# Riyadh Desert Drift

A PS2-style drifting game set in the dunes outside Riyadh at sunset. Slide a white desert
jeep (or one of 13 other cars) across the sand, link long drifts for points, and explore the
desert to discover hidden landmarks, from Najdi mud-brick ruins and a lost city of pillars
to a palm oasis, a rock-cut tomb, an old railway station and a Bedouin camp.

Built with [Godot 4.7](https://godotengine.org). Almost everything (the terrain, ruins,
cockpit, sounds and UI) is generated in code, rendered through a low-poly, vertex-lit PS2
shader.

## Demos

<!--
  Inline players: GitHub only shows a playable video (with sound) in a README for videos
  uploaded through GitHub itself. To turn each link below into a player: edit this README on
  github.com, drag the matching file from demos/web/ into the editor, and replace the link
  line with the https://github.com/user-attachments/assets/... URL GitHub inserts.
-->

### Picking a car

[▶ Watch: picking a car (with sound)](demos/web/pick-a-car.mp4)

### Drifting: chase camera into the cockpit

[▶ Watch: a long drift, switching from the chase camera to the in-car view (with sound)](demos/web/nancy2.mp4)

### Driving from the cockpit

[▶ Watch: cruising across the desert in the in-car view (with sound)](demos/web/borderline.mp4)

## Features

- **Arcade drifting**: kick the back out with the handbrake or with full steer and throttle,
  then steer to hold the angle you want. Points build up with angle × speed and are banked
  when the drift ends.
- **11 landmarks to discover**, each with a drone-shot reveal the first time you find it.
- **Rocket boosters** for short flights, on a fuel tank that recharges on the ground.
- **Chase and in-car cameras**: in the cockpit, desert dust builds up on every window as
  you drive (fast when you drift) and pond water splashes the windshield; press **X** to
  wipe. Plus an animated steering wheel, hands on the horn, gauges and prayer beads.
- **14 cars**, each with LED underglow in its own paint colour.
- **Car stereo** that plays the bundled tracks or your own music, crossfading between songs.
  Even the horn retunes itself to the key of the song that's playing.
- Wildlife (camels, oryx, foxes, lizards, falcons), loose rubble you can knock around, and
  water that splashes when you drive into the oasis.
- Car body roll that lets you ride on two wheels through hard turns.

## Running the game

1. Install [Godot 4.7](https://godotengine.org/download) (standard build).
2. Open Godot, choose **Import**, and select this folder's `project.godot`.
3. Press **F5** (or the ▶ Play button).

## Controls

### Driving

| Key | Action |
| --- | --- |
| **W** | Accelerate |
| **S** | Brake / reverse |
| **A** / **D** | Steer |
| **Space** | Handbrake (start a drift) |
| **Shift** (hold) | Rocket boost (fly). Uses fuel, which refills on the ground |
| **H** (hold) | Horn |
| **X** | Wipe the windows: wipers and washer fluid clean the whole windshield and rear window, a rag cleans the side windows |
| **R** or **V** | Unstuck: drop the car back onto the map at the nearest clear spot |

**Drifting tips:** tap **Space** while steering into a turn, or hold full steer with full
throttle above ~30 km/h. Once you're sliding, steer *into* the slide for a deeper angle, let
go to hold a medium angle, or countersteer to straighten out.

### Camera

| Key | Action |
| --- | --- |
| **C** | Switch between the chase camera and the in-car view |
| **Arrow keys** / two-finger swipe | Look around (orbit in chase view, turn your head in the car) |
| **+** / **−** | Zoom in / out |

### Radio

| Key | Action |
| --- | --- |
| **M** | Radio on / off |
| **E** / **Q** | Next / previous track |
| **]** / **[** | Volume up / down |

### Menus and window

| Key | Action |
| --- | --- |
| **↑** / **↓** (or **W** / **S**) | Move through the menu |
| **←** / **→** (or **A** / **D**) | Change car |
| **Enter** | Select |
| **Esc** | Pause / back |
| **F11** or **Alt + Enter** | Toggle fullscreen |

## Adding your own music

Drop `.ogg` or `.mp3` files into the game's user music folder and they'll show up on the
radio after the bundled tracks:

- **macOS:** `~/Library/Application Support/Godot/app_userdata/Riyadh Desert Drift/music/`
- **Windows:** `%APPDATA%\Godot\app_userdata\Riyadh Desert Drift\music\`
- **Linux:** `~/.local/share/godot/app_userdata/Riyadh Desert Drift/music/`

The folder is created the first time you run the game.

## Credits

See [CREDITS.md](CREDITS.md). Note: the tracks in `assets/music/` are for local playtesting
only and must be replaced before the game is shared or released.
