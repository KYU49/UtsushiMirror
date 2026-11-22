// VRMViewer 画面効果 (ポストエフェクト)
//
// メイン画面と出力ビューポート (OBS / 仮想カメラ / スクショ / 録画) の最前面に置いた ColorRect に掛ける。
// 1 パスで「色の調整 → 絵づくり (アニメ・絵画) → 光のにじみ → レンズ・フィルムの質感」を順に行う。
// どの効果も既定値では何もしない。プリセット (アニメ風・ドラマ風・シネマ風・古い映画風など) は
// scripts/core/post_effects.gd が値の組み合わせとして持つ。
//
// 参考にした考え方:
// - Godot 公式「Custom post-processing」(hint_screen_texture を読む全画面 ColorRect)
// - 色の割り振り (split toning) = 暗部と明部に別々の色味 (シネマのティール & オレンジ)
// - Black Pro-Mist などの拡散フィルター = 明るい部分のぼけを薄く重ねる (diffusion) / フィルムのハレーション
// - Kuwahara フィルター = 領域ごとの分散が最小の平均を使う絵画風 (Acerola の解説・godotshaders の移植)
// - Sobel のエッジ検出 + 明るさの段階化 = セル画風
//
// 透過ウィンドウ・Spout2 の透過を壊さない仕組み:
//   Godot の画面の写し (hint_screen_texture) はアルファが常に 1 になるため、元のアルファは読めない。
//   そこで書き込み先のアルファを変えない合成を 2 回に分けて使う。
//   1 回目 (post_effects_mul.gdshader, blend_mul):   色 × m (m = 効果後 / 元、1 以下)。アルファは × 1 で不変。
//   2 回目 (post_effects_add.gdshader, blend_premul_alpha, アルファ 0): 足りない明るさ (効果後 - 元 × m) を足す。
//   どちらも書き込み先のアルファを変えないので、透過はそのまま残る。
//   protect_clear = 透過の画面では、何も描かれていない所 (色が 0) に色を足さない。
// このファイルは共通部分。shader_type / render_mode と VV_PASS_MUL / VV_PASS_ADD は読み込む側が決める。

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform bool protect_clear = false;

uniform float strength : hint_range(0.0, 1.0) = 1.0;

// ---- 色
uniform float exposure = 0.0;          // 段 (EV)
uniform float contrast = 1.0;
uniform float saturation = 1.0;
uniform float vibrance = 0.0;          // 色の薄いところだけ鮮やかに
uniform float temperature = 0.0;       // + 暖色 / - 寒色
uniform float tint = 0.0;              // + マゼンタ / - グリーン
uniform float black_lift = 0.0;        // 黒を持ち上げる (フィルムのマット感)
uniform float highlight_roll = 0.0;    // 白飛びを抑えて柔らかく
uniform vec3 shadow_color : source_color = vec3(0.5);
uniform float shadow_amount = 0.0;
uniform vec3 highlight_color : source_color = vec3(0.5);
uniform float highlight_amount = 0.0;
uniform float sepia = 0.0;
uniform float mono = 0.0;

// ---- 絵づくり
uniform float posterize = 0.0;         // 明るさの段数 (0 = なし)
uniform float edge = 0.0;              // 輪郭線の濃さ
uniform float edge_threshold = 0.08;
uniform vec3 edge_color : source_color = vec3(0.12, 0.09, 0.14);
uniform float kuwahara = 0.0;          // 絵画風の筆の大きさ (画素, 0 = なし。小数は前後の大きさを混ぜる)

// ---- 光
uniform float diffusion = 0.0;         // 明るい部分の柔らかいにじみ (Pro-Mist)
uniform float diffusion_threshold = 0.6;
uniform float halation = 0.0;          // 明るい部分の周りの赤いにじみ (フィルム)
uniform float glow = 0.0;              // 全体を少しふんわり (ソフトフォーカス)
uniform float softness = 0.0;          // 全体のぼけ (古いレンズ)
uniform float sharpen = 0.0;

// ---- レンズ・フィルム・ビデオ
uniform float vignette = 0.0;
uniform float chroma = 0.0;            // 色収差
uniform float grain = 0.0;
uniform float grain_fps = 24.0;
uniform float scratches = 0.0;
uniform float dust = 0.0;
uniform float flicker = 0.0;
uniform float jitter = 0.0;            // フィルムの揺れ (ゲートウィーブ)
uniform float scanlines = 0.0;
uniform float vhs = 0.0;               // ビデオテープの横揺れ・にじみ
uniform float letterbox = 0.0;         // 画面の縦横比 (2.39 など, 0 = なし)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 kuwahara_filter(vec2 uv, vec2 px, int r) {
	vec3 m0 = vec3(0.0); vec3 m1 = vec3(0.0); vec3 m2 = vec3(0.0); vec3 m3 = vec3(0.0);
	vec3 s0 = vec3(0.0); vec3 s1 = vec3(0.0); vec3 s2 = vec3(0.0); vec3 s3 = vec3(0.0);
	for (int j = -r; j <= r; j++) {
		for (int i = -r; i <= r; i++) {
			vec3 c = textureLod(screen_tex, uv + vec2(float(i), float(j)) * px, 0.0).rgb;
			vec3 c2 = c * c;
			if (i <= 0 && j <= 0) { m0 += c; s0 += c2; }
			if (i >= 0 && j <= 0) { m1 += c; s1 += c2; }
			if (i <= 0 && j >= 0) { m2 += c; s2 += c2; }
			if (i >= 0 && j >= 0) { m3 += c; s3 += c2; }
		}
	}
	float n = float((r + 1) * (r + 1));
	m0 /= n; m1 /= n; m2 /= n; m3 /= n;
	float v0 = dot(abs(s0 / n - m0 * m0), vec3(1.0));
	float v1 = dot(abs(s1 / n - m1 * m1), vec3(1.0));
	float v2 = dot(abs(s2 / n - m2 * m2), vec3(1.0));
	float v3 = dot(abs(s3 / n - m3 * m3), vec3(1.0));
	vec3 best = m0;
	float bv = v0;
	if (v1 < bv) { bv = v1; best = m1; }
	if (v2 < bv) { bv = v2; best = m2; }
	if (v3 < bv) { best = m3; }
	return best;
}

// 小数の大きさ: 前後の整数の大きさの結果を混ぜる (0.5 = 元の色と大きさ 1 の半々)
vec3 kuwahara_soft(vec2 uv, vec2 px, float k, vec3 orig) {
	int r0 = int(floor(k));
	float f = k - float(r0);
	vec3 a = r0 > 0 ? kuwahara_filter(uv, px, r0) : orig;
	if (f < 0.01) {
		return a;
	}
	return mix(a, kuwahara_filter(uv, px, r0 + 1), f);
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec4 src = textureLod(screen_tex, SCREEN_UV, 0.0);
	vec3 base = src.rgb;
	float posterize_fw = posterize >= 2.0 ? fwidth(luma(base) * posterize) : 0.0;

	bool in_bar = false;
	if (letterbox > 0.0) {
		float aspect = px.y / px.x;
		if (aspect < letterbox) {
			float f = aspect / letterbox;
			in_bar = abs(SCREEN_UV.y - 0.5) > f * 0.5;
		} else {
			float f = letterbox / aspect;
			in_bar = abs(SCREEN_UV.x - 0.5) > f * 0.5;
		}
	}

	bool empty = protect_clear && max(max(base.r, base.g), base.b) < 0.5 / 255.0;
	if (in_bar) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else if (empty) {
#if defined(VV_PASS_MIX)
		COLOR = vec4(base, 1.0);
#elif defined(VV_PASS_MUL)
		COLOR = vec4(1.0);
#else
		COLOR = vec4(0.0);
#endif
	} else {

	float frame_t = floor(TIME * grain_fps);
	vec2 uv = SCREEN_UV;

	// フィルムの揺れ (コマごとに少しずれる)
	if (jitter > 0.0) {
		uv += (vec2(hash(vec2(frame_t, 1.3)), hash(vec2(frame_t, 7.1))) - 0.5) * px * 5.0 * jitter;
	}
	// ビデオテープの横揺れとトラッキングの乱れ
	if (vhs > 0.0) {
		float line = floor(uv.y / px.y);
		uv.x += (hash(vec2(line * 0.013, frame_t)) - 0.5) * px.x * 3.0 * vhs;
		float band = abs(fract(uv.y * 0.6 - TIME * 0.11) - 0.5);
		uv.x += (1.0 - smoothstep(0.0, 0.03, band)) * px.x * 18.0 * vhs;
	}

	vec3 col;
	if (chroma > 0.0 || vhs > 0.0) {
		vec2 off = (uv - 0.5) * 0.006 * chroma + vec2(px.x * 2.5 * vhs, 0.0);
		col.r = textureLod(screen_tex, uv + off, 0.0).r;
		col.g = textureLod(screen_tex, uv, 0.0).g;
		col.b = textureLod(screen_tex, uv - off, 0.0).b;
	} else {
		col = textureLod(screen_tex, uv, 0.0).rgb;
	}
	if (kuwahara > 0.0) {
		col = kuwahara_soft(uv, px, min(kuwahara, 8.0), col);
	}
	if (softness > 0.0) {
		col = mix(col, textureLod(screen_tex, uv, 1.6).rgb, clamp(softness, 0.0, 1.0));
	}
	if (sharpen > 0.0) {
		col += (col - textureLod(screen_tex, uv, 1.0).rgb) * sharpen;
	}

	// 輪郭線 (明るさの Sobel)
	float e = 0.0;
	if (edge > 0.0) {
		float tl = luma(textureLod(screen_tex, uv + vec2(-px.x, -px.y), 0.0).rgb);
		float tc = luma(textureLod(screen_tex, uv + vec2(0.0, -px.y), 0.0).rgb);
		float tr = luma(textureLod(screen_tex, uv + vec2(px.x, -px.y), 0.0).rgb);
		float ml = luma(textureLod(screen_tex, uv + vec2(-px.x, 0.0), 0.0).rgb);
		float mr = luma(textureLod(screen_tex, uv + vec2(px.x, 0.0), 0.0).rgb);
		float bl = luma(textureLod(screen_tex, uv + vec2(-px.x, px.y), 0.0).rgb);
		float bc = luma(textureLod(screen_tex, uv + vec2(0.0, px.y), 0.0).rgb);
		float br = luma(textureLod(screen_tex, uv + vec2(px.x, px.y), 0.0).rgb);
		float gx = (tr + 2.0 * mr + br) - (tl + 2.0 * ml + bl);
		float gy = (bl + 2.0 * bc + br) - (tl + 2.0 * tc + tr);
		e = smoothstep(edge_threshold * 0.6, edge_threshold * 1.8 + 0.06, length(vec2(gx, gy)));
	}

	// にじみ (縮小画像 = ミップマップを使った広いぼけ)
	if (diffusion > 0.0 || halation > 0.0 || glow > 0.0) {
		vec3 wide = textureLod(screen_tex, uv, 3.0).rgb * 0.5 + textureLod(screen_tex, uv, 4.5).rgb * 0.5;
		vec3 hi = max(wide - diffusion_threshold, 0.0) / max(1.0 - diffusion_threshold, 0.01);
		col = 1.0 - (1.0 - col) * (1.0 - clamp(hi * diffusion, 0.0, 1.0));   // スクリーン合成
		col += hi * vec3(1.0, 0.3, 0.1) * halation;
		col = mix(col, max(col, wide), glow);
	}

	// 色
	col *= exp2(exposure);
	col *= vec3(1.0 + 0.12 * temperature, 1.0 - 0.06 * tint, 1.0 - 0.12 * temperature);
	col = (col - 0.45) * contrast + 0.45;
	float l = luma(col);
	col = mix(vec3(l), col, saturation);
	float sat = max(col.r, max(col.g, col.b)) - min(col.r, min(col.g, col.b));
	col = mix(vec3(l), col, 1.0 + vibrance * (1.0 - clamp(sat, 0.0, 1.0)));
	float lw = clamp(luma(col), 0.0, 1.0);
	col = mix(col, col * shadow_color * 2.0, shadow_amount * (1.0 - lw) * (1.0 - lw));
	col = mix(col, col * highlight_color * 2.0, highlight_amount * lw * lw);
	// セピア: 明るさに紙の色を掛ける (白は少し黄ばんだ白になり、飛ばない)
	vec3 sep = luma(col) * vec3(1.0, 0.86, 0.66);
	col = mix(col, sep, sepia);
	col = mix(col, vec3(luma(col)), mono);

	// セル画風: 色味は保ったまま明るさを段にする。
	// 段の境目は少し幅を持たせてなめらかにつなぐ (きっちり切ると、境目がギザギザ・ザラザラになる)
	if (posterize >= 2.0) {
		float l0 = max(luma(col), 1e-4);
		float y = l0 * posterize - 0.5;
		float w = clamp(posterize_fw * 1.5, 0.12, 0.45);
		float lq = (floor(y) + smoothstep(0.5 - w, 0.5 + w, fract(y)) + 0.5) / posterize;
		// 暗い所を何倍にも持ち上げると色が飛ぶ (目が赤くなる等) ので、倍率は 0.7〜1.2 に収める
		col *= mix(1.0, clamp(lq / l0, 0.7, 1.2), 0.85);
	}
	col = mix(col, edge_color, clamp(e * edge, 0.0, 1.0));
	col = black_lift + col * (1.0 - black_lift - highlight_roll * 0.5);

	// フィルムの質感
	if (flicker > 0.0) {
		col *= 1.0 + (hash(vec2(frame_t, 9.0)) - 0.5) * flicker * 0.3;
	}
	if (scratches > 0.0) {
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			float x = hash(vec2(frame_t, fi * 5.1 + 0.3));
			float show = step(0.55, hash(vec2(frame_t, fi + 2.7)));
			float d = abs(uv.x - x) / px.x;
			float ln = (1.0 - smoothstep(0.0, 1.2, d)) * show;
			ln *= step(0.3, hash(vec2(floor(uv.y / px.y / 40.0), frame_t + fi)));
			col = mix(col, vec3(0.92, 0.88, 0.78), ln * scratches * 0.7);
		}
	}
	if (dust > 0.0) {
		vec2 grid = vec2(28.0, 16.0);
		vec2 cell = floor(uv * grid);
		float r = hash(cell + frame_t * 1.7);
		if (r > 1.0 - 0.025 * dust) {
			vec2 c = (cell + vec2(hash(cell + 3.1 + frame_t), hash(cell + 5.7 + frame_t))) / grid;
			float size = 1.5 + 4.0 * hash(cell + frame_t + 1.1);
			float d = length((uv - c) / px) / size;
			col = mix(col, vec3(0.06, 0.05, 0.04), (1.0 - smoothstep(0.5, 1.0, d)) * 0.85);
		}
	}
	if (grain > 0.0) {
		float n = hash(floor(uv / px / 1.5) + frame_t * 13.7) - 0.5;
		float mid = 1.0 - abs(luma(col) * 2.0 - 1.0);
		col += n * grain * (0.35 + 0.65 * mid) * 0.5;
	}
	if (scanlines > 0.0) {
		float s = 0.5 + 0.5 * sin(SCREEN_UV.y / px.y * 3.14159);
		col *= 1.0 - scanlines * 0.45 * (1.0 - s);
	}
	if (vignette > 0.0) {
		float v = smoothstep(0.9, 0.25, length(SCREEN_UV - 0.5));
		col *= mix(1.0, v, vignette);
	}

	col = clamp(col, 0.0, 1.0);
	vec3 out_col = mix(src.rgb, col, strength);
#if defined(VV_PASS_MIX)
	COLOR = vec4(out_col, 1.0);
#elif defined(VV_PASS_MUL)
	// 暗くする分: m = 効果後 / 元 (1 以下)。8bit に切り捨てて、足りない分は 2 回目で足す
	vec3 m = clamp(out_col / max(base, vec3(1e-4)), 0.0, 1.0);
	m = floor(m * 255.0) / 255.0;
	COLOR = vec4(m, 1.0);
#else
	// 明るくする分を足す (アルファ 0 の premul 合成 = 加算でアルファ不変)
	vec3 m = clamp(out_col / max(base, vec3(1e-4)), 0.0, 1.0);
	m = floor(m * 255.0) / 255.0;
	COLOR = vec4(max(out_col - base * m, vec3(0.0)), 0.0);
#endif
	}
}
