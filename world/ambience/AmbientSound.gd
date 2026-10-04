## The island's background sound, synthesized on the fly (the project has no audio files): wind
## in gusts, water babbling louder near lakes and waterfalls, birds chirping in the day and
## crickets at night / at sunset. One AudioStreamGenerator on the master bus (GameSettings
## volume applies). GameEnvironment adds it next to AmbientLife; looks at the same camera spot.
extends Node
class_name AmbientSound

const RATE: float = 16000.0     # enough for chirps and crickets, light on the CPU
const WIND_VOLUME: float = 0.07
const WATER_VOLUME: float = 0.1
const BIRD_VOLUME: float = 0.05
const CRICKET_VOLUME: float = 0.018
const WATER_HEARING: float = 14.0   # world units: water this close can be heard

var _player: AudioStreamPlayer = null
var _playback: AudioStreamGeneratorPlayback = null
var _rng := RandomNumberGenerator.new()
var _t: float = 0.0                  # seconds of sound made so far
# filters / state
var _wind_lp: float = 0.0
var _wind_lp2: float = 0.0
var _water_lp: float = 0.0
var _water_slow: float = 0.0
var _water_amp: float = 0.0
var _water_near: float = 0.0         # 0..1 how close the water is (updated twice a second)
var _water_target: float = 0.0
var _day: float = 1.0                # birds vs crickets
var _chirps: Array = []              # [start_t, length, f0, f1]
var _next_song: float = 1.0
var _check: float = 0.0

func _ready():
	if DisplayServer.get_name() == "headless" or AudioServer.get_bus_count() == 0:
		set_process(false)
		return
	_rng.randomize()
	var stream = AudioStreamGenerator.new()
	stream.mix_rate = RATE
	stream.buffer_length = 0.3
	_player = AudioStreamPlayer.new()
	_player.stream = stream
	_player.volume_db = -4.0
	Sfx.ensure_buses()
	_player.bus = "Ambient"  # its own slider in Settings
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()

func _process(delta: float):
	if not _playback:
		return
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		_listen_around()
	_water_near = move_toward(_water_near, _water_target, delta * 0.6)
	var environment = get_parent() as GameEnvironment
	var dusk = environment.dusk if environment else 0.0
	var dark = clamp((1.0 - MapEvents.sight_factor) * 2.0, 0.0, 1.0)
	_day = move_toward(_day, 1.0 - max(dark, smoothstep(0.7, 1.0, dusk)), delta * 0.3)

	var frames = _playback.get_frames_available()
	if frames <= 0:
		return
	var buffer = PackedVector2Array()
	buffer.resize(frames)
	var dt = 1.0 / RATE
	for i in frames:
		_t += dt
		var s = _wind() + _water() + _birds() + _crickets()
		s = clamp(s, -1.0, 1.0)
		buffer[i] = Vector2(s, s)
	_playback.push_buffer(buffer)

## How close is water to the camera's spot (lakes, rivers, waterfalls)?
func _listen_around() -> void:
	var camera = get_viewport().get_camera_3d() if get_viewport() else null
	if not camera:
		return
	var forward = -camera.global_transform.basis.z
	var spot = camera.global_position
	if forward.y < -0.05:
		spot += forward * ((camera.global_position.y - 1.0) / -forward.y)
	var best = INF
	var grid = get_tree().get_first_node_in_group("hex_grid") as HexGrid
	if grid:
		var here = grid.world_to_hex(spot - grid.global_position)
		for dq in range(-4, 5):
			for dr in range(-4, 5):
				var tile = grid.get_tile(here + Vector2i(dq, dr))
				if tile and tile.is_water():
					best = min(best, Vector2(tile.global_position.x - spot.x, tile.global_position.z - spot.z).length())
	for fall in get_tree().get_nodes_in_group("waterfalls"):
		var at: Vector3 = fall.get_meta("sound_at", Vector3.INF)
		best = min(best, Vector2(at.x - spot.x, at.z - spot.z).length() * 0.6)  # waterfalls are louder
	_water_target = clamp(1.0 - best / WATER_HEARING, 0.0, 1.0)

## Soft rumble with slow gusts
func _wind() -> float:
	var white = _rng.randf() * 2.0 - 1.0
	_wind_lp += (white - _wind_lp) * 0.02
	_wind_lp2 += (_wind_lp - _wind_lp2) * 0.05
	var gust = 0.55 + 0.3 * sin(_t * 0.23) + 0.2 * sin(_t * 0.61 + 1.3) + 0.1 * sin(_t * 1.7)
	return _wind_lp2 * 9.0 * gust * WIND_VOLUME

## Babbling: bright noise with a bubbling, uneven loudness
func _water() -> float:
	if _water_near <= 0.001:
		return 0.0
	var white = _rng.randf() * 2.0 - 1.0
	_water_lp += (white - _water_lp) * 0.35
	_water_slow += (white - _water_slow) * 0.04
	var bright = _water_lp - _water_slow  # a rough band-pass
	if _rng.randf() < 0.002:
		_water_amp = _rng.randf_range(0.4, 1.0)
	_water_amp = move_toward(_water_amp, 0.55, 0.00005)
	return bright * _water_amp * _water_near * WATER_VOLUME * 2.0

## Short whistled chirps in little songs, now and then
func _birds() -> float:
	if _day < 0.05:
		return 0.0
	if _t >= _next_song:
		var notes = _rng.randi_range(2, 6)
		var at = _t
		var base = _rng.randf_range(2200.0, 4200.0)
		for n in notes:
			var length = _rng.randf_range(0.05, 0.13)
			var rise = _rng.randf_range(-900.0, 1400.0)
			_chirps.append([at, length, base, base + rise])
			at += length + _rng.randf_range(0.03, 0.12)
		_next_song = at + _rng.randf_range(1.5, 6.0)
	var s = 0.0
	var i = 0
	while i < _chirps.size():
		var c = _chirps[i]
		var local = _t - c[0]
		if local > c[1]:
			_chirps.remove_at(i)
			continue
		if local >= 0.0:
			var k = local / c[1]
			var freq = lerp(float(c[2]), float(c[3]), k)
			var env = sin(k * PI)
			s += sin(TAU * freq * local) * env * env
		i += 1
	return s * BIRD_VOLUME * _day

## Pulsing crickets once it gets dark
func _crickets() -> float:
	var night = 1.0 - _day
	if night < 0.05:
		return 0.0
	var pulse = max(sin(TAU * 28.0 * _t), 0.0) * max(sin(TAU * 0.9 * _t), 0.0)
	return sin(TAU * 4600.0 * _t) * pulse * night * CRICKET_VOLUME
