## A client's idea of the server's clock, and its round trip (ClientWorld feeds it).
## Every world state carries the server's Time msec ("timestamp"); the smallest gap seen between
## our clock and that one is the least delayed packet, so `server_now()` = our clock minus it. Other
## heroes are drawn INTERP_DELAY_MS behind that (`render_time()`), between two real snapshots
## (NetworkingComponent) - 20 states a second arrive bunched and late, and chasing the newest one
## made them jerk and rubber-band.
extends RefCounted
class_name NetClock

const INTERP_DELAY_MS: float = 100.0  # two state intervals: there is nearly always a snapshot on each side

static var _offset: float = INF  # our msec - server msec, for the least delayed packet
static var rtt_ms: float = 0.0   # ENet's round trip to the server (GameClient peer), ClientWorld updates it
static var _render: float = -1.0
static var _frame: int = -1

static func reset() -> void:
	_offset = INF
	rtt_ms = 0.0
	_render = -1.0
	_frame = -1

static func on_state(server_msec: int) -> void:
	var sample = float(Time.get_ticks_msec() - server_msec)
	if _offset == INF or sample < _offset:
		_offset = sample
	else:
		_offset += (sample - _offset) * 0.002  # follow a slow clock drift, not the jitter

static func known() -> bool:
	return _offset != INF

static func server_now() -> float:
	return Time.get_ticks_msec() - _offset

## The moment other heroes are drawn at. It runs on the physics ticks (steady 1/60 s steps -
## the wall clock isn't: two ticks can fall into one millisecond and the next one jumps) and only
## leans gently towards server_now() - INTERP_DELAY_MS; a big gap (a stall, a new server) snaps.
static func render_time() -> float:
	var frame = Engine.get_physics_frames()
	if frame != _frame:
		var target = server_now() - INTERP_DELAY_MS
		if _render < 0.0 or absf(target - _render) > 250.0:
			_render = target
		else:
			_render += float(frame - _frame) * 1000.0 / Engine.physics_ticks_per_second
			_render += (target - _render) * 0.05
		_frame = frame
	return _render
