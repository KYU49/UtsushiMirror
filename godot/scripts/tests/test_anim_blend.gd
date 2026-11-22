extends SceneTree
## 動きを切り替えるときのつなぎ (姿勢の違いに合わせた長さと ease out) を確かめる。
## 実行: godot --headless --path godot -s res://scripts/tests/test_anim_blend.gd
const L := preload("res://scripts/vrm/vrma_loader.gd")
var _ok := true


func _check(label: String, cond: bool) -> void:
	print(("OK   " if cond else "NG   ") + label)
	_ok = _ok and cond


func _clip(rel: String):
	var r: Dictionary = L.load_vrma(ProjectSettings.globalize_path("res://../assets/animations/" + rel))
	return r.get("clip")


func _initialize() -> void:
	var P = L.VrmaPlayer
	# ease out: 始めは速く、終わりはゆっくり
	_check("ease out の端", is_equal_approx(P.ease_out(0.0), 0.0) and is_equal_approx(P.ease_out(1.0), 1.0))
	_check("ease out は前半で大きく進む", P.ease_out(0.5) > 0.85)
	_check("ease out は終わり近くでほとんど動かない", P.ease_out(1.0) - P.ease_out(0.9) < 0.01)

	# つなぐ長さ
	_check("小さな違いは指定のまま", is_equal_approx(P.auto_blend_sec(0.25, 10.0), 0.25))
	_check("大きな違いは 1 秒", is_equal_approx(P.auto_blend_sec(0.25, 150.0), 1.0))
	_check("中くらいは間", P.auto_blend_sec(0.25, 75.0) > 0.5 and P.auto_blend_sec(0.25, 75.0) < 0.75)
	_check("つながない指定 (0) はそのまま", P.auto_blend_sec(0.0, 150.0) == 0.0)
	_check("長めの指定は縮めない", is_equal_approx(P.auto_blend_sec(1.5, 150.0), 1.5))

	# 実際の動きで姿勢の違いを測る
	var apose = _clip("for-test_a-pose.vrma")
	var tpose = _clip("for-test_t-pose.vrma")
	var squat = _clip("for-test_squat.vrma")
	var a: Dictionary = apose.evaluate(0.0, 0.9)
	var same: float = P.pose_distance_deg(a, apose.evaluate(0.0, 0.9))
	var at: float = P.pose_distance_deg(a, tpose.evaluate(0.0, 0.9))
	print("A→A %.1f 度, A→T %.1f 度" % [same, at])
	_check("同じ姿勢の違いは 0", same < 0.5)
	_check("A ポーズ → T ポーズは腕が大きく違う", at > 30.0)
	var deep := 0.0
	for i in range(21):
		var t: float = squat.duration * i / 20.0
		deep = maxf(deep, P.pose_distance_deg(a, squat.evaluate(t, 0.9)))
	print("A→しゃがみ (最大) %.1f 度" % deep)
	_check("しゃがむ姿勢は A ポーズから大きく違い、1 秒近くかけてつなぐ", P.auto_blend_sec(0.25, deep) > 0.8)

	# 再生の切り替えで、つなぐ長さが姿勢の違いで決まる
	var player = P.new()
	player.add_clip("a", apose)
	player.add_clip("t", tpose)
	player.play("a", true, 1.0, 0.0)
	player.sample_pose(0.1, null)
	player.play("t", true, 1.0, 0.25)
	print("A→T のつなぎ %.2f 秒" % player._blend_duration)
	_check("A→T は 0.25 秒より長くつなぐ", player._blend_duration > 0.3)
	var p1: Dictionary = player.sample_pose(player._blend_duration * 0.5, null)
	var half: float = P.pose_distance_deg(p1, tpose.evaluate(0.0, 0.9))
	print("半分の時間で残りの違い %.1f 度 (全体 %.1f 度)" % [half, at])
	_check("半分の時間で 8 割以上進む (ease out)", half < at * 0.2)

	print("TEST_ANIM_BLEND_RESULT=", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)
