extends RefCounted

## 画面効果 (ポストエフェクト) とモデルの陰影 (MToon の影) の調整を管理する。
##
## 画面効果: メイン画面と出力ビューポートの最前面に全画面の ColorRect を 2 枚 (乗算・加算) 置き、
##   shaders/post_effects_mul / _add.gdshader を掛ける (本体は post_effects.gdshaderinc)。
##   2 枚に分けるのは透過を壊さないため (詳しくは gdshaderinc の冒頭)。
##   プリセット = シェーダーの値の組み合わせ。細かい値を変えると style は "custom" になる。
## モデルの陰影: 読み込んだ VRM の MToon マテリアルすべてに vv_* の値を入れる。

const SHADER_MIX := preload("res://shaders/post_effects_mix.gdshader")
const SHADER_MUL := preload("res://shaders/post_effects_mul.gdshader")
const SHADER_ADD := preload("res://shaders/post_effects_add.gdshader")

## シェーダーの値の既定 (= 何もしない)
const NEUTRAL := {
	"exposure": 0.0, "contrast": 1.0, "saturation": 1.0, "vibrance": 0.0,
	"temperature": 0.0, "tint": 0.0, "black_lift": 0.0, "highlight_roll": 0.0,
	"shadow_color": "#808080", "shadow_amount": 0.0, "highlight_color": "#808080", "highlight_amount": 0.0,
	"sepia": 0.0, "mono": 0.0,
	"posterize": 0.0, "edge": 0.0, "edge_threshold": 0.08, "edge_color": "#1f1724", "kuwahara": 0.0,
	"diffusion": 0.0, "diffusion_threshold": 0.6, "halation": 0.0, "glow": 0.0, "softness": 0.0, "sharpen": 0.0,
	"vignette": 0.0, "chroma": 0.0, "grain": 0.0, "grain_fps": 24.0, "scratches": 0.0, "dust": 0.0,
	"flicker": 0.0, "jitter": 0.0, "scanlines": 0.0, "vhs": 0.0, "letterbox": 0.0,
}

## プリセット: [表示名, 説明, NEUTRAL との差分]
const PRESETS := {
	"none": ["なし", "効果を掛けません。", {}],
	"anime": ["アニメ風", "セル画のように明るさを段にし、細い輪郭線を足して色を鮮やかに。明るい所はふんわり光らせます。", {
		"saturation": 1.15, "vibrance": 0.2, "contrast": 1.04, "posterize": 4.0, "edge": 0.25, "edge_threshold": 0.15,
		"kuwahara": 0.5, "diffusion": 0.12, "diffusion_threshold": 0.8, "highlight_roll": 0.08, "shadow_color": "#6a74b0", "shadow_amount": 0.18}],
	"drama": ["ドラマ風", "ドラマ撮影で使う拡散フィルター (Black Pro-Mist) のような柔らかいにじみ。黒を少し浮かせ、肌が映える暖かい色味に。", {
		"diffusion": 0.38, "diffusion_threshold": 0.5, "halation": 0.06, "glow": 0.12, "contrast": 0.92, "black_lift": 0.035,
		"highlight_roll": 0.12, "saturation": 0.92, "temperature": 0.12, "highlight_color": "#ffd2a8", "highlight_amount": 0.18,
		"shadow_color": "#6f8ea0", "shadow_amount": 0.1, "vignette": 0.22}],
	"cinema": ["シネマ風", "映画でよく使うティール (青緑) & オレンジの色分け。コントラストを強め、周辺減光・粒子を加えます。映画の黒帯は下の「黒帯 (縦横比)」で付けられます。", {
		"contrast": 1.16, "saturation": 0.95, "shadow_color": "#3f8f98", "shadow_amount": 0.32, "highlight_color": "#ffb070",
		"highlight_amount": 0.22, "black_lift": 0.02, "halation": 0.07, "diffusion_threshold": 0.7, "vignette": 0.38,
		"grain": 0.06, "chroma": 0.5}],
	"oldfilm": ["古い映画風", "セピア色に退色したフィルム。粒子・縦の傷・ほこり・明るさのちらつき・コマの揺れ、周辺の暗さと柔らかいレンズ。", {
		"sepia": 0.9, "contrast": 1.2, "saturation": 0.6, "exposure": -0.15, "black_lift": 0.04, "highlight_roll": 0.25,
		"grain": 0.3, "grain_fps": 18.0, "scratches": 0.6, "dust": 0.6, "flicker": 0.3, "jitter": 0.4, "vignette": 0.6,
		"softness": 0.25, "glow": 0.05}],
	"noir": ["モノクロ (ノワール)", "白黒の強いコントラストと深い影。古い探偵映画のような雰囲気。", {
		"mono": 1.0, "contrast": 1.35, "black_lift": 0.0, "vignette": 0.5, "grain": 0.12, "diffusion": 0.12,
		"diffusion_threshold": 0.7, "sharpen": 0.2}],
	"vhs": ["VHS・レトロビデオ", "ビデオテープのような色ずれ・横揺れ・走査線・にじみ。90 年代のホームビデオ風。", {
		"vhs": 0.6, "chroma": 1.2, "scanlines": 0.35, "softness": 0.45, "grain": 0.14, "grain_fps": 30.0, "saturation": 1.15,
		"black_lift": 0.04, "temperature": 0.05, "tint": -0.1, "sharpen": 0.0}],
	"painterly": ["絵画・水彩風", "近い色をまとめて筆で塗ったような質感 (Kuwahara フィルター) に、薄い輪郭線を加えます。", {
		"kuwahara": 4.0, "saturation": 1.12, "edge": 0.25, "edge_threshold": 0.12, "contrast": 1.04, "glow": 0.08}],
}

var style: String = "none"
var strength: float = 1.0
var params: Dictionary = NEUTRAL.duplicate()

## モデルの陰影 (MToon)
const SHADE_DEFAULTS := {
	"shade_shift": 0.0,       # + で影の範囲が狭く、- で広く
	"shade_toony": 0.0,       # + で境界くっきり、- でなめらか
	"shade_strength": 1.0,    # 0 で影なし、1 でモデルどおり、2 で最も暗い
	"shade_tint": "#ffffff",  # 影の色味
}
var shade: Dictionary = SHADE_DEFAULTS.duplicate()

var _layers: Array[CanvasLayer] = []
## [{layer: CanvasLayer, vp: Viewport, rect_mix: ColorRect, mat_mix: ShaderMaterial, rect_mul: ColorRect, mat_mul: ShaderMaterial, rect_add: ColorRect, mat_add: ShaderMaterial}]
var _entries: Array = []


## 画面効果を描く層を、メイン画面と出力ビューポートに 1 枚ずつ作る。
func attach(parent: Node, output_viewport: SubViewport) -> void:
	for target in [parent, output_viewport]:
		if target == null:
			continue
		var layer := CanvasLayer.new()
		layer.name = "PostEffectLayer"
		layer.layer = 5  # 3D と背景の上、案内表示 (layer 10) の下
		var vp: Viewport = target if target is Viewport else (target as Node).get_viewport()
		var entry := {"layer": layer, "vp": vp}
		for item in [["mix", SHADER_MIX], ["mul", SHADER_MUL], ["add", SHADER_ADD]]:
			var key: String = item[0]
			var mat := ShaderMaterial.new()
			mat.shader = item[1]
			var rect := ColorRect.new()
			rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rect.material = mat
			layer.add_child(rect)
			entry["rect_" + key] = rect
			entry["mat_" + key] = mat
		target.add_child(layer)
		_layers.append(layer)
		_entries.append(entry)
	_apply()


func apply_preset(name: String) -> void:
	if not PRESETS.has(name):
		return
	style = name
	params = NEUTRAL.duplicate()
	params.merge(PRESETS[name][2], true)
	_apply()


## 外部・設定画面からの変更。style を指定すればプリセットを読み込んでから個別の値を上書きする。
func apply_params(d: Dictionary) -> void:
	if d.has("style") and str(d.style) != style and PRESETS.has(str(d.style)):
		apply_preset(str(d.style))
	if d.has("strength"):
		strength = clampf(float(d.strength), 0.0, 1.0)
	var touched := false
	for k in d.keys():
		if NEUTRAL.has(k):
			params[k] = d[k] if typeof(NEUTRAL[k]) == TYPE_STRING else (int(d[k]) if typeof(NEUTRAL[k]) == TYPE_INT else float(d[k]))
			touched = true
	if touched and not d.has("style"):
		style = "custom"
	for k in d.keys():
		if SHADE_DEFAULTS.has(k):
			shade[k] = str(d[k]) if typeof(SHADE_DEFAULTS[k]) == TYPE_STRING else float(d[k])
	_apply()


func reset_shade() -> void:
	shade = SHADE_DEFAULTS.duplicate()
	apply_shade_to()


func is_active() -> bool:
	if strength <= 0.0:
		return false
	for k in params.keys():
		if params[k] != NEUTRAL[k]:
			return true
	return false


func _apply() -> void:
	var active := is_active()
	for layer in _layers:
		if is_instance_valid(layer):
			layer.visible = active
	if not active:
		apply_shade_to()
		return
	var converted := {}
	for k in params.keys():
		var v = params[k]
		if typeof(NEUTRAL[k]) == TYPE_STRING:
			v = Color(str(v))
		converted[k] = v
	for entry in _entries:
		for mat in [entry["mat_mix"], entry["mat_mul"], entry["mat_add"]]:
			var sm: ShaderMaterial = mat
			sm.set_shader_parameter("strength", strength)
			for k in converted.keys():
				sm.set_shader_parameter(k, converted[k])
	refresh_transparency()
	apply_shade_to()


## 透過の画面では、何も描かれていない所に色を足さない (背景の透過・ウィンドウ透過の切り替え時に呼ぶ)。
func refresh_transparency() -> void:
	for entry in _entries:
		var vp: Viewport = entry["vp"]
		var trans := is_instance_valid(vp) and vp.transparent_bg
		(entry["rect_mix"] as ColorRect).visible = not trans
		(entry["rect_mul"] as ColorRect).visible = trans
		(entry["rect_add"] as ColorRect).visible = trans
		(entry["mat_mix"] as ShaderMaterial).set_shader_parameter("protect_clear", false)
		(entry["mat_mul"] as ShaderMaterial).set_shader_parameter("protect_clear", trans)
		(entry["mat_add"] as ShaderMaterial).set_shader_parameter("protect_clear", trans)


## モデルの MToon マテリアルに陰影の調整を入れる (グローバルシェーダーパラメータを更新)。
func apply_shade_to(_root: Node = null) -> void:
	var tint := Color(str(shade.shade_tint))
	RenderingServer.global_shader_parameter_set("vv_shade_shift", float(shade.shade_shift))
	RenderingServer.global_shader_parameter_set("vv_toony_offset", float(shade.shade_toony))
	RenderingServer.global_shader_parameter_set("vv_shade_strength", float(shade.shade_strength))
	RenderingServer.global_shader_parameter_set("vv_shade_tint", Vector3(tint.r, tint.g, tint.b))


func to_dict() -> Dictionary:
	var d := {"style": style, "strength": strength}
	d.merge(params, true)
	d.merge(shade, true)
	return d


## 保存した設定から戻す (style を先に、そのあと個別の値)。
func load_dict(d: Dictionary) -> void:
	var st := str(d.get("style", "none"))
	if PRESETS.has(st):
		apply_preset(st)
	else:
		apply_preset("none")
	style = st if (PRESETS.has(st) or st == "custom") else "none"
	strength = clampf(float(d.get("strength", 1.0)), 0.0, 1.0)
	for k in d.keys():
		if NEUTRAL.has(k):
			params[k] = d[k] if typeof(NEUTRAL[k]) == TYPE_STRING else (int(d[k]) if typeof(NEUTRAL[k]) == TYPE_INT else float(d[k]))
		elif SHADE_DEFAULTS.has(k):
			shade[k] = str(d[k]) if typeof(SHADE_DEFAULTS[k]) == TYPE_STRING else float(d[k])
	_apply()
