extends RefCounted
## 音声・動画ファイルに合わせて口を動かす (リップシンク)。音は鳴らさない。
## 読み込むときに 1 回だけ解析し (VrmBridge.analyze_lipsync、rust/vrm-gdext/src/lipsync.rs)、
## 再生中は 1/60 秒ごとの表を時間に合わせて引くだけ。口 (aa〜oh) と、軽い感情 (happy / surprised / sad) だけを書く。
## app_controller の _process から毎フレーム process() を呼ぶ。

const MOUTH := ["aa", "ih", "ou", "ee", "oh"]
const EMOTIONS := ["happy", "surprised", "sad"]
## 読める拡張子 (音声と、音の入った動画)
const MEDIA_EXTS := ["mp3", "wav", "ogg", "oga", "flac", "m4a", "aac", "mp4", "m4v", "mov", "mkv", "webm"]

var ctl  # app_controller
var active := false
var path := ""
var intensity := 1.0
var emotion := true
var _t := 0.0
var _dur := 0.0
var _fps := 60.0
var _stride := 9
var _frames := PackedFloat32Array()
var _emo_applied := {}  # 乗せた感情 (止めるときに戻す)


func _init(controller) -> void:
	ctl = controller


static func is_media_file(p: String) -> bool:
	return p.get_extension().to_lower() in MEDIA_EXTS


## params: path (音声・動画ファイル), offset_sec (ファイルのこの位置から始める。既定 0),
##         intensity (口の開きの倍率 0〜1.5。既定 1), emotion (感情も乗せる。既定は今の設定)
func start(params: Dictionary) -> Dictionary:
	if ctl.current_vrm == null:
		return {"ok": false, "error": "モデルが読み込まれていません"}
	if ctl.bridge == null:
		return {"ok": false, "error": "音声の解析に使う拡張 (vrm_gdext) が読み込まれていません"}
	var p := str(params.get("path", "")).strip_edges()
	if p == "":
		return {"ok": false, "error": "path (音声・動画ファイル) を指定してください"}
	p = ctl._resolve_input_path(p)
	var res: Dictionary = ctl.bridge.analyze_lipsync(p)
	if not res.get("ok", false):
		return {"ok": false, "error": str(res.get("error", "解析に失敗しました"))}
	stop()
	_frames = res["frames"]
	_fps = float(res.get("fps", 60.0))
	_stride = int(res.get("stride", 9))
	_dur = float(res.get("duration", 0.0))
	_t = clampf(float(params.get("offset_sec", 0.0)), 0.0, _dur)
	if params.has("intensity"):
		intensity = clampf(float(params["intensity"]), 0.0, 1.5)
	if params.has("emotion"):
		emotion = bool(params["emotion"])
	path = p
	active = true
	return {"ok": true, "path": p, "duration_sec": snappedf(_dur, 0.01), "start_sec": snappedf(_t, 0.01)}


func stop() -> void:
	if not active:
		return
	active = false
	if ctl.current_vrm != null:
		var w := {}
		for v in MOUTH:
			w[v] = 0.0
		ctl.current_vrm.expressions.set_weights(w, 0.08)
		var e := {}
		for k in _emo_applied.keys():
			e[k] = 0.0
		if not e.is_empty():
			ctl.current_vrm.expressions.set_weights(e, 0.3)
	_emo_applied.clear()


func remaining_sec() -> float:
	return maxf(0.0, _dur - _t) if active else 0.0


func state() -> Dictionary:
	return {"active": active, "path": path if active else "", "position_sec": snappedf(_t, 0.01) if active else 0.0,
		"duration_sec": snappedf(_dur, 0.01) if active else 0.0, "intensity": intensity, "emotion": emotion}


## 時刻 t の値 (前後のフレームを補間)。i は表の列 (0 = open, 1〜5 = 母音, 6〜8 = 感情)
func sample(t: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(_stride)
	var n := _frames.size() / _stride
	if n == 0:
		return out
	var f := clampf(t * _fps, 0.0, float(n - 1))
	var i0 := int(f)
	var i1 := mini(i0 + 1, n - 1)
	var k := f - float(i0)
	for c in range(_stride):
		out[c] = lerpf(_frames[i0 * _stride + c], _frames[i1 * _stride + c], k)
	return out


## 表の 1 行から口の重みを作る。母音は 2 乗して一番強いものを 1 にし、開きを掛ける (形がはっきりする)
static func mouth_weights(row: PackedFloat32Array, gain: float) -> Dictionary:
	var top := 0.0
	for i in range(5):
		top = maxf(top, row[1 + i] * row[1 + i])
	var w := {}
	for i in range(5):
		var v: float = row[1 + i] * row[1 + i] / maxf(top, 1e-6)
		w[MOUTH[i]] = clampf(row[0] * gain * v, 0.0, 1.0)
	return w


func process(dt: float) -> void:
	if not active:
		return
	if ctl.current_vrm == null:
		active = false
		_emo_applied.clear()
		return
	_t += dt
	if _t >= _dur:
		stop()
		return
	var row := sample(_t)
	ctl.current_vrm.expressions.set_weights(mouth_weights(row, intensity), 0.0, false)
	if emotion and not _tracking_drives_emotion():
		var names: Array = ctl.current_vrm.expressions.get_expression_names()
		var e := {}
		for i in range(3):
			var en: String = EMOTIONS[i]
			if ctl._manual_expr_overrides.has(en) or not names.has(en):
				continue
			e[en] = row[6 + i]
			_emo_applied[en] = true
		if not e.is_empty():
			ctl.current_vrm.expressions.set_weights(e, 0.0, false)
	elif not _emo_applied.is_empty():
		var e0 := {}
		for k in _emo_applied.keys():
			e0[k] = 0.0
		ctl.current_vrm.expressions.set_weights(e0, 0.3, false)
		_emo_applied.clear()


## トラッキングが表情 (喜び・驚きなど) を動かしているときは、そちらを優先して感情を乗せない
func _tracking_drives_emotion() -> bool:
	return ctl._last_vmc_msec > 0 and bool(ctl.tracking.settings.get("expressions", true))
