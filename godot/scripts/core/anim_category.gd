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
