class_name IronwakeSound
extends RefCounted

var arena: Node = null
var _sfx_player: AudioStreamPlayer = null


func init(arena_node: Node) -> void:
	arena = arena_node


func ensure_audio_player() -> void:
	if _sfx_player != null:
		return
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.name = "IronwakeSfxPlayer"
	arena.add_child(_sfx_player)


func play_cannon_hit_sound() -> void:
	ensure_audio_player()
	var sfx_scale: float = 1.0
	if GameManager != null:
		sfx_scale = float(GameManager.sfx_volume)
	var mix_rate: int = 44100
	var duration_sec: float = 0.16
	var sample_count: int = maxi(1, int(duration_sec * float(mix_rate)))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in range(sample_count):
		var t: float = float(i) / float(mix_rate)
		var env: float = exp(-t * 22.0)
		var s: float = (
			sin(t * TAU * 112.0) * 0.52
			+ sin(t * TAU * 268.0) * 0.28
			+ sin(t * TAU * 440.0) * 0.14
		) * env * 0.48 * sfx_scale
		s = clampf(s, -1.0, 1.0)
		var v: int = int(clampi(int(s * 32767.0), -32768, 32767))
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.mix_rate = mix_rate
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	wav.data = data
	_sfx_player.stream = wav
	_sfx_player.play()


func play_tone(freq_hz: float, duration_sec: float, volume: float) -> void:
	ensure_audio_player()
	var sfx_scale: float = 1.0
	if GameManager != null:
		sfx_scale = float(GameManager.sfx_volume)
	var mix_rate: int = 44100
	var sample_count: int = maxi(1, int(duration_sec * mix_rate))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in range(sample_count):
		var t: float = float(i) / float(mix_rate)
		var envelope: float = clampf(1.0 - (float(i) / float(sample_count)), 0.0, 1.0)
		var sine: float = sin(t * TAU * freq_hz)
		var buzz: float = sign(sin(t * TAU * freq_hz * 0.5))
		var s: float = (sine * 0.65 + buzz * 0.35) * envelope * volume * sfx_scale
		var v: int = int(clampi(int(s * 32767.0), -32768, 32767))
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.mix_rate = mix_rate
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	wav.data = data
	_sfx_player.stream = wav
	_sfx_player.play()
