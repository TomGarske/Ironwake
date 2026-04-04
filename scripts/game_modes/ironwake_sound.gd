class_name IronwakeSound
extends RefCounted

var arena: Node = null

# SFX player pool — allows overlapping sounds (e.g. broadside of 14 cannons).
const SFX_POOL_SIZE: int = 6
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next: int = 0

# Dedicated ambient player (loops continuously, separate from SFX pool).
var _ambient_player: AudioStreamPlayer = null

# Pre-generated WAV caches (built once at init, reused every play call).
var _cannon_fire_wav: AudioStreamWAV = null
var _cannon_fire_distant_wav: AudioStreamWAV = null
var _cannon_hit_wav: AudioStreamWAV = null


func init(arena_node: Node) -> void:
	arena = arena_node
	_build_cached_sounds()


func _build_cached_sounds() -> void:
	_cannon_fire_wav = _generate_cannon_fire_wav()
	_cannon_fire_distant_wav = _generate_cannon_fire_distant_wav()
	_cannon_hit_wav = _generate_cannon_hit_wav()


func _ensure_sfx_pool() -> void:
	if _sfx_players.size() >= SFX_POOL_SIZE:
		return
	for i in range(SFX_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "IronwakeSfx_%d" % i
		arena.add_child(player)
		_sfx_players.append(player)


func _get_next_player() -> AudioStreamPlayer:
	_ensure_sfx_pool()
	var player: AudioStreamPlayer = _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % SFX_POOL_SIZE
	return player


## Legacy compatibility — ensures at least the pool exists.
func ensure_audio_player() -> void:
	_ensure_sfx_pool()


func _sfx_scale() -> float:
	if GameManager != null:
		return float(GameManager.sfx_volume)
	return 1.0


# ---------------------------------------------------------------------------
# Cannon hit sound — wood splintering impact
# ---------------------------------------------------------------------------
func play_cannon_hit_sound() -> void:
	var player: AudioStreamPlayer = _get_next_player()
	player.volume_db = linear_to_db(_sfx_scale())
	player.stream = _cannon_hit_wav
	player.play()


func _generate_cannon_hit_wav() -> AudioStreamWAV:
	var mix_rate: int = 44100
	var duration_sec: float = 0.30
	var sample_count: int = maxi(1, int(duration_sec * float(mix_rate)))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var noise_state: int = 73939
	for i in range(sample_count):
		var t: float = float(i) / float(mix_rate)
		var env: float = exp(-t * 12.0)
		var thud: float = (
			sin(t * TAU * 150.0) * 0.40
			+ sin(t * TAU * 280.0) * 0.25
			+ sin(t * TAU * 420.0) * 0.15
		) * env
		var noise_env: float = exp(-t * 28.0)
		noise_state = (noise_state * 48271) % 2147483647
		var noise: float = (float(noise_state) / 1073741823.5 - 1.0) * noise_env * 0.20
		var s: float = (thud + noise) * 0.55
		s = clampf(s, -1.0, 1.0)
		var v: int = clampi(int(s * 32767.0), -32768, 32767)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.mix_rate = mix_rate
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	wav.data = data
	return wav


# ---------------------------------------------------------------------------
# UI tone (helm lock, sail, fire mode feedback)
# ---------------------------------------------------------------------------
func play_tone(freq_hz: float, duration_sec: float, volume: float) -> void:
	var player: AudioStreamPlayer = _get_next_player()
	var vol: float = _sfx_scale()
	var mix_rate: int = 44100
	var sample_count: int = maxi(1, int(duration_sec * mix_rate))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in range(sample_count):
		var t: float = float(i) / float(mix_rate)
		var envelope: float = clampf(1.0 - (float(i) / float(sample_count)), 0.0, 1.0)
		var sine: float = sin(t * TAU * freq_hz)
		var buzz: float = sign(sin(t * TAU * freq_hz * 0.5))
		var s: float = (sine * 0.65 + buzz * 0.35) * envelope * volume * vol
		var v: int = clampi(int(s * 32767.0), -32768, 32767)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.mix_rate = mix_rate
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	wav.data = data
	player.stream = wav
	player.play()


# ---------------------------------------------------------------------------
# Cannon fire discharge — deep boom when cannons fire (close / player)
# Pre-cached: WAV is generated once at init, just played back here.
# ---------------------------------------------------------------------------
func play_cannon_fire_sound() -> void:
	var player: AudioStreamPlayer = _get_next_player()
	player.volume_db = linear_to_db(_sfx_scale())
	player.stream = _cannon_fire_wav
	player.play()


func _generate_cannon_fire_wav() -> AudioStreamWAV:
	var mix_rate: int = 44100
	var duration_sec: float = 0.90
	var sample_count: int = maxi(1, int(duration_sec * float(mix_rate)))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var noise_state: int = 48271
	var prev_noise: float = 0.0
	var prev_noise2: float = 0.0
	for i in range(sample_count):
		var t: float = float(i) / float(mix_rate)
		# === Initial blast crack — very short, punchy ===
		var crack_env: float = exp(-t * 45.0)
		noise_state = (noise_state * 48271) % 2147483647
		var raw_noise: float = float(noise_state) / 1073741823.5 - 1.0
		prev_noise = prev_noise * 0.72 + raw_noise * 0.28
		prev_noise2 = prev_noise2 * 0.72 + prev_noise * 0.28
		var crack: float = prev_noise2 * crack_env * 0.35
		# === Main body — descending pitch boom ===
		var pitch_sweep: float = 180.0 + 80.0 * exp(-t * 8.0)
		var body_env: float = exp(-t * 4.0)
		var body: float = sin(t * TAU * pitch_sweep) * 0.50 * body_env
		# === Low rumble — sustained resonance ===
		var rumble_env: float = exp(-t * 2.2)
		var rumble: float = (
			sin(t * TAU * 95.0) * 0.35
			+ sin(t * TAU * 142.0) * 0.20
		) * rumble_env
		# === Sub thud ===
		var sub: float = sin(t * TAU * 48.0) * 0.15 * exp(-t * 5.0)
		# === Smoke/air push tail ===
		var tail_env: float = exp(-t * 1.8) * (1.0 - exp(-t * 12.0))
		noise_state = (noise_state * 16807) % 2147483647
		var tail_noise: float = float(noise_state) / 1073741823.5 - 1.0
		var tail: float = tail_noise * tail_env * 0.08
		# === Mix (no volume scaling — applied via player.volume_db) ===
		var s: float = (crack + body + rumble + sub + tail) * 0.70
		s = clampf(s, -1.0, 1.0)
		var v: int = clampi(int(s * 32767.0), -32768, 32767)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.mix_rate = mix_rate
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	wav.data = data
	return wav


# ---------------------------------------------------------------------------
# Cannon fire distant — muffled boom heard when opponents fire
# ---------------------------------------------------------------------------
func play_cannon_fire_distant() -> void:
	var player: AudioStreamPlayer = _get_next_player()
	player.volume_db = linear_to_db(_sfx_scale() * 0.30)
	player.stream = _cannon_fire_distant_wav
	player.play()


func _generate_cannon_fire_distant_wav() -> AudioStreamWAV:
	var mix_rate: int = 44100
	var duration_sec: float = 0.70
	var sample_count: int = maxi(1, int(duration_sec * float(mix_rate)))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var noise_state: int = 73939
	var prev_n: float = 0.0
	var prev_n2: float = 0.0
	for i in range(sample_count):
		var t: float = float(i) / float(mix_rate)
		var onset: float = 1.0 - exp(-t * 18.0)
		var env: float = exp(-t * 2.5) * onset
		var boom: float = (
			sin(t * TAU * 85.0) * 0.40
			+ sin(t * TAU * 128.0) * 0.25
		) * env
		noise_state = (noise_state * 48271) % 2147483647
		var raw_noise: float = float(noise_state) / 1073741823.5 - 1.0
		prev_n = prev_n * 0.82 + raw_noise * 0.18
		prev_n2 = prev_n2 * 0.82 + prev_n * 0.18
		var tail_env: float = exp(-t * 1.8) * (1.0 - exp(-t * 8.0))
		var tail: float = prev_n2 * tail_env * 0.10
		var s: float = (boom + tail) * 0.55
		s = clampf(s, -1.0, 1.0)
		var v: int = clampi(int(s * 32767.0), -32768, 32767)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.mix_rate = mix_rate
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	wav.data = data
	return wav


# ---------------------------------------------------------------------------
# Ambient ocean loop — continuous filtered noise wash
# ---------------------------------------------------------------------------
func start_ocean_ambient() -> void:
	if _ambient_player != null:
		return
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.name = "OceanAmbient"
	arena.add_child(_ambient_player)

	var vol: float = _sfx_scale() * 0.05
	var mix_rate: int = 22050
	var loop_sec: float = 3.0
	var sample_count: int = int(loop_sec * float(mix_rate))
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	var noise_state: int = 73939
	var prev_sample: float = 0.0
	for i in range(sample_count):
		var t: float = float(i) / float(mix_rate)
		noise_state = (noise_state * 48271) % 2147483647
		var raw_noise: float = float(noise_state) / 1073741823.5 - 1.0
		var filtered: float = prev_sample * 0.85 + raw_noise * 0.15
		prev_sample = filtered
		var swell: float = 0.6 + 0.4 * sin(t * TAU * 0.15)
		var s: float = filtered * swell * 0.3 * vol
		s = clampf(s, -1.0, 1.0)
		var v: int = clampi(int(s * 32767.0), -32768, 32767)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF

	var wav := AudioStreamWAV.new()
	wav.mix_rate = mix_rate
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = sample_count
	wav.data = data
	_ambient_player.stream = wav
	_ambient_player.play()


func stop_ocean_ambient() -> void:
	if _ambient_player != null:
		_ambient_player.stop()
		_ambient_player.queue_free()
		_ambient_player = null
