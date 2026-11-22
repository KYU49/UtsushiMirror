extends RefCounted
## SMPL 系 (SMPL / SMPL-H / SMPL-X) のモーションを入れた .npz を、VRMA と同じクリップとして読み込む。
##
## 対応する中身 (AMASS などで使われる形):
##   - poses: (N, 72 | 156 | 165) の軸角 (ラジアン)。先頭 3 つが体全体の向き、続いて関節ごとに 3 つ
##   - または root_orient (N, 3) + pose_body (N, 63) [+ pose_hand (N, 90)]
##   - trans: (N, 3) 体の位置 (メートル)。無くてもよい
##   - mocap_framerate / mocap_frame_rate / fps / frame_rate: フレームレート (無ければ 30)
##
## SMPL も VRM 1.0 の正規化ボーンも「y が上・+z が正面・+x がモデルの左」で、関節の回転は
## 親基準の回転なので、軸角をそのまま VRM の正規化ボーンの回転として使える。
## Z が上のデータ (AMASS) や y が下のデータは、最初のフレームの体の向きから判断して y が上に直す。
## 最初のフレームで正面 (+z) を向くように、水平の向きもそろえる。

const VrmaLoaderScript := preload("res://scripts/vrm/vrma_loader.gd")

## SMPL の体の関節 (0〜21) → VRM のボーン
const BODY_BONES := [
	"hips", "leftUpperLeg", "rightUpperLeg", "spine", "leftLowerLeg", "rightLowerLeg",
	"chest", "leftFoot", "rightFoot", "upperChest", "leftToes", "rightToes",
	"neck", "leftShoulder", "rightShoulder", "head", "leftUpperArm", "rightUpperArm",
	"leftLowerArm", "rightLowerArm", "leftHand", "rightHand",
]
## MANO の指の順番 (人差し指・中指・小指・薬指・親指 × 付け根から 3 つ)
const FINGER_ORDER := [
	["Index", ["Proximal", "Intermediate", "Distal"]],
	["Middle", ["Proximal", "Intermediate", "Distal"]],
	["Little", ["Proximal", "Intermediate", "Distal"]],
	["Ring", ["Proximal", "Intermediate", "Distal"]],
	["Thumb", ["Metacarpal", "Proximal", "Distal"]],
]
## 立った人の腰の高さ (メートル)。腰の上下・前後の動きを、モデルの大きさに合わせて伸び縮みさせる基準
const SMPL_HIPS_HEIGHT := 0.93
## 細かすぎるデータ (120fps など) は、この fps まで間引く
const MAX_FPS := 60.0


static func load_npz(path: String, clip_name: String = "") -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "ファイルがありません: " + path}
	var zr := ZIPReader.new()
	if zr.open(path) != OK:
		return {"ok": false, "error": "npz (zip) として開けません"}
	var arrays := {}
	for f in zr.get_files():
		if f.ends_with(".npy"):
			var a := _parse_npy(zr.read_file(f))
			if not a.is_empty():
				arrays[f.get_basename()] = a
	zr.close()

	var fps := 30.0
	for k in ["mocap_framerate", "mocap_frame_rate", "fps", "frame_rate", "framerate"]:
		if arrays.has(k) and arrays[k].data.size() > 0:
			fps = float(arrays[k].data[0])
			break
	if fps <= 0.0:
		fps = 30.0

	# 関節ごとの軸角を (N, J*3) にそろえる
	var n := 0
	var poses := PackedFloat64Array()
	var joints := 0
	var hand_offset := -1  # 左手の指が始まる関節番号 (無ければ -1)
	if arrays.has("poses"):
		var p: Dictionary = arrays["poses"]
		if p.shape.size() != 2 or p.shape[1] % 3 != 0:
			return {"ok": false, "error": "poses の形が想定外です: %s" % str(p.shape)}
		n = p.shape[0]
		joints = p.shape[1] / 3
		poses = p.data
		if joints == 52:
			hand_offset = 22  # SMPL-H
		elif joints == 55:
			hand_offset = 25  # SMPL-X (顎・両目のあと)
	elif arrays.has("pose_body") and arrays.has("root_orient"):
		var ro: Dictionary = arrays["root_orient"]
		var pb: Dictionary = arrays["pose_body"]
		if ro.shape.size() != 2 or ro.shape[1] < 3 or pb.shape.size() != 2 or pb.shape[0] < ro.shape[0] or pb.shape[1] < 63:
			return {"ok": false, "error": "root_orient / pose_body の形が想定外です: %s / %s" % [str(ro.shape), str(pb.shape)]}
		n = ro.shape[0]
		var ph = arrays.get("pose_hand", null)
		var has_hands: bool = ph != null and ph.shape.size() == 2 and ph.shape[0] >= n and ph.shape[1] >= 90
		joints = 22 + (30 if has_hands else 0)
		hand_offset = 22 if has_hands else -1
		poses.resize(n * joints * 3)
		for i in n:
			for c in 3:
				poses[i * joints * 3 + c] = ro.data[i * ro.shape[1] + c]
			for c in 63:
				poses[i * joints * 3 + 3 + c] = pb.data[i * pb.shape[1] + c]
			if has_hands:
				for c in 90:
					poses[i * joints * 3 + 66 + c] = ph.data[i * ph.shape[1] + c]
	else:
		return {"ok": false, "error": "SMPL 系のモーション (poses か root_orient + pose_body) が入っていません。入っているもの: %s" % ", ".join(arrays.keys())}
	if n < 1 or joints < 22:
		return {"ok": false, "error": "フレームか関節が足りません"}

	var trans := PackedFloat64Array()
	if arrays.has("trans") and arrays["trans"].shape.size() == 2 and arrays["trans"].shape[0] >= n and arrays["trans"].shape[1] >= 3:
		trans = arrays["trans"].data

	# 間引き
	var step := maxi(1, int(round(fps / MAX_FPS)))
	var frames: Array[int] = []
	for i in range(0, n, step):
		frames.append(i)
	var out_fps := fps / step

	# 上の向きと正面の向きを直す回転 (最初のフレームから決める)
	var root0 := _aa(poses, 0, 0, joints)
	var up := root0 * Vector3.UP
	var fix := Quaternion.IDENTITY
	var ax := up.abs().max_axis_index()
	if ax == Vector3.AXIS_Z:
		fix = Quaternion(Vector3.RIGHT, -PI / 2.0 if up.z > 0.0 else PI / 2.0)
	elif ax == Vector3.AXIS_Y and up.y < 0.0:
		fix = Quaternion(Vector3.RIGHT, PI)
	elif ax == Vector3.AXIS_X:
		fix = Quaternion(Vector3.BACK, PI / 2.0 if up.x > 0.0 else -PI / 2.0)
	var fwd := (fix * root0) * Vector3.BACK  # +z = 正面
	var yaw := atan2(fwd.x, fwd.z)
	fix = (Quaternion(Vector3.UP, -yaw) * fix).normalized()

	var clip := VrmaLoaderScript.VrmaClip.new()
	clip.name = clip_name if clip_name != "" else path.get_file().get_basename()
	clip.path = path
	clip.duration = maxf(float(frames.size() - 1) / out_fps, 0.01)

	var times := PackedFloat32Array()
	for k in frames.size():
		times.append(k / out_fps)

	# 関節番号 → VRM のボーン
	var map := {}
	for j in BODY_BONES.size():
		map[j] = BODY_BONES[j]
	if hand_offset >= 0 and joints >= hand_offset + 30:
		for side in 2:
			var prefix := "left" if side == 0 else "right"
			var j := hand_offset + side * 15
			for f in FINGER_ORDER:
				for seg in f[1]:
					map[j] = prefix + str(f[0]) + str(seg)
					j += 1

	for j in map.keys():
		var vals := PackedFloat32Array()
		vals.resize(frames.size() * 4)
		var prev := Quaternion.IDENTITY
		for k in frames.size():
			var q := _aa(poses, frames[k], j, joints)
			if j == 0:
				q = fix * q
			q = q.normalized()
			if prev.dot(q) < 0.0:
				q = -q  # 補間で遠回りしないように符号をそろえる
			prev = q
			vals[k * 4] = q.x
			vals[k * 4 + 1] = q.y
			vals[k * 4 + 2] = q.z
			vals[k * 4 + 3] = q.w
		var s := VrmaLoaderScript.VrmaSampler.new()
		s.times = times
		s.values = vals
		s.stride = 4
		clip.bone_tracks[map[j]] = {
			"rest_local": Quaternion.IDENTITY,
			"rest_local_inv": Quaternion.IDENTITY,
			"parent_rest_world": Quaternion.IDENTITY,
			"parent_rest_world_inv": Quaternion.IDENTITY,
			"sampler": s,
		}

	# 腰の位置: 最初のフレームの水平位置を原点、立ったときの高さを基準にした動きにする
	if not trans.is_empty():
		var pos: Array[Vector3] = []
		var ys: Array[float] = []
		for k in frames.size():
			var i := frames[k]
			var p := fix * Vector3(trans[i * 3], trans[i * 3 + 1], trans[i * 3 + 2])
			pos.append(p)
			ys.append(p.y)
		ys.sort()
		var stand_y: float = ys[int((ys.size() - 1) * 0.9)]  # しゃがむ動きがあっても、立っている高さを基準にする
		var vals := PackedFloat32Array()
		vals.resize(frames.size() * 3)
		for k in frames.size():
			var p: Vector3 = pos[k]
			vals[k * 3] = p.x - pos[0].x
			vals[k * 3 + 1] = SMPL_HIPS_HEIGHT + (p.y - stand_y)
			vals[k * 3 + 2] = p.z - pos[0].z
		var ts := VrmaLoaderScript.VrmaSampler.new()
		ts.times = times
		ts.values = vals
		ts.stride = 3
		clip.hips_trans_sampler = ts
		clip.src_hips_rest_y = SMPL_HIPS_HEIGHT
		clip.src_hips_rest_pos = Vector3(0.0, SMPL_HIPS_HEIGHT, 0.0)

	return {"ok": true, "clip": clip, "frames": frames.size(), "fps": out_fps}


## poses の i フレーム目・j 番目の関節の軸角 → 回転
static func _aa(poses: PackedFloat64Array, i: int, j: int, joints: int) -> Quaternion:
	var o := (i * joints + j) * 3
	var v := Vector3(poses[o], poses[o + 1], poses[o + 2])
	var ang := v.length()
	if ang < 1e-8:
		return Quaternion.IDENTITY
	return Quaternion(v / ang, ang)


## .npy (little endian の f4 / f8 / i4 / i8) → {"shape": [...], "data": PackedFloat64Array}
static func _parse_npy(b: PackedByteArray) -> Dictionary:
	if b.size() < 10 or b[0] != 0x93 or b.slice(1, 6).get_string_from_ascii() != "NUMPY":
		return {}
	var major := b[6]
	var hlen := 0
	var off := 0
	if major == 1:
		hlen = b.decode_u16(8)
		off = 10
	else:
		hlen = b.decode_u32(8)
		off = 12
	var header := b.slice(off, off + hlen).get_string_from_ascii()
	var data_off := off + hlen
	var descr := _header_value(header, "descr")
	if _header_value(header, "fortran_order") == "True":
		return {}
	var shape_s := _header_value(header, "shape").replace("(", "").replace(")", "")
	var shape: Array[int] = []
	for part in shape_s.split(",", false):
		if part.strip_edges() != "":
			shape.append(int(part.strip_edges()))
	var count := 1
	for s in shape:
		count *= s
	var raw := b.slice(data_off)
	var data := PackedFloat64Array()
	match descr:
		"<f8":
			data = raw.to_float64_array()
		"<f4":
			var src_f4 := raw.to_float32_array()
			var n_f4 := mini(src_f4.size(), count)
			data.resize(n_f4)
			for idx in range(n_f4):
				data[idx] = src_f4[idx]
		"<i4":
			var src_i4 := raw.to_int32_array()
			var n_i4 := mini(src_i4.size(), count)
			data.resize(n_i4)
			for idx in range(n_i4):
				data[idx] = src_i4[idx]
		"<i8":
			var src_i8 := raw.to_int64_array()
			var n_i8 := mini(src_i8.size(), count)
			data.resize(n_i8)
			for idx in range(n_i8):
				data[idx] = src_i8[idx]
		_:
			return {}
	if data.size() < count:
		return {}
	data.resize(count)
	return {"shape": shape, "data": data}


static func _header_value(header: String, key: String) -> String:
	var i := header.find("'" + key + "'")
	if i < 0:
		i = header.find("\"" + key + "\"")
	if i < 0:
		return ""
	var colon := header.find(":", i + key.length() + 2)
	if colon < 0:
		return ""
	var rest := header.substr(colon + 1).strip_edges()
	if rest.begins_with("'") or rest.begins_with("\""):
		var q := rest.substr(0, 1)
		var end_q := rest.find(q, 1)
		return rest.substr(1, end_q - 1) if end_q >= 1 else ""
	if rest.begins_with("("):
		var end_p := rest.find(")")
		return rest.substr(0, end_p + 1) if end_p >= 0 else ""
	return rest.split(",")[0].strip_edges()
