extends Node
## MusicPlayer — autoload singleton that owns the ProceduralMusic engine.
## Listens to GameManager signals for volume/profile changes and provides
## a simple API for screens to request songs by preset name.

const ProceduralMusicScript := preload("res://scripts/audio/procedural_music.gd")

const DEFAULT_MENU_SONG := "spanish-ladies"
const DEFAULT_ARENA_SONG := "spanish-ladies"
const PRESET_DIR := "res://presets/"

## Available songs loaded from manifest.json — array of {id, name}
var available_songs: Array[Dictionary] = []

var _engine: AudioStreamPlayer = null
var _current_song: String = ""
var _base_bpm: float = 115.0

signal song_changed(preset_name: String)

func _ready() -> void:
	_load_manifest()
	_engine = ProceduralMusicScript.new()
	_engine.name = "ProceduralMusic"
	add_child(_engine)

	# Connect to GameManager signals
	if GameManager != null:
		GameManager.audio_volume_changed.connect(_on_audio_volume_changed)
		GameManager.music_profile_changed.connect(_on_music_profile_changed)
		GameManager.music_enabled_changed.connect(_on_music_enabled_changed)
		# Apply initial volume
		_engine.set_volume(GameManager.music_volume)

	# Start with menu music
	play_song(DEFAULT_MENU_SONG)


func _load_manifest() -> void:
	var file := FileAccess.open(PRESET_DIR + "manifest.json", FileAccess.READ)
	if not file:
		push_warning("[MusicPlayer] Could not load manifest.json")
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_warning("[MusicPlayer] Failed to parse manifest.json")
		return
	var data: Dictionary = json.data
	var presets: Array = data.get("presets", [])
	available_songs.clear()
	for p: Variant in presets:
		var pd: Dictionary = p as Dictionary
		available_songs.append({"id": str(pd.get("id", "")), "name": str(pd.get("name", ""))})


func play_song(preset_name: String) -> void:
	if preset_name == _current_song:
		return
	var was_playing: bool = _engine._playing
	if was_playing:
		_engine.stop_music()
	var path := PRESET_DIR + preset_name + ".json"
	if not _engine.apply_preset(path):
		push_warning("[MusicPlayer] Failed to load preset: %s" % path)
		return
	_current_song = preset_name
	_base_bpm = _engine._bpm
	song_changed.emit(_current_song)
	# Apply current profile
	if GameManager != null:
		_engine.set_volume(GameManager.music_volume)
		_apply_profile(GameManager.music_intensity, GameManager.music_speed)
	if GameManager == null or GameManager.music_enabled:
		_engine.play_music()


func stop() -> void:
	_engine.stop_music()


func get_current_song() -> String:
	return _current_song


func _on_audio_volume_changed(music_vol: float, _sfx_vol: float) -> void:
	_engine.set_volume(music_vol)


func _on_music_profile_changed(intensity: float, speed: float, _tone: float) -> void:
	_apply_profile(intensity, speed)


func _on_music_enabled_changed(enabled: bool) -> void:
	if enabled:
		if not _engine._playing and not _current_song.is_empty():
			_engine.play_music()
	else:
		_engine.stop_music()


func _apply_profile(intensity: float, speed: float) -> void:
	# Speed scales BPM around the preset's base tempo
	var scaled_bpm := _base_bpm * speed
	_engine.set_bpm(scaled_bpm)
	# Intensity scales the voice and drone layers for a fuller/thinner sound
	_engine.set_layer("voiceBass", intensity)
	_engine.set_layer("voiceBaritone", intensity)
	_engine.set_layer("voiceTenor", intensity)
	_engine.set_layer("drone", intensity)
