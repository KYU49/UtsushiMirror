class_name BackgroundManager
extends Node

## Manages main window background & transparency (including OS click-through desktop mascot mode),
## plus independent Output SubViewport resolution & background mode for OBS/Spout2/VCam/Capture.
## Uses Environment BG_COLOR / BG_SKY so backgrounds always render behind 3D geometry.

signal background_changed
signal window_changed

var main_bg_layer: CanvasLayer
var main_bg_rect: ColorRect
var main_bg_image_rect: TextureRect
var world_env: WorldEnvironment

var output_viewport: SubViewport
var output_bg_rect: ColorRect
var output_bg_image_rect: TextureRect
var output_camera: Camera3D

# Main background state
var bg_mode: String = "solid" # solid | chroma_green | chroma_blue | gradient | image | transparent_window
var bg_color: Color = Color("#1e222b")
var bg_gradient_bottom: Color = Color("#0f1218")
var bg_image_path: String = ""

# Window state
var win_transparent: bool = false
var win_borderless: bool = false
var win_always_on_top: bool = false
var win_click_through: bool = false

# Output viewport state
var out_width: int = 1280
var out_height: int = 720
var out_bg_mode: String = "transparent" # match_main | transparent | solid | chroma_green | image
var out_color: Color = Color("#00ff00")
var out_image_path: String = ""

var _bridge: Node = null
var _sky_grad_shader: Shader = null
var _sky_img_shader: Shader = null
var _applied_click_through: bool = false
static var _img_tex_cache: Dictionary = {} # path -> {"mtime": int, "tex": Texture2D}


func setup(
	p_bridge: Node,
	p_main_bg_layer: CanvasLayer,
	p_main_bg_rect: ColorRect,
	p_main_bg_img: TextureRect,
	p_world_env: WorldEnvironment,
	p_out_vp: SubViewport,
	p_out_bg_rect: ColorRect,
	p_out_bg_img: TextureRect,
	p_out_cam: Camera3D
) -> void:
	_bridge = p_bridge
	main_bg_layer = p_main_bg_layer
	main_bg_rect = p_main_bg_rect
	main_bg_image_rect = p_main_bg_img
	world_env = p_world_env
	output_viewport = p_out_vp
	output_bg_rect = p_out_bg_rect
	output_bg_image_rect = p_out_bg_img
	output_camera = p_out_cam

	# Keep legacy 2D overlay nodes hidden so they never occlude 3D geometry
	if main_bg_rect != null:
		main_bg_rect.visible = false
	if main_bg_image_rect != null:
		main_bg_image_rect.visible = false
	if output_bg_rect != null:
		output_bg_rect.visible = false
	if output_bg_image_rect != null:
		output_bg_image_rect.visible = false

	RenderingServer.set_default_clear_color(Color(0.0, 0.0, 0.0, 0.0))
	_apply_main_background()
	_apply_output_viewport()


func apply_background(params: Dictionary) -> void:
	if params.has("mode") and params["mode"] != null:
		bg_mode = str(params["mode"])
	if params.has("color") and params["color"] != null:
		bg_color = Color(str(params["color"]))
	if params.has("gradient_bottom") and params["gradient_bottom"] != null:
		bg_gradient_bottom = Color(str(params["gradient_bottom"]))
	if params.has("image_path") and params["image_path"] != null:
		bg_image_path = str(params["image_path"])

	# ウィンドウの枠・透過は「モードを切り替えたとき」だけ変える (色だけの変更では触らない)
	if params.has("mode") and bg_mode == "transparent_window":
		win_transparent = true
		win_borderless = true
	elif params.has("mode"):
		win_transparent = false
		win_borderless = false
		win_click_through = false

	_apply_main_background()
	_apply_window_flags()
	if out_bg_mode == "match_main":
		_apply_output_viewport()
	background_changed.emit()


func apply_window(params: Dictionary) -> void:
	if params.has("transparent") and params["transparent"] != null:
		win_transparent = bool(params["transparent"])
		if win_transparent and bg_mode != "transparent_window":
			bg_mode = "transparent_window"
		elif not win_transparent and bg_mode == "transparent_window":
			bg_mode = "solid"
	if params.has("borderless") and params["borderless"] != null:
		win_borderless = bool(params["borderless"])
	if params.has("always_on_top") and params["always_on_top"] != null:
		win_always_on_top = bool(params["always_on_top"])
	if params.has("click_through") and params["click_through"] != null:
		win_click_through = bool(params["click_through"])
	if params.has("size") and typeof(params["size"]) == TYPE_ARRAY and params["size"].size() >= 2:
		var sz := Vector2i(maxi(320, int(params["size"][0])), maxi(240, int(params["size"][1])))
		DisplayServer.window_set_size(sz)
	if params.has("position") and typeof(params["position"]) == TYPE_ARRAY and params["position"].size() >= 2:
		var wp := Vector2i(int(params["position"][0]), int(params["position"][1]))
		if _position_on_screen(wp, DisplayServer.window_get_size()):
			DisplayServer.window_set_position(wp)

	_apply_main_background()
	_apply_window_flags()
	if out_bg_mode == "match_main":
		_apply_output_viewport()
	window_changed.emit()


func restore_normal_window() -> void:
	bg_mode = "solid"
	win_transparent = false
	win_borderless = false
	win_always_on_top = false
	win_click_through = false
	_apply_main_background()
	_apply_window_flags()
	if out_bg_mode == "match_main":
		_apply_output_viewport()
	background_changed.emit()
	window_changed.emit()


func apply_output_viewport(params: Dictionary) -> void:
	if params.has("width") and params["width"] != null:
		out_width = clampi(int(params["width"]), 64, 7680)
	if params.has("height") and params["height"] != null:
		out_height = clampi(int(params["height"]), 64, 4320)
	if params.has("background_mode") and params["background_mode"] != null:
		out_bg_mode = str(params["background_mode"])
	if params.has("color") and params["color"] != null:
		out_color = Color(str(params["color"]))
	if params.has("image_path") and params["image_path"] != null:
		out_image_path = str(params["image_path"])
	_apply_output_viewport()
	background_changed.emit()


func bg_to_dict() -> Dictionary:
	return {
		"mode": bg_mode,
		"color": "#" + bg_color.to_html(false),
		"gradient_bottom": "#" + bg_gradient_bottom.to_html(false),
		"image_path": bg_image_path,
	}


## 窓が (どれかの画面に) 十分に見える位置か。画面構成が変わって画面の外に出てしまう位置には戻さない。
func _position_on_screen(pos: Vector2i, sz: Vector2i) -> bool:
	var r := Rect2i(pos, sz)
	for i in DisplayServer.get_screen_count():
		var u := DisplayServer.screen_get_usable_rect(i)
		var inter := u.intersection(r)
		if inter.size.x >= mini(200, sz.x) and inter.size.y >= mini(120, sz.y) and u.has_point(pos + Vector2i(sz.x / 2, 10)):
			return true
	return false


func window_to_dict() -> Dictionary:
	var sz := DisplayServer.window_get_size()
	var pos := DisplayServer.window_get_position()
	return {
		"width": sz.x,
		"height": sz.y,
		"size": [sz.x, sz.y],
		"position": [pos.x, pos.y],
		"transparent": win_transparent,
		"borderless": win_borderless,
		"always_on_top": win_always_on_top,
		"click_through": win_click_through,
	}


func output_to_dict() -> Dictionary:
	return {
		"width": out_width,
		"height": out_height,
		"background_mode": out_bg_mode,
		"color": "#" + out_color.to_html(false),
		"image_path": out_image_path,
	}


func _apply_main_background() -> void:
	var root_vp := get_viewport()
	var is_trans := win_transparent or (bg_mode == "transparent_window")
	if root_vp != null:
		root_vp.transparent_bg = is_trans

	if world_env != null and world_env.environment != null:
		if not is_trans and main_bg_rect != null and main_bg_image_rect != null:
			_set_main_clear_color(bg_mode, bg_color)
			_apply_canvas_background(world_env.environment)
		else:
			_apply_env_background(world_env.environment, bg_mode, bg_color, bg_gradient_bottom, bg_image_path, true)
			_apply_canvas_background(world_env.environment)


func sync_output_environment() -> void:
	if output_camera == null or output_camera.environment == null or world_env == null or world_env.environment == null:
		return
	var src := world_env.environment
	var dst := output_camera.environment
	dst.ambient_light_color = src.ambient_light_color
	dst.ambient_light_energy = src.ambient_light_energy
	dst.glow_enabled = src.glow_enabled
	dst.glow_intensity = src.glow_intensity
	dst.glow_hdr_threshold = src.glow_hdr_threshold
	dst.glow_hdr_scale = src.glow_hdr_scale
	dst.glow_blend_mode = src.glow_blend_mode
	dst.glow_bloom = src.glow_bloom
	dst.tonemap_exposure = src.tonemap_exposure
	dst.tonemap_mode = src.tonemap_mode


func _set_main_clear_color(mode: String, col: Color) -> void:
	var base := Color(col.r, col.g, col.b, 1.0)
	match mode:
		"transparent", "transparent_window":
			base = Color(0.0, 0.0, 0.0, 0.0)
		"chroma_green":
			base = Color(0.0, 1.0, 0.0, 1.0)
		"chroma_blue":
			base = Color(0.0, 0.0, 1.0, 1.0)
	RenderingServer.set_default_clear_color(base)


## メイン画面の不透明な背景は、3D の背景色ではなく 3D の奥の 2D の板 (MainBgLayer, layer -100) で描く。
## Windows では透過の仕組みを常にオンにしている (D3D12 で実行中に切り替えると壊れるため)。このとき
## 3D の背景色はアルファ 0 のままウィンドウに渡り、色が後ろに「足される」だけになる
## (黒は完全に透け、白は光ってウィンドウの縁の外まではみ出して見える)。2D の板はアルファ 1 で描かれるので不透明になる。
func _apply_canvas_background(env: Environment) -> void:
	if main_bg_rect == null or main_bg_image_rect == null:
		return
	main_bg_rect.visible = false
	main_bg_image_rect.visible = false
	if bg_mode == "transparent_window" or win_transparent:
		return  # 透過: 3D の背景 (透明) のまま
	match bg_mode:
		"gradient":
			var g := Gradient.new()
			g.set_color(0, Color(bg_color.r, bg_color.g, bg_color.b, 1.0))
			g.set_color(1, Color(bg_gradient_bottom.r, bg_gradient_bottom.g, bg_gradient_bottom.b, 1.0))
			var gt := GradientTexture2D.new()
			gt.gradient = g
			gt.fill_from = Vector2(0.5, 0.0)
			gt.fill_to = Vector2(0.5, 1.0)
			gt.width = 4
			gt.height = 256
			main_bg_image_rect.texture = gt
			main_bg_image_rect.stretch_mode = TextureRect.STRETCH_SCALE
			main_bg_image_rect.visible = true
		"image":
			var tex := _load_image_tex(bg_image_path)
			if tex != null:
				main_bg_image_rect.texture = tex
				main_bg_image_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
				main_bg_image_rect.visible = true
	# 画像・グラデーションの下にも不透明な色を敷く (画像の透明部分・縦横比の余りが透けないように)
	var base := Color(bg_color.r, bg_color.g, bg_color.b, 1.0)
	if bg_mode == "chroma_green":
		base = Color(0.0, 1.0, 0.0, 1.0)
	elif bg_mode == "chroma_blue":
		base = Color(0.0, 0.0, 1.0, 1.0)
	main_bg_rect.color = base
	main_bg_rect.visible = true
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = -1  # 背景に使うのは layer が負の 2D だけ (UI は前に出したまま)
	env.sky = null


func _apply_window_flags() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var cur_trans: bool = DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT)
	if OS.get_name() == "Windows":
		# Keep Windows per-pixel transparency composition active so toggling modes never forces a DWM re-create
		if not cur_trans:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	elif cur_trans != win_transparent:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, win_transparent)

	var was_borderless: bool = DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)
	if was_borderless != win_borderless:
		var saved_pos := DisplayServer.window_get_position()
		var saved_sz := DisplayServer.window_get_size()
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, win_borderless)
		if was_borderless and not win_borderless:
			DisplayServer.window_set_size(saved_sz)
			DisplayServer.window_set_position(saved_pos)
			if _bridge != null and _bridge.has_method("refresh_window_frame"):
				var hwnd_r := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
				if hwnd_r != 0:
					_bridge.refresh_window_frame(hwnd_r)
			call_deferred("_deferred_refresh_frame")

	if DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP) != win_always_on_top:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, win_always_on_top)

	if _applied_click_through != win_click_through:
		var handled := false
		if _bridge != null and _bridge.has_method("set_window_click_through"):
			var hwnd := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
			if hwnd != 0:
				handled = _bridge.set_window_click_through(hwnd, win_click_through)
		if not handled:
			if win_click_through:
				DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
			else:
				var sz := DisplayServer.window_get_size()
				DisplayServer.window_set_mouse_passthrough(PackedVector2Array([
					Vector2(0, 0), Vector2(sz.x, 0), Vector2(sz.x, sz.y), Vector2(0, sz.y)
				]))
		_applied_click_through = win_click_through


func _deferred_refresh_frame() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _bridge != null and _bridge.has_method("refresh_window_frame"):
		var hwnd := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
		if hwnd != 0:
			_bridge.refresh_window_frame(hwnd)


func _apply_output_viewport() -> void:
	if output_viewport == null:
		return
	output_viewport.size = Vector2i(out_width, out_height)
	var eff_mode := bg_mode if out_bg_mode == "match_main" else out_bg_mode
	var is_trans := (eff_mode == "transparent" or eff_mode == "transparent_window")
	output_viewport.transparent_bg = is_trans

	if output_camera != null and world_env != null and world_env.environment != null:
		var env_copy := world_env.environment.duplicate() as Environment
		var eff_col := bg_color if out_bg_mode == "match_main" else out_color
		var eff_img := bg_image_path if out_bg_mode == "match_main" else out_image_path
		_apply_env_background(env_copy, eff_mode, eff_col, bg_gradient_bottom, eff_img)
		output_camera.environment = env_copy


## is_main: メイン画面のときだけ、画面の下地 (既定のクリア色。全画面で共通) も変える。
##   Windows では透過の仕組みを常にオンにしているので、下地が透明のままだと背景色を塗っても下が透ける。
##   出力ビューポート (既定は透過) から呼んだときに下地を透明に戻してはいけない。
func _apply_env_background(env: Environment, mode: String, col: Color, grad_bot: Color, img_path: String, is_main := false) -> void:
	if is_main:
		var base := Color(col.r, col.g, col.b, 1.0)
		match mode:
			"transparent", "transparent_window":
				base = Color(0.0, 0.0, 0.0, 0.0)
			"chroma_green":
				base = Color(0.0, 1.0, 0.0, 1.0)
			"chroma_blue":
				base = Color(0.0, 0.0, 1.0, 1.0)
		RenderingServer.set_default_clear_color(base)
	match mode:
		"transparent", "transparent_window":
			env.background_mode = Environment.BG_CLEAR_COLOR
			env.background_color = Color(0.0, 0.0, 0.0, 0.0)
			env.sky = null
		"chroma_green":
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.0, 1.0, 0.0, 1.0)
			env.sky = null
		"chroma_blue":
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.0, 0.0, 1.0, 1.0)
			env.sky = null
		"gradient":
			env.background_mode = Environment.BG_SKY
			env.sky = _make_gradient_sky(col, grad_bot)
		"image":
			var tex := _load_image_tex(img_path)
			if tex != null:
				env.background_mode = Environment.BG_SKY
				env.sky = _make_image_sky(tex)
			else:
				env.background_mode = Environment.BG_COLOR
				env.background_color = Color(col.r, col.g, col.b, 1.0)
				env.sky = null
		_:
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(col.r, col.g, col.b, 1.0)
			env.sky = null


func _make_gradient_sky(top_col: Color, bot_col: Color) -> Sky:
	if _sky_grad_shader == null:
		_sky_grad_shader = Shader.new()
		_sky_grad_shader.code = """
shader_type sky;
uniform vec4 top_color : source_color = vec4(0.12, 0.14, 0.18, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.05, 0.06, 0.09, 1.0);
void sky() {
	COLOR = mix(top_color.rgb, bottom_color.rgb, SCREEN_UV.y);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = _sky_grad_shader
	mat.set_shader_parameter("top_color", top_col)
	mat.set_shader_parameter("bottom_color", bot_col)
	var sky := Sky.new()
	sky.sky_material = mat
	return sky


func _make_image_sky(tex: Texture2D) -> Sky:
	if _sky_img_shader == null:
		_sky_img_shader = Shader.new()
		_sky_img_shader.code = """
shader_type sky;
uniform sampler2D bg_tex : source_color, filter_linear;
void sky() {
	COLOR = texture(bg_tex, SCREEN_UV).rgb;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = _sky_img_shader
	mat.set_shader_parameter("bg_tex", tex)
	var sky := Sky.new()
	sky.sky_material = mat
	return sky


static func _load_image_tex(path: String) -> Texture2D:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var mtime := int(FileAccess.get_modified_time(path))
	if _img_tex_cache.has(path):
		var entry: Dictionary = _img_tex_cache[path]
		if int(entry.get("mtime", -1)) == mtime and entry.get("tex") != null:
			return entry["tex"]
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	var tex := ImageTexture.create_from_image(img)
	if _img_tex_cache.size() >= 16:
		_img_tex_cache.clear()
	_img_tex_cache[path] = {"mtime": mtime, "tex": tex}
	return tex
