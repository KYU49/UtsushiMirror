shader_type spatial;
render_mode cull_front, unshaded, depth_draw_opaque;

uniform int u_outline_mode = 0; // 0: none, 1: worldCoordinates, 2: screenCoordinates
uniform float u_outline_width = 0.0;
uniform bool u_has_outline_tex = false;
uniform sampler2D u_outline_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 u_outline_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 u_expr_outline_mul = vec4(1.0, 1.0, 1.0, 1.0);
uniform float u_outline_lighting_mix = 1.0;

uniform vec4 u_base_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool u_has_base_tex = false;
uniform sampler2D u_base_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 u_uv_scale = vec2(1.0, 1.0);
uniform vec2 u_uv_offset = vec2(0.0, 0.0);
uniform vec2 u_expr_uv_scale = vec2(1.0, 1.0);
uniform vec2 u_expr_uv_offset = vec2(0.0, 0.0);
uniform bool u_is_alpha_mask = false;
uniform float u_alpha_cutoff = 0.5;

void vertex() {
	if (u_outline_mode == 0 || u_outline_width <= 0.0) {
		VERTEX = vec3(0.0);
	} else {
		float width_mask = 1.0;
		if (u_has_outline_tex) {
			vec2 uv = UV * u_uv_scale + u_uv_offset;
			uv = uv * u_expr_uv_scale + u_expr_uv_offset;
			width_mask = textureLod(u_outline_tex, uv, 0.0).g;
		}
		float w = u_outline_width * width_mask;
		if (u_outline_mode == 2) {
			// Screen-space scaled by clip-space W so width stays consistent with distance.
			vec4 clip_pos = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
			w *= clamp(clip_pos.w, 0.25, 4.0) * 0.5;
		}
		VERTEX += NORMAL * w;
	}
}

void fragment() {
	if (u_outline_mode == 0 || u_outline_width <= 0.0) {
		discard;
	}
	vec2 uv = UV * u_uv_scale + u_uv_offset;
	uv = uv * u_expr_uv_scale + u_expr_uv_offset;
	vec4 base = u_base_color;
	if (u_has_base_tex) {
		base *= texture(u_base_tex, uv);
	}
	if (u_is_alpha_mask && base.a < u_alpha_cutoff) {
		discard;
	}
	vec3 out_col = u_outline_color.rgb * u_expr_outline_mul.rgb;
	out_col = mix(out_col, out_col * base.rgb, u_outline_lighting_mix * 0.35);
	ALBEDO = out_col;
	// OUTLINE_ALPHA_LINE
}
