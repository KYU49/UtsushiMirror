// VRMViewer 画面効果 (不透明画面用 1 パス)。本体は post_effects.gdshaderinc。
shader_type canvas_item;
render_mode blend_mix, unshaded;

#define VV_PASS_MIX
#include "res://shaders/post_effects.gdshaderinc"
