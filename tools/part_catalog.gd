extends RefCounted
## 42 件部件池 —— **唯一的定义源**
##
## `data/parts/*.tres` 由本表生成（`tools/gen_data.gd`）。
## 要改部件，改这里然后重跑生成脚本；**不要**在编辑器里手改 .tres，会被覆盖。
##
## 【名字从哪来】显示名 = 美术图层文件名的横线左边那一半（去掉括号、保留括号里的字）：
##   `悲伤（忧愁） - 眉毛.png` → 「悲伤忧愁」；
##   `肤色 - 白.png` / `配件 - 眼镜.png` 是**类别在左、名字在右**，取右边。
##   这条规则的可执行版本在 `tools/import_emoji_layers.py` 的 `title_of()`，
##   重跑导入脚本会把每个 id 的建议名打出来，改表时对着抄。
##
## 【为什么是 42 件而不是更少】
## 技术上，每类只要有「正效价 / 中性 / 负效价」三档就能跑通全部判定。
## 这个量级是为了**表达的丰富度** —— GDD 的核心卖点是「我想演成什么样」，
## 每类只有三个选项的话，这游戏就退化成三选一了。
##
## 【梯度是硬约束】每个**必填**槽位内必须同时存在正效价、中性、负效价部件。
## 缺了任何一档，玩家就拼不出「递减曲线」（D 文艺片）和「帧间反转」（E 大厂），
## L3 / L4 两档难度直接死掉。肤色不参与判定（纯外观槽），不受这条约束。
##
## emo 字典的键：joy / anger / sorrow / shock / charm / awkward，取值 0~5。
## 每件打 1~3 个标签即可，不必每个都填。

const EYES := PartData.Slot.EYES
const MOUTH := PartData.Slot.MOUTH
const BROWS := PartData.Slot.BROWS
const EXTRA := PartData.Slot.EXTRA
const SKIN := PartData.Slot.SKIN

## slot / tier / 名字 / 情绪向量
## 【效价速查】valence = (喜+魅) − (怒+哀+尬)
const PARTS: Array[Dictionary] = [
	# ---- 眼 8 件（原文：信任 / 惊讶 / 愤怒 / 悲伤（忧愁）/ 喜悦 / 期待 / 厌恶 / 想起已故的爱人）----
	{"slot": EYES, "tier": 0, "name": "信任", "emo": {}},
	{"slot": EYES, "tier": 1, "name": "惊讶", "emo": {"shock": 2.0}},
	{"slot": EYES, "tier": 2, "name": "愤怒", "emo": {"anger": 3.0}},
	{"slot": EYES, "tier": 3, "name": "悲伤忧愁", "emo": {"sorrow": 3.0}},
	{"slot": EYES, "tier": 4, "name": "喜悦", "emo": {"joy": 3.0, "charm": 1.0}},
	{"slot": EYES, "tier": 5, "name": "期待", "emo": {"charm": 3.0, "joy": 1.0}},
	{"slot": EYES, "tier": 6, "name": "厌恶", "emo": {"awkward": 3.0}},
	{"slot": EYES, "tier": 7, "name": "想起已故的爱人", "emo": {"sorrow": 4.0}},

	# ---- 嘴 11 件 ----
	{"slot": MOUTH, "tier": 0, "name": "认真脸", "emo": {}},
	{"slot": MOUTH, "tier": 1, "name": "惊讶", "emo": {"shock": 1.0}},
	{"slot": MOUTH, "tier": 2, "name": "信任", "emo": {"joy": 2.0}},
	{"slot": MOUTH, "tier": 3, "name": "喜悦", "emo": {"joy": 3.0}},
	{"slot": MOUTH, "tier": 4, "name": "期待", "emo": {"awkward": 2.0}},
	{"slot": MOUTH, "tier": 5, "name": "厌恶", "emo": {"awkward": 3.0, "anger": 1.0}},
	{"slot": MOUTH, "tier": 6, "name": "恐惧", "emo": {"sorrow": 2.0, "shock": 1.0}},
	{"slot": MOUTH, "tier": 7, "name": "愤怒", "emo": {"anger": 3.0}},
	{"slot": MOUTH, "tier": 8, "name": "悲伤忧愁", "emo": {"sorrow": 3.0}},
	{"slot": MOUTH, "tier": 9, "name": "得意", "emo": {"charm": 2.0, "anger": 1.0}},
	# 「笑得不对劲」：有喜悦的外形，但读起来发毛 —— 所以喜只给一点点，尬占大头。
	# ⚠️ 这组权重是照名字拍的，**待复核**
	{"slot": MOUTH, "tier": 10, "name": "皮笑肉不笑", "emo": {"joy": 1.0, "awkward": 2.0}},

	# ---- 眉 8 件 ----
	{"slot": BROWS, "tier": 0, "name": "信任", "emo": {}},
	{"slot": BROWS, "tier": 1, "name": "期待", "emo": {"joy": 1.0, "shock": 1.0}},
	{"slot": BROWS, "tier": 2, "name": "惊讶", "emo": {"joy": 2.0}},
	{"slot": BROWS, "tier": 3, "name": "厌恶", "emo": {"anger": 2.0}},
	{"slot": BROWS, "tier": 4, "name": "愤怒", "emo": {"anger": 3.0}},
	{"slot": BROWS, "tier": 5, "name": "悲伤忧愁", "emo": {"sorrow": 2.0}},
	{"slot": BROWS, "tier": 6, "name": "恐惧", "emo": {"sorrow": 1.0, "awkward": 1.0}},
	{"slot": BROWS, "tier": 7, "name": "得意", "emo": {"charm": 2.0, "anger": 1.0}},

	# ---- 其他 6 件：可留空(None)，组合数 ×7 ----
	# 名字取自素材 `配件 - X.png` 的右边。情绪权重按名字标过一遍，
	# **这是需要复核的内容数据**（模拟器只关心它参不参与判定，不关心它画的是什么）。
	{"slot": EXTRA, "tier": 0, "name": "要吐了", "emo": {"awkward": 3.0}},
	{"slot": EXTRA, "tier": 1, "name": "压迫感", "emo": {"anger": 3.0}},
	{"slot": EXTRA, "tier": 2, "name": "汗如雨下", "emo": {"awkward": 2.0, "shock": 1.0}},
	{"slot": EXTRA, "tier": 3, "name": "加载中", "emo": {"shock": 2.0}},
	{"slot": EXTRA, "tier": 4, "name": "脸红", "emo": {"charm": 3.0}},
	{"slot": EXTRA, "tier": 5, "name": "眼镜", "emo": {}},

	# ---- 肤色 9 件：纯外观槽，**不参与判定**（emo 全空）----
	# 【tier 0 是默认肤色】`Clip.Frame.skin` 为 null 时按它渲染，所以它必须一直是第一件。
	# 素材里的「喜 / 怒 / 悲 / 恐 / 受刺激」是画给某些表情配的脸色，
	# 现在只当外观用；要不要给它们情绪权重，得策划拍板（给了就会改变现有难度曲线）。
	{"slot": SKIN, "tier": 0, "name": "亚洲人常规肤色", "emo": {}},
	{"slot": SKIN, "tier": 1, "name": "白", "emo": {}},
	{"slot": SKIN, "tier": 2, "name": "黑", "emo": {}},
	{"slot": SKIN, "tier": 3, "name": "深肤色特定剧本_搞笑", "emo": {}},
	{"slot": SKIN, "tier": 4, "name": "喜", "emo": {}},
	{"slot": SKIN, "tier": 5, "name": "怒", "emo": {}},
	{"slot": SKIN, "tier": 6, "name": "悲", "emo": {}},
	{"slot": SKIN, "tier": 7, "name": "恐", "emo": {}},
	{"slot": SKIN, "tier": 8, "name": "受刺激", "emo": {}},
]

const SLOT_KEY := {
	EYES: "eyes", MOUTH: "mouth", BROWS: "brows", EXTRA: "extra", SKIN: "skin",
}


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
