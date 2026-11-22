class_name ProceduralIdle
extends RefCounted

## Layered natural idle animation generator:
## - Breathing (chest / upperChest / shoulders)
## - Automatic blinking (natural quick close, slightly slower open)
## - Eye saccades (subtle natural micro-movements)
## - Subtle standing weight shift (hips / spine)

var enabled: bool = true
var breathing: bool = true
var blink: bool = true
var saccade: bool = true
var sway: bool = true
var intensity: float = 1.0

var _time: float = 0.0
var _blink_timer: float = 2.5
var _blink_progress: float = -1.0 # < 0 means open
var _saccade_timer: float = 1.2
var _saccade_cur: Vector3 = Vector3.ZERO
var _saccade_target: Vector3 = Vector3.ZERO
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 20261119


func apply_params(params: Dictionary) -> void:
	if params.has("enabled"):
		enabled = bool(params["enabled"])
	if params.has("breathing"):
		breathing = bool(params["breathing"])
	if params.has("blink"):
		blink = bool(params["blink"])
	if params.has("saccade"):
		saccade = bool(params["saccade"])
	if params.has("sway"):
		sway = bool(params["sway"])
	if params.has("intensity"):
		intensity = clampf(float(params["intensity"]), 0.0, 2.5)


func get_params() -> Dictionary:
	return {
		"enabled": enabled,
		"breathing": breathing,
		"blink": blink,
		"saccade": saccade,
		"sway": sway,
		"intensity": intensity,
	}


func sample_idle(dt: float) -> Dictionary:
	var bones: Dictionary = {}
	var hips_delta := Vector3.ZERO
	var blink_w := 0.0
	var saccade_off := Vector3.ZERO

	if not enabled or intensity <= 0.001:
		return {
			"bones": bones,
			"hips_delta": hips_delta,
			"blink_weight": 0.0,
			"saccade_offset": Vector3.ZERO,
		}

	_time += dt
	var k := intensity

	# 1. Breathing (~15 breaths/min = 0.25 Hz)
	if breathing:
		var b := sin(_time * 1.65)
		bones["chest"] = Quaternion.from_euler(Vector3(deg_to_rad(1.6 * b * k), 0.0, 0.0))
		bones["upperChest"] = Quaternion.from_euler(Vector3(deg_to_rad(1.2 * b * k), 0.0, 0.0))
		# 肩はすくめない。左右の肩を鏡写しに回すと、後ろや前で手を組む動きで両手が左右へ離れたり寄ったりする

	# 2. Subtle standing sway
	if sway:
		var s1 := sin(_time * 0.72)
		var s2 := cos(_time * 0.43)
		hips_delta = Vector3(0.007 * s1 * k, 0.003 * s2 * k, 0.0)
		bones["hips"] = Quaternion.from_euler(Vector3(0.0, deg_to_rad(1.2 * s2 * k), deg_to_rad(0.9 * s1 * k)))
		bones["spine"] = Quaternion.from_euler(Vector3(deg_to_rad(0.8 * s2 * k), deg_to_rad(-0.9 * s2 * k), deg_to_rad(-0.6 * s1 * k)))
		bones["head"] = Quaternion.from_euler(Vector3(deg_to_rad(0.9 * sin(_time * 0.53) * k), deg_to_rad(1.4 * s2 * k), 0.0))

	# 3. Natural blinking (70ms close, 120ms open)
	if blink:
		if _blink_progress < 0.0:
			_blink_timer -= dt
			if _blink_timer <= 0.0:
				_blink_progress = 0.0
		else:
			_blink_progress += dt
			var close_t := 0.075
			var open_t := 0.135
			if _blink_progress < close_t:
				blink_w = _blink_progress / close_t
			elif _blink_progress < close_t + open_t:
				blink_w = 1.0 - ((_blink_progress - close_t) / open_t)
			else:
				blink_w = 0.0
				_blink_progress = -1.0
				_blink_timer = _rng.randf_range(2.2, 5.4)

	# 4. Eye saccades
	if saccade:
		_saccade_timer -= dt
		if _saccade_timer <= 0.0:
			_saccade_timer = _rng.randf_range(0.6, 2.4)
			_saccade_target = Vector3(
				_rng.randf_range(-0.14, 0.14) * k,
				_rng.randf_range(-0.08, 0.08) * k,
				0.0
			)
		_saccade_cur = _saccade_cur.lerp(_saccade_target, clampf(dt * 10.0, 0.0, 1.0))
		saccade_off = _saccade_cur

	return {
		"bones": bones,
		"hips_delta": hips_delta,
		"blink_weight": clampf(blink_w, 0.0, 1.0),
		"saccade_offset": saccade_off,
	}
