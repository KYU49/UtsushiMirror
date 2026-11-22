extends RefCounted
## アニメーションの名前から、一覧で使うカテゴリーを決める。
## - うつしみらーで作った動き: <性別>_<大分類>_<中身>_<番号>  (例: female_greeting_bow_01)
## - Quaternius の動き: 名前の単語 (Idle / Walk / Sitting など)
## - for-test_ で始まるもの: 確認用
## どれにも当たらないもの (プリセットのフォルダに自分で入れたものなど) は「その他」。

## 一覧に並べる順
const ORDER: Array[String] = [
	"待機", "あいさつ", "ポーズ", "応援・喜び", "歩く", "走る", "跳ぶ", "回る", "座る・しゃがむ",
	"しぐさ", "ダンス", "アクション", "確認用", "その他",
]

## <大分類> → カテゴリー
const GROUP := {
	"idle": "待機",
	"greeting": "あいさつ",
	"pose": "ポーズ",
	"cheer": "応援・喜び",
	"walk": "歩く",
	"run": "走る",
	"jump": "跳ぶ",
	"turn": "回る",
	"sit": "座る・しゃがむ",
	"dance": "ダンス",
}

## 名前に含まれる単語 → カテゴリー (上から順に見る)
const WORDS := [
	["sitting", "座る・しゃがむ"], ["crouch", "座る・しゃがむ"], ["laytoidle", "座る・しゃがむ"],
	["walk", "歩く"], ["jog", "走る"], ["sprint", "走る"], ["run", "走る"], ["jump", "跳ぶ"],
	["dance", "ダンス"],
	["punch", "アクション"], ["sword", "アクション"], ["spell", "アクション"], ["hit", "アクション"], ["roll", "アクション"],
	["idle", "待機"],
	["consume", "しぐさ"], ["interact", "しぐさ"], ["pickup", "しぐさ"], ["yes", "しぐさ"],
]

const GENDER := {"male": "男性", "female": "女性"}


static func category_of(clip_name: String) -> String:
	var low := clip_name.to_lower()
	if low.begins_with("for-test_"):
		return "確認用"
	var parts := low.split("_")
	if parts.size() >= 3 and GENDER.has(parts[0]) and GROUP.has(parts[1]):
		return GROUP[parts[1]]
	var flat := low.replace("_", "").replace("-", "")
	for w in WORDS:
		if flat.contains(str(w[0])):
			return str(w[1])
	return "その他"


## 名前の並び → [[カテゴリー, [名前, ...]], ...] (ORDER の順。空のカテゴリーは出さない)
static func group(names: Array) -> Array:
	var by := {}
	for n in names:
		var c := category_of(str(n))
		if not by.has(c):
			by[c] = []
		by[c].append(str(n))
	var out := []
	for c in ORDER:
		if by.has(c):
			var list: Array = by[c]
			list.sort()
			out.append([c, list])
	return out


## 性別: "female" / "male" / "" (性別の無いもの)
static func gender_of(clip_name: String) -> String:
	var p := clip_name.to_lower().get_slice("_", 0)
	return p if GENDER.has(p) else ""


## 一覧に出す短い名前。性別の頭と、末尾の _01 を落とす (female_turn_cute_01 → turn_cute)
static func short_name(clip_name: String) -> String:
	var s := clip_name
	if gender_of(s) != "":
		s = s.substr(s.find("_") + 1)
	if s.ends_with("_01"):
		s = s.substr(0, s.length() - 3)
	return s


## うつしみらーで作った動きの表示名 (<大分類>_<中身> → 日本語)
const LABELS := {
	"cheer_banzai": "バンザイ", "cheer_clap": "拍手",
	"greeting_bow": "お辞儀", "greeting_wave": "手を振る",
	"idle_handsback": "後ろで手を組む", "idle_lookaround": "見回す", "idle_relaxed": "楽に立つ",
	"idle_sway": "体を揺らす", "idle_armscrossed": "腕を組む", "idle_neck": "首をほぐす",
	"jump_normal": "ジャンプ",
	"pose_peacedouble": "ダブルピース", "pose_peacegenki": "元気にピース", "pose_peacegyaru": "ギャルピース",
	"pose_peaceshy": "照れピース", "pose_point": "指さし", "pose_pray": "祈る",
	"run_girly": "女の子走り", "run_swing": "腕を振って走る", "run_normal": "走る",
	"turn_cute": "かわいく回る", "turn_light": "軽く回る", "turn_spread": "腕を広げて回る",
	"turn_cool": "かっこよく回る", "turn_simple": "回る",
	"walk_normal": "歩く", "walk_wild": "ワイルドに歩く",
	"sit_chair": "椅子に座る",
}

## そのほかの動き (Quaternius・確認用) の表示名
const NAMES := {
	"Consume": "食べる・飲む", "Crouch_Idle_Loop": "しゃがむ", "Dance_Loop": "踊る", "Hit_Chest": "胸を打たれる",
	"Idle_FoldArms_Loop": "腕を組んで待つ", "Idle_Loop": "立って待つ", "Idle_No_Loop": "首を横に振る",
	"Idle_TalkingPhone_Loop": "電話で話す", "Idle_Talking_Loop": "話す", "Interact": "物に触れる",
	"Jog_Fwd_Loop": "ジョギング", "Jump_Loop": "跳んでいる (空中)", "LayToIdle": "寝た姿勢から起きる",
	"PickUp_Table": "机の物を取る", "Punch_Jab": "ジャブ", "Roll": "前転",
	"Sitting_Enter": "座る", "Sitting_Exit": "立ち上がる", "Sitting_Idle_Loop": "座って待つ",
	"Sitting_Talking_Loop": "座って話す", "Spell_Simple_Idle_Loop": "魔法を構える", "Spell_Simple_Shoot": "魔法を放つ",
	"Sprint_Loop": "全力で走る", "Sword_Idle": "剣を構える", "Walk_Formal_Loop": "姿勢よく歩く",
	"Walk_Loop": "歩く (標準)", "Yes": "うなずく",
	"for-test_a-pose": "A ポーズ", "for-test_t-pose": "T ポーズ", "for-test_finger": "指の確認",
	"for-test_neck": "首の確認", "for-test_shoulder": "肩の確認", "for-test_side": "横向きの確認",
	"for-test_squat": "スクワット",
}


## 一覧やメニューに出す名前。知らないもの (自分で入れたものなど) は短い名前のまま
static func display_name(clip_name: String) -> String:
	if NAMES.has(clip_name):
		return str(NAMES[clip_name])
	var parts := clip_name.to_lower().split("_")
	if parts.size() >= 3 and GENDER.has(parts[0]):
		var num := ""
		var body := parts.slice(1)
		if body.size() >= 3 and str(body[-1]).is_valid_int():
			num = str(body[-1])
			body = body.slice(0, body.size() - 1)
		var key := "_".join(body)
		if LABELS.has(key):
			var n := num.to_int()
			return str(LABELS[key]) + (" %d" % n if n >= 2 else "")
	return short_name(clip_name)


## 2 列の表の行に並べる。戻り値は [[左のセル, 右のセル], ...]。セルは {"kind", "text", "name"}
## kind: "category" (カテゴリーの見出し) / "gender" (女性・男性・共通の見出し) / "clip" / "blank"
## 同じ中身の女性版と男性版は同じ行に。対の無いものは、残り同士を上から順に並べる。
## 性別の無いものは「共通」の下に 2 列で。with_category が false ならカテゴリーの見出しを出さない。
static func layout(names: Array, with_category: bool = true, only: String = "") -> Array:
	var rows := []
	var blank := {"kind": "blank", "text": "", "name": ""}
	var cell := func(n: String) -> Dictionary: return {"kind": "clip", "text": display_name(n), "name": n}
	for g in group(names):
		if only != "" and g[0] != only:
			continue
		if with_category:
			rows.append([{"kind": "category", "text": "― %s ―" % g[0], "name": ""}, blank])
		var fem := {}
		var mal := {}
		var com := []
		for n in g[1]:
			match gender_of(n):
				"female":
					fem[short_name(n)] = n
				"male":
					mal[short_name(n)] = n
				_:
					com.append(n)
		if not fem.is_empty() or not mal.is_empty():
			rows.append([{"kind": "gender", "text": "女性", "name": ""}, {"kind": "gender", "text": "男性", "name": ""}])
			var keys := fem.keys()
			keys.sort()
			var fl := []
			var ml := []
			for k in keys:
				if mal.has(k):
					rows.append([cell.call(fem[k]), cell.call(mal[k])])
				else:
					fl.append(fem[k])
			var mkeys := mal.keys()
			mkeys.sort()
			for k in mkeys:
				if not fem.has(k):
					ml.append(mal[k])
			for i in range(maxi(fl.size(), ml.size())):
				rows.append([cell.call(fl[i]) if i < fl.size() else blank, cell.call(ml[i]) if i < ml.size() else blank])
			if not com.is_empty():
				rows.append([{"kind": "gender", "text": "共通", "name": ""}, blank])
		for i in range(0, com.size(), 2):
			rows.append([cell.call(com[i]), cell.call(com[i + 1]) if i + 1 < com.size() else blank])
	return rows
