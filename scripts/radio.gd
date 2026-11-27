## In-car stereo: plays the songs in res://assets/music (bundled with the game) plus any
## .ogg/.mp3 the player drops into user://music. Muffled when heard from outside the car,
## ducked under the pause menu.
extends Node

signal track_changed(title: String, index: int, count: int)
signal volume_changed(level: int, max_level: int)
signal power_changed(on: bool)

const BUNDLED_DIR := "res://assets/music/"
const USER_DIR := "user://music/"
const BUS := "Music"
const VOL_STEPS := 10
const OUTSIDE_DB := -4.0       # extra attenuation in chase view
const DUCK_DB := -8.0          # extra attenuation under the pause menu
const MUFFLE_HZ := 2500.0
# Chase-cam zoom nudges the music: a touch fuller up close, quieter and more muffled far away.
const ZOOM_DB_PER_DOUBLING := -2.5
const ZOOM_DB_RANGE := Vector2(-6.0, 2.0)
const ZOOM_MUFFLE_EXP := -0.35    # cutoff = MUFFLE_HZ * zoom^this
# Bass boost (dB) on the stereo's low EQ bands: 32 Hz, 100 Hz, 320 Hz.
const BASS_DB := [6.0, 7.0, 2.0]
const BASS_HEADROOM_DB := -4.0   # pre-gain so the boost doesn't clip loud tracks
# Fades (s). Skips/power use the short ones; a song ending on its own crossfades longer.
const FADE_IN := 0.35
const FADE_OUT := 0.6
const END_CROSSFADE := 2.0
# Dead air in the bundled files, measured with ffmpeg silencedetect (-45 dB):
# file -> [start, end] seconds of actual audio. Tracks not listed play in full.
# Musical key of each bundled song, for the horn to harmonize with. Detected offline from
# the audio (tuning-corrected chroma vs. Krumhansl key profiles):
# file -> [tonic pitch class (C=0), horn interval (3 = minor 3rd, 4 = major 3rd,
# 7 = 5th where major/minor or the tonic was ambiguous), tuning offset in cents].
const KEYS := {
	"01 - nancy ajram freestyle.mp3": [1, 3, 2],          # C# minor
	"02 - Bad Girls.mp3": [1, 7, 6],                      # C# (5th)
	"03 - Amr Diab - Ana Ayesh.mp3": [10, 3, 5],          # A# minor
	"04 - Amr Diab - Waadtak.mp3": [0, 3, 31],            # C minor, tuned +31c
	"05 - Omry Maak.mp3": [4, 3, -3],                     # E minor
	"06 - Tame Impala - Borderline.mp3": [7, 3, -1],      # G minor
	"07 - Travis Scott - Skeletons.mp3": [7, 3, 4],       # G minor
	"08 - CeeLo Green - Bright Lights Bigger City.mp3": [11, 7, -2],  # B (5th)
	"09 - Tamally Maak.mp3": [0, 3, 1],                   # C minor
	"10 - Jorge Ben Jor - Take It Easy My Brother Charles.mp3": [8, 3, 41],  # G# minor, +41c
	"11 - Genie In a Bottle.mp3": [5, 3, -1],             # F minor
	"12 - Rich Girl - Desert Mashup.mp3": [10, 4, 3],     # A# major
	"13 - A Whole New World (Arabic Cover).mp3": [11, 4, -1],  # B major
	"14 - Amr Diab - Kan Tayeb.mp3": [9, 4, -2],          # A major
}
const TRIMS := {
	"03 - Amr Diab - Ana Ayesh.mp3": [0.38, 225.11],
	"04 - Amr Diab - Waadtak.mp3": [2.43, 225.14],
	"05 - Omry Maak.mp3": [0.26, 324.90],
	"06 - Tame Impala - Borderline.mp3": [0.35, 236.09],
	"07 - Travis Scott - Skeletons.mp3": [0.70, 145.98],
	"08 - CeeLo Green - Bright Lights Bigger City.mp3": [0.22, 217.70],
	"09 - Tamally Maak.mp3": [0.46, 268.46],
	"10 - Jorge Ben Jor - Take It Easy My Brother Charles.mp3": [0.22, 154.75],
	"11 - Genie In a Bottle.mp3": [0.97, 217.37],
	"14 - Amr Diab - Kan Tayeb.mp3": [0.59, 317.91],
	"01 - nancy ajram freestyle.mp3": [0.0, 98.84],
	"02 - Bad Girls.mp3": [0.0, 227.38],
	"12 - Rich Girl - Desert Mashup.mp3": [0.0, 141.60],
	"13 - A Whole New World (Arabic Cover).mp3": [0.0, 155.66],
}

var tracks: Array[Dictionary] = []   # {title, path, user}
var index := 0
var on := false
var volume := 7                      # 0..VOL_STEPS
var shuffle := false

# Two players so one song can fade out while the next fades in.
var _players: Array[AudioStreamPlayer] = []
var _tweens: Array[Tween] = [null, null]
var _cur := 0
var _start_at := 0.0               # where the current song's audio actually begins
var _end_at := 0.0                 # where it actually ends (before trailing silence)
var _bus := -1
var _lowpass: AudioEffectLowPassFilter
var _lowpass_idx := 0
var _cockpit := false
var _ducked := false
var _target_db := 0.0
var _zoom := 1.0


func _ready() -> void:
	_setup_bus()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		p.finished.connect(_on_finished.bind(i))
		add_child(p)
		_players.append(p)
	_scan()
	_apply_mix(true)


## Key of the song playing now (see KEYS), or [] when the radio is off / the song is unknown.
func current_key() -> Array:
	if not on or not has_tracks():
		return []
	return KEYS.get(tracks[index].path.get_file(), [])


func has_tracks() -> bool:
	return not tracks.is_empty()


# --- Controls ----------------------------------------------------------------

func toggle() -> void:
	set_on(not on)


func set_on(v: bool) -> void:
	if not has_tracks():
		on = false
		power_changed.emit(false)
		return
	on = v
	if on:
		_play_current()
	else:
		_fade_out(_cur, FADE_OUT)
	power_changed.emit(on)


func next() -> void:
	if not has_tracks():
		return
	_pick_next()
	_change_track()


func _pick_next() -> void:
	if shuffle and tracks.size() > 1:
		var n := index
		while n == index:
			n = randi() % tracks.size()
		index = n
	else:
		index = wrapi(index + 1, 0, tracks.size())


func prev() -> void:
	if not has_tracks():
		return
	# Like a real stereo: a few seconds into a song, "prev" restarts it.
	var p := _players[_cur]
	if on and p.playing and p.get_playback_position() - _start_at > 3.0:
		_start(p.stream, FADE_OUT)
		_emit_track()
		return
	index = wrapi(index - 1, 0, tracks.size())
	_change_track()


func volume_step(d: int) -> void:
	volume = clampi(volume + d, 0, VOL_STEPS)
	_apply_mix(d == 0)
	if d != 0:
		volume_changed.emit(volume, VOL_STEPS)


func set_cockpit(v: bool) -> void:
	_cockpit = v
	_apply_mix(false)


## Chase-camera zoom factor (1 = default distance; cockpit passes 1).
func set_zoom(z: float) -> void:
	if absf(z - _zoom) < 0.01:
		return
	_zoom = z
	_lowpass.cutoff_hz = clampf(MUFFLE_HZ * pow(z, ZOOM_MUFFLE_EXP), 800.0, 8000.0)
	_apply_mix(false)


func set_ducked(v: bool) -> void:
	_ducked = v
	_apply_mix(false)


# --- Internals ---------------------------------------------------------------

func _change_track() -> void:
	if on:
		_play_current()
	else:
		_emit_track()


func _play_current(fade_out := FADE_OUT) -> void:
	index = clampi(index, 0, tracks.size() - 1)
	var stream := _load(tracks[index])
	if stream == null:
		# Skip unreadable files instead of going silent.
		tracks.remove_at(index)
		if not has_tracks():
			set_on(false)
			return
		_play_current(fade_out)
		return
	var trim: Array = TRIMS.get(tracks[index].path.get_file(), [])
	_start_at = trim[0] if trim else 0.0
	_end_at = trim[1] if trim else stream.get_length()
	_start(stream, fade_out)
	_emit_track()


## Fade the current song out and the given one in on the other player (a crossfade).
func _start(stream: AudioStream, fade_out: float) -> void:
	_fade_out(_cur, fade_out)
	_cur = 1 - _cur
	var p := _players[_cur]
	if _tweens[_cur]:
		_tweens[_cur].kill()
	p.stream = stream
	p.volume_linear = 0.0
	p.play(_start_at)
	_tweens[_cur] = create_tween()
	_tweens[_cur].tween_property(p, "volume_linear", 1.0, FADE_IN)


func _fade_out(i: int, time: float) -> void:
	var p := _players[i]
	if _tweens[i]:
		_tweens[i].kill()
	if not p.playing:
		return
	_tweens[i] = create_tween()
	_tweens[i].tween_property(p, "volume_linear", 0.0, time)
	_tweens[i].tween_callback(p.stop)


func _emit_track() -> void:
	track_changed.emit(tracks[index].title, index, tracks.size())


func _on_finished(i: int) -> void:
	# Fallback for songs that end before the crossfade point (e.g. very short user files).
	if on and i == _cur:
		_advance()


## Song ended on its own: move on with a long, smooth crossfade.
func _advance() -> void:
	_pick_next()
	_play_current(END_CROSSFADE)


func _load(t: Dictionary) -> AudioStream:
	var path: String = t.path
	if not t.user:
		return load(path) as AudioStream
	var ext := path.get_extension().to_lower()
	var s: AudioStream = null
	if ext == "ogg":
		s = AudioStreamOggVorbis.load_from_file(path)
	elif ext == "mp3":
		s = AudioStreamMP3.load_from_file(path)
	if s != null and "loop" in s:
		s.loop = false
	return s


func _scan() -> void:
	tracks.clear()
	# ResourceLoader.list_directory also works in exported builds (DirAccess only sees .import files there).
	if DirAccess.dir_exists_absolute(BUNDLED_DIR):
		var names := Array(ResourceLoader.list_directory(BUNDLED_DIR))
		names.sort()
		for f: String in names:
			if f.get_extension().to_lower() in ["ogg", "mp3"]:
				tracks.append({"title": _title(f), "path": BUNDLED_DIR + f, "user": false})
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var user := Array(DirAccess.get_files_at(USER_DIR))
	user.sort()
	for f: String in user:
		if f.get_extension().to_lower() in ["ogg", "mp3"]:
			tracks.append({"title": _title(f), "path": USER_DIR + f, "user": true})


## "03 - My Song.ogg" -> "MY SONG"
static func _title(file: String) -> String:
	var s := file.get_basename()
	var re := RegEx.create_from_string("^\\s*\\d+\\s*[-_.]\\s*")
	s = re.sub(s, "")
	return s.replace("_", " ").strip_edges().to_upper()


func _setup_bus() -> void:
	_bus = AudioServer.get_bus_index(BUS)
	if _bus == -1:
		AudioServer.add_bus()
		_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus, BUS)
		AudioServer.set_bus_send(_bus, "Master")
	# Bass boost first, then the outside-the-car muffle, then a limiter to catch peaks.
	var pre := AudioEffectAmplify.new()
	pre.volume_db = BASS_HEADROOM_DB
	AudioServer.add_bus_effect(_bus, pre)
	var eq := AudioEffectEQ6.new()
	for i in BASS_DB.size():
		eq.set_band_gain_db(i, BASS_DB[i])
	AudioServer.add_bus_effect(_bus, eq)
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = MUFFLE_HZ
	AudioServer.add_bus_effect(_bus, _lowpass)
	_lowpass_idx = AudioServer.get_bus_effect_count(_bus) - 1
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.5
	AudioServer.add_bus_effect(_bus, limiter)


func _apply_mix(instant: bool) -> void:
	AudioServer.set_bus_effect_enabled(_bus, _lowpass_idx, not _cockpit)
	var base := linear_to_db(pow(volume / float(VOL_STEPS), 2.0)) if volume > 0 else -80.0
	var zoom_db := clampf(ZOOM_DB_PER_DOUBLING * log(_zoom) / log(2.0), ZOOM_DB_RANGE.x, ZOOM_DB_RANGE.y)
	_target_db = base + (0.0 if _cockpit else OUTSIDE_DB + zoom_db) + (DUCK_DB if _ducked else 0.0)
	if instant:
		AudioServer.set_bus_volume_db(_bus, _target_db)


func _process(delta: float) -> void:
	# Start crossfading into the next song just before this one's trailing silence.
	var p := _players[_cur]
	if on and p.playing and _end_at > END_CROSSFADE * 2.0 and p.get_playback_position() >= _end_at - END_CROSSFADE:
		_advance()
	# Smooth volume changes so ducking/view switches don't click.
	var cur := AudioServer.get_bus_volume_db(_bus)
	if absf(cur - _target_db) > 0.05:
		AudioServer.set_bus_volume_db(_bus, move_toward(cur, _target_db, 40.0 * delta))
