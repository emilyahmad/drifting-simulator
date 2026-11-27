## Two-tone car horn that tunes itself to the song on the radio. Hold H to honk.
## Each key's horn sound is a 1-second seamless loop built ahead of time (in the background),
## so a honk is just play() on a ready sample: no delay, and no hitch when the song changes.
extends AudioStreamPlayer3D

const RATE := 44100
const LOOP_FRAMES := RATE        # 1 s loop: any whole-Hz frequency repeats seamlessly
const TABLE_SIZE := 2048
const VOLUME_DB := -10.0
const RELEASE := 0.05            # s fade-out so letting go doesn't click
const DEFAULT_KEY := []          # radio off: the classic 400/500 Hz horn

var enabled := true              # car turns this off in menus / cinematics
var _held := false


## True while the horn is sounding (the cockpit animates the driver's hand from this).
func is_honking() -> bool:
	return _held
var _tween: Tween
var _key: Array = DEFAULT_KEY
var _cache := {}                 # "f1:f2" -> AudioStreamWAV
var _task := -1                  # background build task (must finish before we're freed)
static var _table := PackedFloat32Array()


func _ready() -> void:
	_build_table()
	volume_db = VOLUME_DB
	unit_size = 12.0
	max_db = 0.0
	stream = _get_or_build(_freqs(DEFAULT_KEY))


## Build the horn sounds for these keys in the background so switching songs never hitches.
func prepare(keys: Array) -> void:
	var todo := []
	for k in keys:
		var f := _freqs(k)
		if not _cache.has(_id(f)) and not todo.has(f):
			todo.append(f)
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
	_task = WorkerThreadPool.add_task(func():
		for f in todo:
			_store.call_deferred(_id(f), _build(f)))


## Key = [pitch class 0-11 (C=0), interval to the 2nd note in semitones, tuning in cents].
func set_key(key: Array) -> void:
	if key == _key:
		return
	_key = key
	var wav := _get_or_build(_freqs(key))
	if _held and playing:
		var pos := get_playback_position()
		stream = wav
		play(pos)
	else:
		stream = wav


func _exit_tree() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


# --- Input -------------------------------------------------------------------

# Event-driven so the honk starts the moment the key goes down, not on the next physics tick.
func _input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action("honk"):
		return
	_set_held(event.is_pressed() and enabled)


func _process(_delta: float) -> void:
	if _held and (not enabled or not Input.is_action_pressed("honk")):
		_set_held(false)


func _set_held(on: bool) -> void:
	if on == _held:
		return
	_held = on
	if _tween:
		_tween.kill()
	if on:
		volume_db = VOLUME_DB
		play()
	else:
		_tween = create_tween()
		_tween.tween_property(self, "volume_db", -60.0, RELEASE)
		_tween.tween_callback(stop)


# --- Synthesis ---------------------------------------------------------------

## Horn pitches for a key: the tonic (placed in the 330-660 Hz horn range) and the note
## `interval` semitones above it, shifted by the song's tuning, rounded to whole Hz.
static func _freqs(key: Array) -> Vector2i:
	if key.is_empty():
		return Vector2i(400, 500)
	var f := 440.0 * pow(2.0, (60 + int(key[0]) - 69 + float(key[2]) / 100.0) / 12.0)
	if f < 330.0:
		f *= 2.0
	return Vector2i(roundi(f), roundi(f * pow(2.0, int(key[1]) / 12.0)))


static func _id(f: Vector2i) -> String:
	return "%d:%d" % [f.x, f.y]


func _store(id: String, wav: AudioStreamWAV) -> void:
	_cache[id] = wav
	if _id(_freqs(_key)) == id and stream != wav and not playing:
		stream = wav


func _get_or_build(f: Vector2i) -> AudioStreamWAV:
	var id := _id(f)
	if not _cache.has(id):
		_cache[id] = _build(f)
	return _cache[id]


## One cycle of the horn's tone: a stack of harmonics (odd ones stronger, like a horn's
## buzzing diaphragm), lightly saturated.
static func _build_table() -> void:
	if not _table.is_empty():
		return
	_table.resize(TABLE_SIZE)
	var peak := 0.0
	for i in TABLE_SIZE:
		var ph := float(i) / TABLE_SIZE * TAU
		var s := 0.0
		for n in range(1, 13):
			s += sin(ph * n) * (1.0 if n % 2 == 1 else 0.55) / pow(n, 1.1)
		_table[i] = s
		peak = maxf(peak, absf(s))
	for i in TABLE_SIZE:
		_table[i] = tanh(_table[i] / peak * 1.6)


## Both notes, each doubled 1 Hz sharp for a gentle shimmer. With whole-Hz frequencies every
## voice completes a whole number of cycles in the 1 s loop, so it repeats with no seam.
static func _build(f: Vector2i) -> AudioStreamWAV:
	var voices := [[f.x, 0.5], [f.x + 1, 0.35], [f.y, 0.45], [f.y + 1, 0.3]]
	var data := PackedByteArray()
	data.resize(LOOP_FRAMES * 2)
	for i in LOOP_FRAMES:
		var s := 0.0
		for v in voices:
			s += _table[(i * int(v[0]) % RATE) * TABLE_SIZE / RATE] * float(v[1])
		data.encode_s16(i * 2, int(tanh(s * 0.7) * 0.5 * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = LOOP_FRAMES
	return wav
