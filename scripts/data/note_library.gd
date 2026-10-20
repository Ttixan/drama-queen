class_name NoteLibrary
extends RefCounted
## 抄录手册的**内容**（4 张便签）—— 从 `.document/scripts/tips/theory.md` 拆出来的。
##
## 【为什么内容在代码里，不像事件那样 md → tres】这四段是**界面文案**：
## 不进玩法、不参与存档、没有数值，一共四张便签。为它造一套 md 解析 + 生成器，
## 比内容本身还长。等哪天便签要按周解锁 / 有几十条，再照 `events.md` 那套搬。
##
## 【为什么便签只写标题、正文在三级页】便签贴在本子上是"索引"，
## 玩家一眼看到的是「哪一页写了什么」；正文塞进 380×420 的小纸片会挤成一团。
##
## 【拆法照原文】基础情绪 8 条、复合情绪 24 条分三组（初级 / 次级 / 三级），
## 正好是四张纸。原文里的「三、四级」编号是分组标题，不是第几条。

const NOTES: Array[Dictionary] = [
	{
		"title": "基础情绪（8 种）",
		"lines": [
			"喜悦", "信任", "恐惧", "惊讶",
			"悲伤", "厌恶", "愤怒", "期待",
		],
	},
	{
		"title": "初级复合情绪（8 种）",
		"lines": [
			"爱 = 喜悦 + 信任",
			"顺从 = 信任 + 恐惧",
			"敬畏 = 恐惧 + 惊讶",
			"失望 = 惊讶 + 悲伤",
			"悔恨 = 悲伤 + 厌恶",
			"轻蔑 = 厌恶 + 愤怒",
			"攻击性 = 愤怒 + 期待",
			"乐观 = 期待 + 喜悦",
		],
	},
	{
		"title": "次级复合情绪（8 种）",
		"lines": [
			"内疚 = 喜悦 + 恐惧",
			"焦虑 = 期待 + 恐惧",
			"喜悦 = 喜悦 + 惊讶",
			"绝望 = 恐惧 + 悲伤",
			"羞耻 = 恐惧 + 厌恶",
			"忮忌 = 悲伤 + 愤怒",
			"悲观 = 悲伤 + 期待",
			"病态 = 厌恶 + 喜悦",
		],
	},
	{
		"title": "三级复合情绪（8 种）",
		"lines": [
			"自豪 = 愤怒 + 喜悦",
			"支配 = 愤怒 + 信任",
			"好奇 = 信任 + 惊讶",
			"多愁善感 = 信任 + 悲伤",
			"宿命论 = 信任 + 期待",
			"休克 = 惊讶 + 厌恶",
			"愠怒 = 悲伤 + 愤怒",
			"愤怒 = 惊讶 + 愤怒",
		],
	},
]


static func count() -> int:
	return NOTES.size()


## 第 i 张便签。越界返回空字典 —— 调用方不用到处判长度
static func note_at(index: int) -> Dictionary:
	if index < 0 or index >= NOTES.size():
		return {}
	return NOTES[index]


## 便签正文：每行前面加「· 」，与 `theory.md` 的写法一致。
## 【为什么不在数据里写死「· 」】副标题（`（8 种）`）不该带点；
## 而且以后要换成项目符号 / 编号，只改这一处。
static func body_text(index: int) -> String:
	var note := note_at(index)
	if note.is_empty():
		return ""
	var lines: Array = note.get("lines", [])
	var out: PackedStringArray = []
	for line: String in lines:
		out.append("· " + line)
	return "\n".join(out)
