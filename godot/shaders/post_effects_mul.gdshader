// VRMViewer 画面効果 1 回目: 暗くする分を掛ける (アルファ不変)。本体は post_effects.gdshaderinc。
shader_type canvas_item;
render_mode blend_mul, unshaded;

#define VV_PASS_MUL
#include "res://shaders/post_effects.gdshaderinc"
