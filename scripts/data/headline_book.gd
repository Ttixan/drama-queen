class_name HeadlineBook
extends Resource
## 一整本电子报标题（`data/news/headlines.md` 转出来的那本）
##
## 【为什么不拆成几十个 .tres】标题不像邮件那样按公司分文件 —— 它们是一张**表**，
## 「A 的高分」「B 的高分」只有放在一起才能一眼看出风格是否统一。
## 一个数组装整本，狗牙在检查器里能滚动浏览全部文案。

@export var entries: Array[Headline] = []


## 缺了哪几类标题 —— 测试用它断言「四张表都转进来了」，
## 而不是等玩家播到第 2 周才发现某家公司的高分标题是空的。
## 返回形如 ["MAIN B/HIGH", "EXTRA NORMAL/好剧中"] 的缺失清单。
func missing_slots() -> Array[String]:
	var out: Array[String] = []
	for code: String in ["A", "B", "C", "D", "E"]:
		for g: int in [BalanceData.Grade.LOW, BalanceData.Grade.NORMAL, BalanceData.Grade.HIGH]:
			if find_main(code, g) == null:
				out.append("MAIN %s/%s" % [code, BalanceData.grade_name(g)])
	for g: int in [BalanceData.Grade.LOW, BalanceData.Grade.NORMAL, BalanceData.Grade.HIGH]:
		for good: int in [0, 1]:
			if find_extra(g, good) == null:
				out.append("EXTRA %s/%s" % [BalanceData.grade_name(g), "好剧中" if good == 1 else "烂剧中"])
	for k: StringName in [Headline.KIND_BLACK_FAME, Headline.KIND_BLACK_FAME_REPEAT,
			Headline.KIND_EXTRA_STAR]:
		if find_kind(k) == null:
			out.append("SPECIAL " + String(k))
	return out


# ============================================================
# 查表（纯数据查找，不含「该选哪条」的规则 —— 规则在 HeadlineComposer 里）
# ============================================================
func find_main(code: String, grade: int) -> Headline:
	for h: Headline in entries:
		if h.group == Headline.Group.MAIN and h.company_code == code and h.grade == grade:
			return h
	return null


func find_extra(grade: int, play_good: int) -> Headline:
	for h: Headline in entries:
		if h.group == Headline.Group.EXTRA and h.grade == grade and h.play_good == play_good:
			return h
	return null


func find_kind(kind: StringName) -> Headline:
	for h: Headline in entries:
		if h.group == Headline.Group.SPECIAL and h.kind == kind:
			return h
	return null
