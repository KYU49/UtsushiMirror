extends RefCounted
## 外部 (MCP / WebSocket) からの「自然にしゃべる (口を動かす)」「自然に歩く」「その場で回る」と、
## ポーズをなめらかに移すことを受け持つ。
## app_controller の _process から毎フレーム process() を呼ぶ。

const MOUTH := ["aa", "ih", "ou", "ee", "oh"]

var ctl  # app_controller

# ---------------------------------------------------------------- しゃべる
var talking := false
var _talk_t := 0.0
var _talk_dur := 0.0
var _segs: Array = []  # [{t0, t1, v: "aa"|...|"" (口を閉じる), amp}]
var _seg_i := 0
var _mouth := {}  # 今の口の形の重み (なめらかに追いかける)

# ---------------------------------------------------------------- 歩く
var walking := false
var _w_phase := ""  # "turn" | "move" | "stop" | "face"
var _w_from := Vector3.ZERO
var _w_to := Vector3.ZERO
var _w_dist := 0.0
var _w_speed := 0.8
var _w_t := 0.0
var _w_move_dur := 0.0
var _w_yaw_target := 0.0
var _w_face_camera := true
var _w_prev_anim := {}
var _w_clip := ""
const TURN_DEG_PER_SEC := 240.0
const ACCEL_SEC := 0.3

# ---------------------------------------------------------------- その場で回る
var turning := false
var _t_from := 0.0
var _t_delta := 0.0
var _t_dur := 0.0
var _t_t := 0.0

# ---------------------------------------------------------------- ポーズをなめらかに移す
var _blend := {}  # bone -> {mode: "slerp"|"in"|"out", from, to, from_w}
var _blend_t := 0.0
var _blend_dur := 0.0


func _init(controller) -> void:
	ctl = controller


func state() -> Dictionary:
	return {
		"talking": talking,
		"talk_remaining_sec": maxf(0.0, _talk_dur - _talk_t) if talking else 0.0,
		"walking": walking,
		"walk_phase": _w_phase if walking else "",
		"turning": turning,
		"blending_pose": not _blend.is_empty(),
	}


func process(dt: float) -> void:
	if talking:
		_process_talk(dt)
	if walking:
		_process_walk(dt)
	if turning:
		_process_turn(dt)
	if not _blend.is_empty():
		_process_blend(dt)


# =====================================================================
# その場で回る
# =====================================================================

## params:
##   angle_deg: 回る角度 (既定 360 = 1 回転)。+ で上から見て反時計回り (キャラクターから見て左回り)
##   to: "camera" にすると、カメラの方を向くまで回る (angle_deg は足し算の回転として使う。既定 0)
##   duration_sec: かける時間 (既定は角度に合わせて。1 回転で約 0.9 秒)
func start_turn(params: Dictionary) -> Dictionary:
	if ctl.current_vrm == null:
		return {"ok": false, "error": "モデルが読み込まれていません"}
	if walking:
		return {"ok": false, "error": "歩いている途中です"}
	var root: Node3D = ctl.model_root
	var delta := 0.0
	if str(params.get("to", "")) == "camera":
		var cam: Vector3 = ctl.camera_rig.get_camera_world_position()
		var p := root.position
		delta = angle_difference(root.rotation.y, atan2(cam.x - p.x, cam.z - p.z))
		var extra := float(params.get("angle_deg", 0.0))
		if absf(extra) > 0.5:
			# 余分に回るときは、向く方向と同じ回り方にそろえる
			delta += deg_to_rad(absf(extra)) * (signf(extra) if absf(delta) < 0.01 else signf(delta))
	else:
		delta = deg_to_rad(float(params.get("angle_deg", 360.0)))
	var dur := float(params.get("duration_sec", 0.0))
	if dur <= 0.0:
		dur = 0.15 + absf(rad_to_deg(delta)) / 480.0
	_t_from = root.rotation.y
	_t_delta = delta
	_t_dur = clampf(dur, 0.05, 30.0)
	_t_t = 0.0
	turning = true
	return {"ok": true, "angle_deg": snappedf(rad_to_deg(delta), 0.1), "duration_sec": snappedf(_t_dur, 0.01)}


func stop_turn() -> void:
	turning = false


func _process_turn(dt: float) -> void:
	if ctl.current_vrm == null:
		turning = false
		return
	_t_t += dt
	var k := clampf(_t_t / _t_dur, 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)  # ゆっくり始まって、ゆっくり止まる
	ctl.model_root.rotation.y = wrapf(_t_from + _t_delta * k, -PI, PI)
	if _t_t >= _t_dur:
		turning = false
		ctl._emit_state_changed()


# =====================================================================
# ポーズをなめらかに移す (直接指定のボーン)
# =====================================================================

## target: ボーン名 -> Quaternion。dur 秒かけて、今の姿勢から target へ移す。
## clear_others: target に無い直接指定は、アニメーションの姿勢へなめらかに戻して外す。
func blend_bones(target: Dictionary, dur: float, clear_others: bool) -> void:
	var vrm = ctl.current_vrm
	if vrm == null:
		return
	_finish_blend()
	var ov: Dictionary = vrm.direct_bone_overrides
	var w: Dictionary = vrm.direct_bone_weights
	for b in target.keys():
		var q: Quaternion = target[b]
		if ov.has(b) and float(w.get(b, 1.0)) >= 0.999:
			_blend[b] = {"mode": "slerp", "from": ov[b], "to": q}
		else:
			var from_w := float(w.get(b, 0.0)) if ov.has(b) else 0.0
			ov[b] = q
			w[b] = from_w
			_blend[b] = {"mode": "in", "from_w": from_w}
	if clear_others:
		for b in ov.keys():
			if not target.has(b):
				_blend[b] = {"mode": "out", "from_w": float(w.get(b, 1.0))}
	_blend_t = 0.0
	_blend_dur = maxf(dur, 0.0)
	if _blend_dur <= 0.0:
		_finish_blend()


## 途中のポーズの移り変わりを、行き先の姿勢にして終える
func _finish_blend() -> void:
	var vrm = ctl.current_vrm
	if vrm != null:
		for b in _blend.keys():
			var e: Dictionary = _blend[b]
			match str(e["mode"]):
				"slerp":
					vrm.direct_bone_overrides[b] = e["to"]
				"in":
					vrm.direct_bone_weights.erase(b)
				"out":
					vrm.direct_bone_overrides.erase(b)
					vrm.direct_bone_weights.erase(b)
					ctl._direct_bone_euler_deg.erase(b)
	_blend = {}


## 途中のポーズの移り変わりを、その場で捨てる (すぐに姿勢を消すとき)
func cancel_blend() -> void:
	_blend = {}
	if ctl.current_vrm != null:
		ctl.current_vrm.direct_bone_weights.clear()


func _process_blend(dt: float) -> void:
	var vrm = ctl.current_vrm
	if vrm == null:
		_blend = {}
		return
	_blend_t += dt
	if _blend_t >= _blend_dur:
		_finish_blend()
		ctl._emit_state_changed()
		return
	var k := clampf(_blend_t / _blend_dur, 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	for b in _blend.keys():
		var e: Dictionary = _blend[b]
		match str(e["mode"]):
			"slerp":
				vrm.direct_bone_overrides[b] = (e["from"] as Quaternion).slerp(e["to"], k)
			"in":
				vrm.direct_bone_weights[b] = lerpf(float(e["from_w"]), 1.0, k)
			"out":
				vrm.direct_bone_weights[b] = lerpf(float(e["from_w"]), 0.0, k)


# =====================================================================
# しゃべる: 文字から「あいうえお」の口の形の並びを作って、自然な速さで動かす
# =====================================================================

## params: text (しゃべる文。無ければ duration_sec の長さだけそれらしく動かす),
##         duration_sec, speed (1 秒あたりの音の数。既定 7.5), intensity (口の開き 0〜1。既定 0.8)
func start_talk(params: Dictionary) -> Dictionary:
	if ctl.current_vrm == null:
		return {"ok": false, "error": "モデルが読み込まれていません"}
	var text := str(params.get("text", ""))
	var dur := float(params.get("duration_sec", 0.0))
	var speed := clampf(float(params.get("speed", 7.5)), 2.0, 16.0)
	var amp := clampf(float(params.get("intensity", 0.8)), 0.05, 1.0)
	if text.strip_edges() == "" and dur <= 0.0:
		return {"ok": false, "error": "text か duration_sec を指定してください"}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(text) if text != "" else Time.get_ticks_usec()
	var morae: Array = _text_to_morae(text, rng) if text.strip_edges() != "" else _random_morae(dur, speed, rng)
	_segs.clear()
	var t := 0.0
	var unit := 1.0 / speed
	for m in morae:
		var len_sec: float = float(m[1]) * unit * rng.randf_range(0.85, 1.15) if m[0] != "pause" else float(m[1])
		var v: String = "" if m[0] == "pause" else str(m[0])
		var a: float = 0.0 if v == "" else amp * rng.randf_range(0.65, 1.0) * float(m[2] if m.size() > 2 else 1.0)
		_segs.append({"t0": t, "t1": t + len_sec, "v": v, "amp": a})
		t += len_sec
	if dur > 0.0 and text.strip_edges() != "" and t > 0.0:
		# 文と長さの両方が指定されたら、長さに合わせて伸び縮みさせる
		var k := dur / t
		for s in _segs:
			s.t0 *= k
			s.t1 *= k
		t = dur
	_talk_dur = t
	_talk_t = 0.0
	_seg_i = 0
	talking = true
	for v in MOUTH:
		if not _mouth.has(v):
			_mouth[v] = 0.0
	return {"ok": true, "duration_sec": snappedf(t, 0.01), "morae": _segs.size()}


func stop_talk() -> void:
	if not talking:
		return
	talking = false
	if ctl.current_vrm != null:
		var w := {}
		for v in MOUTH:
			w[v] = 0.0
			_mouth[v] = 0.0
		ctl.current_vrm.expressions.set_weights(w, 0.08)


func _process_talk(dt: float) -> void:
	if ctl.current_vrm == null:
		talking = false
		return
	_talk_t += dt
	if _talk_t >= _talk_dur:
		stop_talk()
		return
	while _seg_i < _segs.size() - 1 and _talk_t >= _segs[_seg_i].t1:
		_seg_i += 1
	var s: Dictionary = _segs[_seg_i]
	var ph := clampf((_talk_t - s.t0) / maxf(s.t1 - s.t0, 0.001), 0.0, 1.0)
	# 1 つの音の中で、開いて閉じる (完全には閉じきらない)
	var env := 0.35 + 0.65 * sin(PI * clampf(ph * 1.15, 0.0, 1.0))
	var target := {}
	for v in MOUTH:
		target[v] = 0.0
	if s.v != "":
		target[s.v] = float(s.amp) * env
	# 口の形はすばやく、でも飛ばずに追いかける
	var k := 1.0 - exp(-dt * 28.0)
	var w := {}
	for v in MOUTH:
		_mouth[v] = lerpf(float(_mouth.get(v, 0.0)), float(target[v]), k)
		w[v] = _mouth[v]
	ctl.current_vrm.expressions.set_weights(w, 0.0)


const VOWEL_ROWS := {
	"aa": "あかがさざただなはばぱまやらわぁゃゎ",
	"ih": "いきぎしじちぢにひびぴみりぃゐ",
	"ou": "うくぐすずつづぬふぶぷむゆるぅゅゔ",
	"ee": "えけげせぜてでねへべぺめれぇゑ",
	"oh": "おこごそぞとどのほぼぽもよろをぉょ",
}


## 文 → [口の形, 長さ (音の数), 開きの強さ] の並び。口の形 "pause" は長さが秒
func _text_to_morae(text: String, rng: RandomNumberGenerator) -> Array:
	var vowel_of := {}
	for v in VOWEL_ROWS.keys():
		for ch in VOWEL_ROWS[v]:
			vowel_of[ch] = v
	var out: Array = []
	var latin := ""
	for i in text.length():
		var c := text[i]
		var code := c.unicode_at(0)
		# カタカナ → ひらがな
		if code >= 0x30A1 and code <= 0x30F6:
			c = String.chr(code - 0x60)
			code -= 0x60
		var is_latin := (code >= 0x41 and code <= 0x5A) or (code >= 0x61 and code <= 0x7A)
		if is_latin:
			latin += c.to_lower()
			continue
		if latin != "":
			out.append_array(_latin_morae(latin))
			latin = ""
		if c in "ゃゅょぁぃぅぇぉゎ" and not out.is_empty() and out[-1][0] != "pause":
			out[-1][0] = vowel_of[c]  # きゃ → 「あ」の口 (前の音の形を変える)
		elif vowel_of.has(c):
			out.append([vowel_of[c], 1.0, 1.0])
		elif c == "ん":
			out.append(["ou", 0.9, 0.25])  # ほぼ閉じた口
		elif c == "っ":
			out.append(["pause", 0.07])
		elif c == "ー" or c == "～" or c == "〜":
			if not out.is_empty() and out[-1][0] != "pause":
				out.append([out[-1][0], 1.0, 0.85])
		elif c in "、,，":
			out.append(["pause", 0.22])
		elif c in "。．.！？!?…\n":
			out.append(["pause", 0.42])
		elif c == " " or c == "　":
			out.append(["pause", 0.08])
		elif (code >= 0x4E00 and code <= 0x9FFF) or c == "々":
			# 漢字は読みが分からないので、1〜3 音のそれらしい口の形にする
			var nm := 1 + int(rng.randf() < 0.7) + int(rng.randf() < 0.2)
			for _k in nm:
				out.append([_random_vowel(rng), 1.0, 1.0])
		elif code >= 0x30 and code <= 0x39:
			for _k in 2:
				out.append([_random_vowel(rng), 1.0, 1.0])
	if latin != "":
		out.append_array(_latin_morae(latin))
	return out


## 英字の単語: 母音のまとまりごとに 1 音 (英語は日本語より 1 音が長い)
func _latin_morae(word: String) -> Array:
	var out: Array = []
	var prev_vowel := false
	for ch in word:
		var v := ""
		match ch:
			"a": v = "aa"
			"i", "y": v = "ih"
			"u", "w": v = "ou"
			"e": v = "ee"
			"o": v = "oh"
		if v != "" and not prev_vowel:
			out.append([v, 1.5, 1.0])
		prev_vowel = v != ""
	if out.is_empty():
		out.append(["ee", 1.0, 0.5])
	return out


func _random_morae(dur: float, speed: float, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var t := 0.0
	var until_pause := rng.randi_range(6, 14)
	while t < dur:
		if until_pause <= 0:
			var p := rng.randf_range(0.18, 0.4)
			out.append(["pause", p])
			t += p
			until_pause = rng.randi_range(6, 14)
			continue
		out.append([_random_vowel(rng), 1.0, 1.0])
		t += 1.0 / speed
		until_pause -= 1
	return out


func _random_vowel(rng: RandomNumberGenerator) -> String:
	var r := rng.randf()
	if r < 0.3:
		return "aa"
	if r < 0.5:
		return "ih"
	if r < 0.68:
		return "ou"
	if r < 0.8:
		return "ee"
	return "oh"


# =====================================================================
# 歩く: 向きを変え、歩くアニメーションを再生しながら体ごと移動し、止まったら元に戻す
# =====================================================================

## params:
##   direction: "forward" | "backward" | "left" | "right" (既定 "forward")
##   angle_deg: direction の代わりの角度 (0 = 前、90 = 右、-90 = 左、180 = 後ろ)
##   relative_to: "character" (キャラクターから見た向き。既定) | "screen" (画面から見た向き。前 = カメラの方)
##   target: [x, z] 行き先のワールド座標 (指定すると direction・distance より優先)
##   distance: 歩く距離 (メートル。既定 1.0)
##   speed: 歩く速さ (メートル/秒。既定 0.8)
##   animation: 歩くアニメーション名 (既定は Walk_Loop か walk)
##   face_camera_after: 着いたあとカメラの方を向くか (既定 true)
func start_walk(params: Dictionary) -> Dictionary:
	if ctl.current_vrm == null:
		return {"ok": false, "error": "モデルが読み込まれていません"}
	var root: Node3D = ctl.model_root
	var from: Vector3 = root.position
	var to := from
	if typeof(params.get("target", null)) == TYPE_ARRAY and params["target"].size() >= 2:
		var tg: Array = params["target"]
		to = Vector3(float(tg[0]), from.y, float(tg[tg.size() - 1]))
	else:
		var ang := 0.0
		if params.has("angle_deg"):
			ang = deg_to_rad(float(params["angle_deg"]))
		else:
			match str(params.get("direction", "forward")):
				"right": ang = PI / 2.0
				"left": ang = -PI / 2.0
				"backward", "back": ang = PI
				_: ang = 0.0
		var fwd: Vector3
		var right: Vector3
		if str(params.get("relative_to", "character")) == "screen":
			var cam: Vector3 = ctl.camera_rig.get_camera_world_position()
			fwd = Vector3(cam.x - from.x, 0.0, cam.z - from.z)
			if fwd.length() < 0.01:
				fwd = Vector3.BACK
			fwd = fwd.normalized()
			var cb: Basis = ctl.camera_rig.main_camera.global_transform.basis
			right = Vector3(cb.x.x, 0.0, cb.x.z).normalized()
		else:
			var yaw: float = root.rotation.y
			fwd = Vector3(sin(yaw), 0.0, cos(yaw))  # VRM は +z が正面
			right = Vector3(-cos(yaw), 0.0, sin(yaw))  # モデルの右手側
		var dir := (fwd * cos(ang) + right * sin(ang)).normalized()
		to = from + dir * clampf(float(params.get("distance", 1.0)), 0.0, 50.0)
	var dist := Vector2(to.x - from.x, to.z - from.z).length()
	_w_speed = clampf(float(params.get("speed", 0.8)), 0.1, 6.0)
	_w_face_camera = bool(params.get("face_camera_after", true))
	_w_from = from
	_w_to = to
	_w_dist = dist
	_w_move_dur = dist / _w_speed + ACCEL_SEC  # 加速・減速のぶん少し長い
	if dist < 0.01:
		_w_yaw_target = root.rotation.y
	else:
		_w_yaw_target = atan2(to.x - from.x, to.z - from.z)

	# 歩くアニメーション
	var want := str(params.get("animation", ""))
	var clip_name := ""
	for c in ([want] if want != "" else []) + ["Walk_Loop", "walk"]:
		if c != "" and ctl.vrma_player.has_clip(c):
			clip_name = c
			break
	if not walking:
		var vp = ctl.vrma_player
		_w_prev_anim = {"name": vp.current_name if vp.playing else "", "looping": vp.looping, "speed": vp.speed}
	_w_clip = clip_name
	if clip_name != "" and dist >= 0.01:
		ctl.vrma_player.strip_root_xz = true
		ctl.vrma_player.play(clip_name, true, _anim_rate(clip_name), 0.3)
	walking = true
	_w_t = 0.0
	_w_phase = "turn" if dist >= 0.01 else "stop"
	var turn_sec := absf(rad_to_deg(angle_difference(root.rotation.y, _w_yaw_target))) / TURN_DEG_PER_SEC
	return {"ok": true, "distance": snappedf(dist, 0.01), "duration_sec": snappedf(turn_sec + (_w_move_dur if dist >= 0.01 else 0.0), 0.01),
		"target": [snappedf(to.x, 0.001), snappedf(to.z, 0.001)], "animation": clip_name}


func stop_walk() -> void:
	if walking and (_w_phase == "turn" or _w_phase == "move"):
		_w_to = ctl.model_root.position
		_begin_stop()


## 歩くアニメーションの再生速度: アニメーション本来の歩く速さに、指定の速さを合わせる
func _anim_rate(clip_name: String) -> float:
	var clip = ctl.vrma_player.get_clip(clip_name)
	var dst_y: float = ctl.current_vrm.humanoid.hips_rest_height if ctl.current_vrm != null else 0.9
	var natural := 1.1 * dst_y / 0.93  # 足踏みのアニメーションなら、ふつうの歩く速さとみなす
	if clip != null and clip.hips_trans_sampler != null and clip.duration > 0.1:
		var a: Vector3 = clip.hips_trans_sampler.sample_vec3(0.0)
		var b: Vector3 = clip.hips_trans_sampler.sample_vec3(clip.duration)
		var d := Vector2(b.x - a.x, b.z - a.z).length() * dst_y / maxf(clip.src_hips_rest_y, 0.05)
		if d / clip.duration > 0.3:
			natural = d / clip.duration
	return clampf(_w_speed / natural, 0.4, 2.5)


func _process_walk(dt: float) -> void:
	if ctl.current_vrm == null:
		_finish_walk()
		return
	var root: Node3D = ctl.model_root
	_w_t += dt
	match _w_phase:
		"turn":
			if _turn_toward(root, _w_yaw_target, dt):
				_w_phase = "move"
				_w_t = 0.0
		"move":
			# 速さの台形: 最初と最後の ACCEL_SEC 秒で加速・減速する
			var total := _w_move_dur
			var vmax := _w_dist / maxf(total - ACCEL_SEC, 0.01)
			var t := minf(_w_t, total)
			var s := 0.0
			if t < ACCEL_SEC:
				s = 0.5 * vmax / ACCEL_SEC * t * t
			elif t < total - ACCEL_SEC:
				s = 0.5 * vmax * ACCEL_SEC + vmax * (t - ACCEL_SEC)
			else:
				var r := total - t
				s = _w_dist - 0.5 * vmax / ACCEL_SEC * r * r
			var k := clampf(s / maxf(_w_dist, 0.0001), 0.0, 1.0)
			root.position = _w_from.lerp(_w_to, k)
			_turn_toward(root, _w_yaw_target, dt)
			if _w_t >= total:
				root.position = _w_to
				_begin_stop()
		"stop":
			if _w_face_camera:
				var cam: Vector3 = ctl.camera_rig.get_camera_world_position()
				var p := root.position
				var yaw := atan2(cam.x - p.x, cam.z - p.z)
				if _turn_toward(root, yaw, dt):
					_finish_walk()
			else:
				_finish_walk()


func _begin_stop() -> void:
	_w_phase = "stop"
	_w_t = 0.0
	var vp = ctl.vrma_player
	vp.strip_root_xz = false
	var prev := str(_w_prev_anim.get("name", ""))
	if prev != "" and prev != _w_clip and vp.has_clip(prev):
		vp.play(prev, bool(_w_prev_anim.get("looping", true)), float(_w_prev_anim.get("speed", 1.0)), 0.4)
	elif _w_clip != "":
		# もともとアニメーションが無かったときは、待機のアニメーションで立ち止まる
		var idle := ""
		for c in ["Idle_Loop", "idle"]:
			if vp.has_clip(c):
				idle = c
				break
		if idle != "":
			vp.play(idle, true, 1.0, 0.4)
		else:
			vp.stop()


func _finish_walk() -> void:
	walking = false
	_w_phase = ""
	ctl.vrma_player.strip_root_xz = false
	ctl._emit_state_changed()


## 少しずつ yaw へ向ける。向き終わったら true
func _turn_toward(root: Node3D, yaw: float, dt: float) -> bool:
	var diff := angle_difference(root.rotation.y, yaw)
	var stepv := deg_to_rad(TURN_DEG_PER_SEC) * dt
	if absf(diff) <= stepv:
		root.rotation.y = yaw
		return true
	root.rotation.y += signf(diff) * stepv
	return false
