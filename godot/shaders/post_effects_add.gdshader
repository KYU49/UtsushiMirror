// VRMViewer 画面効果 2 回目: 明るくする分を足す (アルファ不変)。本体は post_effects.gdshaderinc。
shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;

#define VV_PASS_ADD
#include "res://shaders/post_effects.gdshaderinc"
