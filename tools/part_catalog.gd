extends RefCounted
## 32 件部件池 —— **唯一的定义源**
##
## `data/parts/*.tres` 由本表生成（`tools/gen_data.gd`）。
## 要改部件，改这里然后重跑生成脚本；**不要**在编辑器里手改 .tres，会被覆盖。
##
## 【为什么是 32 件而不是更少】
## 技术上，每类只要有「正效价 / 中性 / 负效价」三档就能跑通全部判定。
## 32 件是为了**表达的丰富度** —— GDD 的核心卖点是「我想演成什么样」，
## 每类只有三个选项的话，这游戏就退化成三选一了。
##
## 【梯度是硬约束】每个 slot 内必须同时存在正效价、中性、负效价部件。
## 缺了任何一档，玩家就拼不出「递减曲线」（D 文艺片）和「帧间反转」（E 大厂），
## L3 / L4 两档难度直接死掉。
##
## emo 字典的键：joy / anger / sorrow / shock / charm / awkward，取值 0~5。
## 每件打 1~3 个标签即可，不必每个都填。

const EYES := PartData.Slot.EYES
const MOUTH := PartData.Slot.MOUTH
const BROWS := PartData.Slot.BROWS
const EXTRA := PartData.Slot.EXTRA

## slot / tier / 名字 / 情绪向量
## 【效价速查】valence = (喜+魅) − (怒+哀+尬)
const PARTS: Array[Dictionary] = [
	# ---- 眼 8 件：平静 → 睁大 → 瞪 → 含泪 → 眯笑 ----
	{"slot": EYES, "tier": 0, "name": "平静", "emo": {}},
	{"slot": EYES, "tier": 1, "name": "睁大", "emo": {"shock": 2.0}},
	{"slot": EYES, "tier": 2, "name": "瞪", "emo": {"anger": 3.0}},
	{"slot": EYES, "tier": 3, "name": "含泪", "emo": {"sorrow": 3.0}},
	{"slot": EYES, "tier": 4, "name": "眯笑", "emo": {"joy": 3.0, "charm": 1.0}},
	{"slot": EYES, "tier": 5, "name": "星星眼", "emo": {"charm": 3.0, "joy": 1.0}},
	{"slot": EYES, "tier": 6, "name": "死鱼眼", "emo": {"awkward": 3.0}},
	{"slot": EYES, "tier": 7, "name": "泪如雨下", "emo": {"sorrow": 4.0}},

	# ---- 嘴 10 件：闭合 → 微张 → 大笑 → 撇嘴 → 发抖 ----
	{"slot": MOUTH, "tier": 0, "name": "闭合", "emo": {}},
	{"slot": MOUTH, "tier": 1, "name": "微张", "emo": {"shock": 1.0}},
	{"slot": MOUTH, "tier": 2, "name": "微笑", "emo": {"joy": 2.0}},
	{"slot": MOUTH, "tier": 3, "name": "大笑", "emo": {"joy": 3.0}},
	{"slot": MOUTH, "tier": 4, "name": "抿嘴", "emo": {"awkward": 2.0}},
	{"slot": MOUTH, "tier": 5, "name": "撇嘴", "emo": {"awkward": 3.0, "anger": 1.0}},
	{"slot": MOUTH, "tier": 6, "name": "发抖", "emo": {"sorrow": 2.0, "shock": 1.0}},
	{"slot": MOUTH, "tier": 7, "name": "咬牙切齿", "emo": {"anger": 3.0}},
	{"slot": MOUTH, "tier": 8, "name": "嚎啕", "emo": {"sorrow": 3.0}},
	{"slot": MOUTH, "tier": 9, "name": "坏笑", "emo": {"charm": 2.0, "anger": 1.0}},

	# ---- 眉 8 件：舒展 → 上挑 → 紧锁 → 八字 → 斜挑 ----
	{"slot": BROWS, "tier": 0, "name": "舒展", "emo": {}},
	{"slot": BROWS, "tier": 1, "name": "上挑", "emo": {"joy": 1.0, "shock": 1.0}},
	{"slot": BROWS, "tier": 2, "name": "高扬", "emo": {"joy": 2.0}},
	{"slot": BROWS, "tier": 3, "name": "紧锁", "emo": {"anger": 2.0}},
	{"slot": BROWS, "tier": 4, "name": "倒竖", "emo": {"anger": 3.0}},
	{"slot": BROWS, "tier": 5, "name": "八字", "emo": {"sorrow": 2.0}},
	{"slot": BROWS, "tier": 6, "name": "微蹙", "emo": {"sorrow": 1.0, "awkward": 1.0}},
	{"slot": BROWS, "tier": 7, "name": "斜挑", "emo": {"charm": 2.0, "anger": 1.0}},

	# ---- 其他 6 件：可留空(None)，组合数 ×7 ----
	{"slot": EXTRA, "tier": 0, "name": "黑线", "emo": {"awkward": 3.0}},
	{"slot": EXTRA, "tier": 1, "name": "青筋", "emo": {"anger": 3.0}},
	{"slot": EXTRA, "tier": 2, "name": "汗滴", "emo": {"awkward": 2.0, "shock": 1.0}},
	{"slot": EXTRA, "tier": 3, "name": "泪珠", "emo": {"sorrow": 3.0}},
	{"slot": EXTRA, "tier": 4, "name": "红晕", "emo": {"charm": 3.0}},
	{"slot": EXTRA, "tier": 5, "name": "呆毛", "emo": {"shock": 2.0, "joy": 1.0}},
]

const SLOT_KEY := {EYES: "eyes", MOUTH: "mouth", BROWS: "brows", EXTRA: "extra"}


## 部件 ID，同时是文件名主干：eyes_04 / mouth_09 / brows_02 / extra_05
static func part_id(slot: int, tier: int) -> String:
	return "%s_%02d" % [SLOT_KEY[slot], tier]


## 只取某个槽位的部件，按 tier 升序
static func of_slot(slot: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in PARTS:
		if p["slot"] == slot:
			out.append(p)
	return out
