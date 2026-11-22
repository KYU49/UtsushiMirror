extends SceneTree
## 動きのカテゴリー分けを確かめる。
## 実行: godot --headless --path godot -s res://scripts/tests/test_anim_category.gd
const C := preload("res://scripts/core/anim_category.gd")
var _ok := true


func _check(label: String, cond: bool) -> void:
	print(("OK   " if cond else "NG   ") + label)
	_ok = _ok and cond


func _initialize() -> void:
	_check("あいさつ", C.category_of("female_greeting_bow_01") == "あいさつ")
	_check("歩く (作った動き)", C.category_of("male_walk_wild_01") == "歩く")
	_check("走る (作った動き)", C.category_of("female_run_girly_01") == "走る")
	_check("ポーズ", C.category_of("female_pose_peacegyaru_01") == "ポーズ")
	_check("応援・喜び", C.category_of("male_cheer_banzai_02") == "応援・喜び")
	_check("回る", C.category_of("male_turn_cool_01") == "回る")
	_check("座る (作った動き)", C.category_of("female_sit_chair_01") == "座る・しゃがむ")
	_check("確認用", C.category_of("for-test_t-pose") == "確認用")
	_check("Quaternius の待機", C.category_of("Idle_TalkingPhone_Loop") == "待機")
	_check("Quaternius の座る", C.category_of("Sitting_Idle_Loop") == "座る・しゃがむ")
	_check("Quaternius のしゃがむ", C.category_of("Crouch_Idle_Loop") == "座る・しゃがむ")
	_check("Quaternius の走る", C.category_of("Jog_Fwd_Loop") == "走る")
	_check("Quaternius のアクション", C.category_of("Spell_Simple_Idle_Loop") == "アクション")
	_check("当てはまらないものはその他", C.category_of("my_motion") == "その他")

	# 同梱の動きは、どれも「その他」にならない
	var root := ProjectSettings.globalize_path("res://../assets/animations").simplify_path()
	var names: Array = []
	var dirs: Array = [root]
	for sub in DirAccess.get_directories_at(root):
		dirs.append(root.path_join(sub))
	for d in dirs:
		for fn in DirAccess.get_files_at(d):
			if fn.ends_with(".vrma"):
				names.append(fn.get_basename())
	var other := names.filter(func(n): return C.category_of(n) == "その他")
	_check("同梱の動き %d 個がどれもカテゴリーに入る %s" % [names.size(), str(other)], other.is_empty() and names.size() > 40)

	var g: Array = C.group(["Walk_Loop", "female_greeting_bow_01", "Idle_Loop", "male_greeting_bow_01"])
	_check("決めた順に並ぶ", g.size() == 3 and g[0][0] == "待機" and g[1][0] == "あいさつ" and g[2][0] == "歩く")
	_check("カテゴリーの中は名前順", g[1][1] == ["female_greeting_bow_01", "male_greeting_bow_01"])
	# 女性・男性の 2 列と共通
	_check("短い名前", C.short_name("female_turn_cute_01") == "turn_cute" and C.short_name("male_cheer_banzai_02") == "cheer_banzai_02" and C.short_name("Idle_Loop") == "Idle_Loop")
	var rows: Array = C.layout(["female_turn_cute_01", "male_turn_cool_01", "female_turn_spread_01", "male_turn_spread_01", "Roll", "for-test_neck"], false, "回る")
	var t := rows.map(func(r): return [r[0]["text"], r[1]["text"]])
	print("layout ", t)
	_check("女性・男性の見出しが左右に", t[0] == ["女性", "男性"])
	_check("同じ中身は同じ行に", t[1] == ["turn_spread", "turn_spread"])
	_check("対の無いもの同士を並べる", t[2] == ["turn_cute", "turn_cool"])
	_check("絞ったカテゴリー以外は出ない", rows.size() == 3)
	var rows2: Array = C.layout(["female_sit_chair_01", "male_sit_chair_01", "Sitting_Idle_Loop", "Sitting_Exit", "Crouch_Idle_Loop"])
	var t2 := rows2.map(func(r): return [r[0]["text"], r[1]["text"]])
	print("layout ", t2)
	_check("カテゴリーの見出し", t2[0][0] == "― 座る・しゃがむ ―")
	_check("共通の見出しの下に 2 列", t2[3] == ["共通", ""] and t2[4] == ["Crouch_Idle_Loop", "Sitting_Exit"] and t2[5] == ["Sitting_Idle_Loop", ""])
	var rows3: Array = C.layout(["Idle_Loop", "Idle_No_Loop"])
	_check("性別の無いカテゴリーは女性・男性の見出しを付けない", rows3.size() == 2 and rows3[1][0]["text"] == "Idle_Loop")
	_check("動きのセルは元の名前を持つ", rows2[2][0]["name"] == "female_sit_chair_01")
	print("TEST_ANIM_CATEGORY_RESULT=", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)
