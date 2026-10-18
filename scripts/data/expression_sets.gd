class_name ExpressionSets
extends RefCounted
## 「复杂表情」的三套牌面 —— 周结算翻牌的**唯一数据源**
##
## 【它和 part_catalog 的关系】部件池定义每一件怎么画、有什么情绪；
## 这里只回答「哪三件属于同一张脸」「这张脸在牌面上长什么样」。
## 部件那边用 `PartData.set_id` 指回来（`tools/part_catalog.gd` 的 `"set"` 字段），
## 两边 id 必须一致 —— `tools/test_expression_reward.gd` 有一条断言钉这个。
##
## 【为什么只有三套】龙套 / 配角 / 主角三个档位各给一次奖励，一次翻一张牌，
## 三张牌背长得一样、正面就是这三套。牌翻到哪套是**结算时抽好的**（存进状态），
## 不是点击那一刻现摇 —— 读档回来不会换一张脸，玩家的选择也不必影响结果。
##
## 【为什么帧图是裁过的】原图 1920×1080、相框只占左边一块，直接排三张会挤在左边。
## 裁剪见 `tools/import_reward_frames.py`（四张共用同一个框，翻面时不会跳）。

## id / 显示名 / 三件部件 / 牌面图
## 【牌面图为什么写在这里而不是部件里】它是「一套」的视觉，不是某一件的属性；
## 三件各自存一份路径，改图时就有三处会漏。
const SETS: Array[Dictionary] = [
	{
		"id": "smug",
		"name": "得意",
		"parts": ["eyes_08", "mouth_09", "brows_07"],
		"frame": "res://assets/ui/reward/frame_smug.png",
	},
	{
		"id": "smirk",
		"name": "皮笑肉不笑",
		"parts": ["eyes_09", "mouth_10", "brows_08"],
		"frame": "res://assets/ui/reward/frame_smirk.png",
	},
	{
		"id": "late_love",
		"name": "想起已故的爱人",
		"parts": ["eyes_07", "mouth_11", "brows_09"],
		"frame": "res://assets/ui/reward/frame_late_love.png",
	},
]


## 牌背。三张牌共用这一张（正面才是不同的表情）。
const BACK_FRAME := "res://assets/ui/reward/frame_back.png"


## 全部 set id，顺序与 SETS 一致。
static func ids() -> Array[String]:
	var out: Array[String] = []
	for s: Dictionary in SETS:
		out.append(String(s["id"]))
	return out


static func by_id(id: String) -> Dictionary:
	for s: Dictionary in SETS:
		if String(s["id"]) == id:
			return s
	return {}


static func has(id: String) -> bool:
	return not by_id(id).is_empty()


static func name_of(id: String) -> String:
	var s := by_id(id)
	return String(s.get("name", ""))


static func parts_of(id: String) -> Array[String]:
	var out: Array[String] = []
	var s := by_id(id)
	for p: Variant in s.get("parts", []):
		out.append(String(p))
	return out


static func frame_of(id: String) -> String:
	return String(by_id(id).get("frame", ""))


## 这套脸在第 `tier` 档首次成功时发 —— 只用来写界面文案（"首次当上龙套"）。
## 【为什么档位不写进 SETS】奖励是「每档一次」，不是「这套只配某个档」：
## 玩家先拿到的是哪个档，翻出来的就是哪张脸。
static func tier_name(tier: int) -> String:
	return RoleRequirement.TIER_NAMES.get(tier, "?")
