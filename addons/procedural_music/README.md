# Procedural Music Addon — Godot 4

Drop-in procedural background music system. Works on both Web and Desktop builds.

## Installation

1. Copy the `addons/procedural_music/` folder into your Godot project's `addons/` directory.
2. In Godot: **Project → Project Settings → Autoload**
   - Click the folder icon and select `addons/procedural_music/music_manager.gd`
   - Set Node Name to `MusicManager`
   - Enable it. Click Add.
3. That's it. The autoload handles everything else.

## Usage

Call these from any script, any scene:

```gdscript
# Start/stop
MusicManager.play()
MusicManager.stop()

# Jump to a specific song section (useful for scene transitions)
MusicManager.seek_to_phase("chorus1")
# Valid phase IDs: "intro", "build1", "verse1", "chorus1", "break", "chorus2", "outro"

# Volume (0.0 to 1.0)
MusicManager.set_volume(0.5)

# Fade out over a few seconds using a tween
var tween = create_tween()
tween.tween_method(MusicManager.set_volume, 1.0, 0.0, 3.0)
```
