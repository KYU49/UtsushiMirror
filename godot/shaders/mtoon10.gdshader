shader_type spatial;
render_mode cull_back, depth_draw_opaque, ambient_light_disabled, specular_disabled;

global uniform float vv_time;
uniform bool u_is_unlit = false;

// UV transform (KHR_texture_transform + VRM expression textureTransformBinds)
uniform vec2 u_uv_scale = vec2(1.0, 1.0);
uniform vec2 u_uv_offset = vec2(0.0, 0.0);
uniform vec2 u_expr_uv_scale = vec2(1.0, 1.0);
uniform vec2 u_expr_uv_offset = vec2(0.0, 0.0);

// Base & Alpha
uniform vec4 u_base_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 u_expr_color_mul = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool u_has_base_tex = false;
uniform sampler2D u_base_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool u_is_alpha_mask = false;
uniform float u_alpha_cutoff = 0.5;

// Shade
uniform vec3 u_shade_color = vec3(0.97, 0.81, 0.86);
uniform vec4 u_expr_shade_mul = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool u_has_shade_tex = false;
uniform sampler2D u_shade_tex : source_color, filter_linear_mipmap, repeat_enable;

// Shading curve
uniform float u_shading_shift = 0.0;
uniform float u_shading_shift_tex_scale = 1.0;
uniform bool u_has_shading_shift_tex = false;
uniform sampler2D u_shading_shift_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float u_shading_toony = 0.9;
uniform float u_gi_equalization = 0.9;
// VRMViewer: 影の見た目の調整 (全マテリアル共通に入れる。既定値では MToon の仕様どおり)
global uniform float vv_shade_shift;     // + で影の範囲が狭く、- で広く
global uniform float vv_toony_offset;    // + で影の境界がくっきり、- でなめらか
global uniform float vv_shade_strength;  // 0 で影の色を使わない (明るい色のまま)、1 でモデルどおり、2 まで上げるとさらに暗く
// 落ち影を濃くする分 (0 = Godot の影のまま)。ライトの「落ち影の濃さ」が 1 を超えた分が入る
global uniform float vv_cast_dark;
global uniform vec3 vv_shade_tint;       // 影の色味
global uniform vec3 vv_ambient_color;
global uniform float vv_ambient_energy;

// Normal
uniform bool u_has_normal_tex = false;
uniform sampler2D u_normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float u_normal_scale = 1.0;

// Emissive
uniform vec3 u_emissive_color = vec3(0.0, 0.0, 0.0);
uniform vec4 u_expr_emissive_mul = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool u_has_emissive_tex = false;
uniform sampler2D u_emissive_tex : source_color, filter_linear_mipmap, repeat_enable;

// MatCap
uniform vec3 u_matcap_color = vec3(1.0, 1.0, 1.0);
uniform vec4 u_expr_matcap_mul = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool u_has_matcap_tex = false;
uniform sampler2D u_matcap_tex : source_color, filter_linear_mipmap, repeat_disable;

// Rim
uniform vec3 u_rim_color = vec3(0.0, 0.0, 0.0);
uniform vec4 u_expr_rim_mul = vec4(1.0, 1.0, 1.0, 1.0);
uniform float u_rim_fresnel_power = 5.0;
uniform float u_rim_lift = 0.0;
uniform float u_rim_lighting_mix = 1.0;
uniform bool u_has_rim_tex = false;
uniform sampler2D u_rim_tex : source_color, filter_linear_mipmap, repeat_enable;

// UV Animation
uniform bool u_has_uv_anim_mask = false;
uniform sampler2D u_uv_anim_mask_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float u_uv_anim_scroll_x = 0.0;
uniform float u_uv_anim_scroll_y = 0.0;
uniform float u_uv_anim_rotation = 0.0;

vec2 compute_mtoon_uv(vec2 base_uv) {
	vec2 uv = base_uv * u_uv_scale + u_uv_offset;
	uv = uv * u_expr_uv_scale + u_expr_uv_offset;
	float mask = 1.0;
	if (u_has_uv_anim_mask) {
		mask = texture(u_uv_anim_mask_tex, uv).b;
	}
	float angle = u_uv_anim_rotation * vv_time * mask;
	if (abs(angle) > 0.00001) {
		vec2 centered = uv - vec2(0.5);
		float s = sin(angle);
		float c = cos(angle);
		uv = vec2(centered.x * c - centered.y * s, centered.x * s + centered.y * c) + vec2(0.5);
	}
	uv += vec2(u_uv_anim_scroll_x, u_uv_anim_scroll_y) * vv_time * mask;
	return uv;
}

void fragment() {
	vec2 uv = compute_mtoon_uv(UV);

	vec4 base = u_base_color * u_expr_color_mul;
	if (u_has_base_tex) {
		base *= texture(u_base_tex, uv);
	}

	if (u_is_alpha_mask) {
		if (base.a < u_alpha_cutoff) {
			discard;
		}
	}
	// ALPHA_OUTPUT_LINE

	if (u_has_normal_tex) {
		NORMAL_MAP = texture(u_normal_tex, uv).xyz;
		NORMAL_MAP_DEPTH = u_normal_scale;
	}

	vec3 emissive = u_emissive_color * u_expr_emissive_mul.rgb;
	if (u_has_emissive_tex) {
		emissive *= texture(u_emissive_tex, uv).rgb;
	}

	// MatCap (view-space normal projection)
	vec3 matcap_term = vec3(0.0);
	if (u_has_matcap_tex) {
		vec3 view_up = vec3(0.0, 1.0, 0.0);
		vec3 view_dir = normalize(VIEW);
		vec3 x_axis = normalize(cross(view_up, view_dir));
		if (length(x_axis) < 0.001) {
			x_axis = vec3(1.0, 0.0, 0.0);
		}
		vec3 y_axis = cross(view_dir, x_axis);
		vec2 matcap_uv = vec2(dot(x_axis, NORMAL), dot(y_axis, NORMAL)) * 0.495 + vec2(0.5);
		matcap_uv.y = 1.0 - matcap_uv.y;
		matcap_term = texture(u_matcap_tex, matcap_uv).rgb * u_matcap_color * u_expr_matcap_mul.rgb;
	}

	// Parametric Rim (unlit portion + ambient; light-mixed portion approximated cleanly)
	float fresnel = pow(clamp(1.0 - max(dot(NORMAL, VIEW), 0.0) + u_rim_lift, 0.0, 1.0), max(0.001, u_rim_fresnel_power));
	vec3 rim = u_rim_color * u_expr_rim_mul.rgb * fresnel;
	if (u_has_rim_tex) {
		rim *= texture(u_rim_tex, uv).rgb;
	}

	if (u_is_unlit) {
		ALBEDO = base.rgb + emissive + matcap_term + rim;
		EMISSION = vec3(0.0);
		ROUGHNESS = 1.0;
	} else {
		vec3 lit_col = base.rgb;
		vec3 raw_shade = lit_col * u_shade_color * u_expr_shade_mul.rgb;
		if (u_has_shade_tex) {
			raw_shade = texture(u_shade_tex, uv).rgb * u_shade_color * u_expr_shade_mul.rgb * u_base_color.rgb * u_expr_color_mul.rgb;
		}
		vec3 sc = raw_shade * vv_shade_tint;
		// 1 まではモデルの影色へ近づけ、1 を超えたら影色をさらに暗くする (影色が明るいモデルでも差が出るように)
		vec3 eff_shade = vv_shade_strength <= 1.0 ? mix(lit_col, sc, vv_shade_strength)
				: sc * mix(1.0, 0.15, clamp(vv_shade_strength - 1.0, 0.0, 1.0));
		float shift = u_shading_shift;
		if (u_has_shading_shift_tex) {
			shift += texture(u_shading_shift_tex, uv).g * u_shading_shift_tex_scale;
		}
		// Base ambient / GI contribution weighted by giEqualization & LightingRig ambient
		vec3 gi_approx = mix(eff_shade, lit_col, 0.5) * vv_ambient_color * (vv_ambient_energy / 0.45) * (0.08 + 0.08 * u_gi_equalization);
		EMISSION = emissive + matcap_term + rim * (1.0 - 0.5 * u_rim_lighting_mix) + gi_approx;
		// Pass precomputed lit/shade/shift into light() without re-sampling textures per light
		ALBEDO = max(lit_col, vec3(0.001));
		BACKLIGHT = eff_shade;
		ROUGHNESS = clamp(shift * 0.25 + 0.5, 0.0, 1.0);
	}
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

void light() {
	if (!u_is_unlit) {
		float shift = (ROUGHNESS - 0.5) * 4.0;
		float ndotl = dot(NORMAL, LIGHT);
		float shading = ndotl + shift + vv_shade_shift;
		float toony = clamp(u_shading_toony + vv_toony_offset, 0.0, 0.999);
		float min_v = -1.0 + toony;
		float max_v = 1.0 - toony;
		float t = clamp((shading - min_v) / max(0.0001, max_v - min_v), 0.0, 1.0);
		float atten = min(ATTENUATION, t);

		vec3 direct_col = mix(BACKLIGHT, ALBEDO, atten);
		// 落ち影 (ATTENUATION が下がった所) をさらに暗く
		direct_col *= 1.0 - clamp(vv_cast_dark, 0.0, 1.0) * 0.85 * (1.0 - ATTENUATION);
		vec3 light_energy = LIGHT_COLOR * (0.68 / 3.14159265);
		DIFFUSE_LIGHT += (direct_col / ALBEDO) * light_energy;
	}
}
