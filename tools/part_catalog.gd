extends RefCounted
## 53 件部件池 —— **唯一的定义源**
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
## 【为什么是 58 件而不是更少】
## 技术上，每类只要有「正效价 / 中性 / 负效价」三档就能跑通全部判定。
## 这个量级是为了**表达的丰富度** —— GDD 的核心卖点是「我想演成什么样」，
## 每类只有三个选项的话，这游戏就退化成三选一了。
##
## 【8 基础表情开局】玩家一开始只有 8 个基础表情（喜悦/信任/恐惧/惊讶/悲伤/
## 厌恶/愤怒/期待）的五官部件；其余按两条门解锁：记忆提取/每周放送套走 `set`
## 翻牌或 `week`（认真脸 week 2，爆缸/绿豆蛙 week 3）。
##
## 【两种"现在还不能用"，别混】
## 1. `week` = 第几周起可用（缺省 1）。只留给「爆缸笑脸 / 绿豆蛙」两套 ——
##    它们第 3 周才进池子，从 `day` 派生（`PartData.is_unlocked_at`），不进存档。
## 2. `set` = 属于哪一套"复杂表情"。那三套（得意 / 皮笑肉不笑 / 想起已故的爱人）
##    **不再按周给**，而是周结算翻牌赢来的（见 `scripts/data/expression_sets.gd`）：
##    玩家在龙套 / 配角 / 主角上**首次成功投递**，各得一次翻牌，
##    翻到哪套就开哪套（`GameState.owned_sets`，进存档）。
## 【为什么一套三件必须同门】半套可用会让玩家拼出「得意的嘴 + 皮笑肉不笑的眼睛」
## 这种画面上说不通的组合。所以 眼/嘴/眉 的 `set` / `week` 必须一致。
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

## slot / tier / 名字 / 情绪向量（可选 `week` = 解锁周次，缺省 1）
## 【效价速查】valence = (喜+魅) − (怒+哀+尬)
const PARTS: Array[Dictionary] = [
	# ---- 眼 15 件（信任 / 惊讶 / 愤怒×2 / 悲伤（忧愁）/ 喜悦 / 期待 / 厌恶 / 恐惧 /
	#      想起已故的爱人 + 得意 / 皮笑肉不笑 / 爆缸笑脸 / 绿豆蛙 / 认真脸）----
	{"slot": EYES, "tier": 0, "name": "信任", "emo": {}},
	{"slot": EYES, "tier": 1, "name": "惊讶", "emo": {"shock": 2.0}},
	{"slot": EYES, "tier": 2, "name": "愤怒", "emo": {"anger": 3.0}},
	{"slot": EYES, "tier": 3, "name": "悲伤忧愁", "emo": {"sorrow": 3.0}},
	{"slot": EYES, "tier": 4, "name": "喜悦", "emo": {"joy": 3.0, "charm": 1.0}},
	{"slot": EYES, "tier": 5, "name": "期待", "emo": {"charm": 3.0, "joy": 1.0}},
	{"slot": EYES, "tier": 6, "name": "厌恶", "emo": {"awkward": 3.0}},
	{"slot": EYES, "tier": 7, "name": "想起已故的爱人", "emo": {"sorrow": 4.0}, "set": "late_love"},
	# 「得意」的眼是半阖着斜看 —— 与同套的嘴/眉共用一组权重
	{"slot": EYES, "tier": 8, "name": "得意", "emo": {"charm": 2.0, "anger": 1.0}, "set": "smug"},
	# 眼珠发直、嘴角在笑 —— 「笑得不对劲」的那一半，与 mouth_10 同源
	{"slot": EYES, "tier": 9, "name": "皮笑肉不笑", "emo": {"joy": 1.0, "awkward": 2.0}, "set": "smirk"},
	{"slot": EYES, "tier": 10, "name": "爆缸笑脸", "emo": {"joy": 3.0}, "week": 3},
	{"slot": EYES, "tier": 11, "name": "绿豆蛙", "emo": {"awkward": 2.0}, "week": 3},
	# 10-20 补缺：恐惧眼（8 基础补全）、愤怒第二张变体、认真脸眼
	{"slot": EYES, "tier": 12, "name": "恐惧", "emo": {"sorrow": 2.0, "shock": 1.0}},
	{"slot": EYES, "tier": 13, "name": "愤怒②", "emo": {"anger": 3.0}},
	{"slot": EYES, "tier": 14, "name": "认真脸", "emo": {"shock": 1.0}, "week": 2},

	# ---- 嘴 14 件 ----
	{"slot": MOUTH, "tier": 0, "name": "认真脸", "emo": {}, "week": 2},
	{"slot": MOUTH, "tier": 1, "name": "惊讶", "emo": {"shock": 1.0}},
	{"slot": MOUTH, "tier": 2, "name": "信任", "emo": {"joy": 2.0}},
	{"slot": MOUTH, "tier": 3, "name": "喜悦", "emo": {"joy": 3.0}},
	{"slot": MOUTH, "tier": 4, "name": "期待", "emo": {"awkward": 2.0}},
	{"slot": MOUTH, "tier": 5, "name": "厌恶", "emo": {"awkward": 3.0, "anger": 1.0}},
	{"slot": MOUTH, "tier": 6, "name": "恐惧", "emo": {"sorrow": 2.0, "shock": 1.0}},
	{"slot": MOUTH, "tier": 7, "name": "愤怒", "emo": {"anger": 3.0}},
	{"slot": MOUTH, "tier": 8, "name": "悲伤忧愁", "emo": {"sorrow": 3.0}},
	{"slot": MOUTH, "tier": 9, "name": "得意", "emo": {"charm": 2.0, "anger": 1.0}, "set": "smug"},
	# 「笑得不对劲」：有喜悦的外形，但读起来发毛 —— 所以喜只给一点点，尬占大头。
	# ⚠️ 这组权重是照名字拍的，**待复核**
	{"slot": MOUTH, "tier": 10, "name": "皮笑肉不笑", "emo": {"joy": 1.0, "awkward": 2.0}, "set": "smirk"},
	# 苦笑的嘴：哀为主，但嘴角是往上提的 —— 所以带一点魅
	{"slot": MOUTH, "tier": 11, "name": "想起已故的爱人", "emo": {"sorrow": 2.0, "charm": 1.0}, "set": "late_love"},
	# 「爆缸」= 笑到引擎报废：喜 + 一点惊（笑岔气了）
	{"slot": MOUTH, "tier": 12, "name": "爆缸笑脸", "emo": {"joy": 3.0, "shock": 1.0}, "week": 3},
	{"slot": MOUTH, "tier": 13, "name": "绿豆蛙", "emo": {"awkward": 2.0, "shock": 1.0}, "week": 3},

	# ---- 眉 14 件 ----
	{"slot": BROWS, "tier": 0, "name": "信任", "emo": {}},
	{"slot": BROWS, "tier": 1, "name": "期待", "emo": {"joy": 1.0, "shock": 1.0}},
	{"slot": BROWS, "tier": 2, "name": "惊讶", "emo": {"joy": 2.0}},
	{"slot": BROWS, "tier": 3, "name": "厌恶", "emo": {"anger": 2.0}},
	{"slot": BROWS, "tier": 4, "name": "愤怒", "emo": {"anger": 3.0}},
	{"slot": BROWS, "tier": 5, "name": "悲伤忧愁", "emo": {"sorrow": 2.0}},
	{"slot": BROWS, "tier": 6, "name": "恐惧", "emo": {"sorrow": 1.0, "awkward": 1.0}},
	{"slot": BROWS, "tier": 7, "name": "得意", "emo": {"charm": 2.0, "anger": 1.0}, "set": "smug"},
	{"slot": BROWS, "tier": 8, "name": "皮笑肉不笑", "emo": {"joy": 1.0, "awkward": 2.0}, "set": "smirk"},
	{"slot": BROWS, "tier": 9, "name": "想起已故的爱人", "emo": {"sorrow": 2.0}, "set": "late_love"},
	{"slot": BROWS, "tier": 10, "name": "爆缸笑脸", "emo": {"joy": 2.0, "shock": 1.0}, "week": 3},
	{"slot": BROWS, "tier": 11, "name": "绿豆蛙", "emo": {"awkward": 2.0}, "week": 3},
	# 10-20 补缺：喜悦眉、认真脸眉
	{"slot": BROWS, "tier": 12, "name": "喜悦", "emo": {"joy": 2.0}},
	{"slot": BROWS, "tier": 13, "name": "认真脸", "emo": {"shock": 1.0}, "week": 2},

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

# ============================================================
# 展示属性（关键词表）
# ============================================================
## `关键词表 (1).docx` 里每件部件标的 **8 种基础情绪** 分值（喜悦/信任/恐惧/惊讶/
## 悲伤/厌恶/愤怒/期待）。它**只给界面标注用**，不参与判定 ——
## 判定走上面那 6 个权重（`Emotion.Kind`），两套体系别混。
## 58 件里命中 55 件（没标的意味着 docx 里没有对应行，卡片上就不显示徽章）。
const ATTR := {
"eyes_00": {"信任": 40, "期待": 20},
	"eyes_01": {"惊讶": 40, "悲伤": 20},
	"eyes_02": {"愤怒": 40, "厌恶": 20},
	"eyes_03": {"悲伤": 40, "厌恶": 10},
	"eyes_04": {"喜悦": 40, "期待": 10, "厌恶": 10},
	"eyes_05": {"期待": 50},
	"eyes_06": {"厌恶": 50},
	"eyes_07": {"悲伤": 40, "恐惧": 20},
	"eyes_08": {"厌恶": 30, "喜悦": 20},
	"eyes_09": {"喜悦": 20, "信任": 20, "厌恶": 20, "悲伤": 20},
	"eyes_10": {"喜悦": 40, "愤怒": 10, "期待": 10},
	"eyes_11": {"惊讶": 30, "恐惧": 20, "愤怒": 10},
	"eyes_12": {"恐惧": 40, "惊讶": 20},
	"eyes_13": {"愤怒": 40, "厌恶": 20},
	"eyes_14": {"喜悦": 20, "信任": 20, "悲伤": 20, "期待": 20},
	"mouth_00": {"信任": 10, "期待": 10},
	"mouth_01": {"惊讶": 30, "喜悦": 10, "厌恶": 10},
	"mouth_02": {"信任": 30, "惊讶": 15},
	"mouth_03": {"喜悦": 30, "期待": 10},
	"mouth_04": {"期待": 25, "信任": 20, "愤怒": 5},
	"mouth_05": {"厌恶": 30, "愤怒": 20},
	"mouth_06": {"恐惧": 20, "悲伤": 20, "厌恶": 10},
	"mouth_07": {"愤怒": 35, "厌恶": 15},
	"mouth_08": {"悲伤": 30, "信任": 20},
	"mouth_09": {"厌恶": 30, "喜悦": 30},
	"mouth_10": {"喜悦": 20, "厌恶": 20, "悲伤": 20},
	"mouth_11": {"悲伤": 20, "信任": 10},
	"mouth_12": {"惊讶": 25, "愤怒": 5},
	"mouth_13": {"惊讶": 30, "恐惧": 20},
	"brows_00": {"信任": 30, "恐惧": 10, "悲伤": 10},
	"brows_01": {"期待": 25, "喜悦": 15, "信任": 10},
	"brows_02": {"惊讶": 30, "喜悦": 10},
	"brows_03": {"厌恶": 20, "愤怒": 30},
	"brows_04": {"愤怒": 25, "信任": 25},
	"brows_05": {"悲伤": 30, "厌恶": 20},
	"brows_06": {"恐惧": 25, "悲伤": 25},
	"brows_07": {"喜悦": 20, "期待": 20, "信任": 10},
	"brows_08": {"喜悦": 20, "信任": 20, "期待": 10},
	"brows_09": {"悲伤": 40, "恐惧": 10, "愤怒": 10},
	"brows_10": {"愤怒": 30, "喜悦": 20, "悲伤": 10, "期待": 10},
	"brows_11": {"愤怒": 30, "惊讶": 20},
	"brows_12": {"喜悦": 30, "信任": 15, "期待": 5},
	"brows_13": {"信任": 20, "恐惧": 20, "愤怒": 20, "期待": 20},
	"extra_00": {"厌恶": 15},
	"extra_01": {"愤怒": 15, "厌恶": 5},
	"extra_02": {"惊讶": 10, "信任": 5},
	"extra_03": {"信任": 10, "厌恶": 5},
	"extra_04": {"喜悦": 10, "期待": 5},
	"extra_05": {"厌恶": 5, "愤怒": 5},
	"skin_02": {"厌恶": 5},
	"skin_04": {"喜悦": 5},
	"skin_05": {"愤怒": 5},
	"skin_06": {"悲伤": 5},
	"skin_07": {"恐惧": 5},
	"skin_08": {"惊讶": 5},
}


## 某件部件的展示属性。空字典 = 没标
static func attributes_of(id: String) -> Dictionary:
	return ATTR.get(id, {})
