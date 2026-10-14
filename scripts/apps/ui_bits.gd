class_name UiBits
extends RefCounted
## 界面小组件 —— 重排各个 App 时会反复用到的几件东西
##
## 【为什么单独放一处】「缩略成一颗子弹、一行装不下就用省略号」这条规则，
## 在 Boss 的列表 / HR 卡、微信的联系人、录像机的部件表里都要用。
## 各写各的就会各自长歪 —— Boss 的列表第一版就是这么坏的：
## 长职位名把卡片撑成两行，右栏的「演技 8 / 未联系」被顶到另一个角落，看着像飘出来。

## 一行装得下就按文字实际宽度收窄，装不下就**截断加省略号**。
##
## 【为什么必须自己算宽度】`Label` 在横向容器里会按文字全宽展开。
## 长文案因此会把同一行的其它东西挤走（甚至换行）。这里给一个宽度上限：
## 短文本贴着文字宽（不该拉成一条长条），长文本到上限就省略号。
static func one_line(l: Label, font_size: int, max_width: float = 9999.0) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# 【为什么要留余量】`ThemeDB.fallback_font` **量不准中日韩字**（那些字要落到系统字体），
	# 算出来的宽度偏窄 —— 于是「陈女士 · 人事」被截成「陈女士 · 人事…」。
	# 宁可宽几个像素，也不要切掉半个字。
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	l.custom_minimum_size.x = minf(max_width, w * 1.15 + 12.0)
	return l


## 一颗「子弹」：小圆角块 + 一行字。**超宽就省略号，绝不换行**。
## 界面上把这些子弹按数组铺进 `HFlowContainer`，排满一行自动换行。
static func bullet(text: String, font_size: int, color: Color,
		bg: Color = Color("33333d"), max_width: float = 460.0) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UiPalette.panel(bg, 8))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_bottom", 3)
	chip.add_child(margin)

	var l := Label.new()
	l.text = text
	UiPalette.text(l, font_size, color)
	margin.add_child(one_line(l, font_size, max_width))
	return chip


## 子弹里那个 Label（内容要变的子弹，比如「未联系 → 已联系」）
static func label_in(chip: Control) -> Label:
	return chip.get_child(0).get_child(0) as Label


## 按数组铺一排子弹。每一项：{"text": String, "size": int, "color": Color}
## 空文本会被跳过 —— 「没有这项」就不显示，不编一个出来
static func bullet_flow(items: Array[Dictionary], h_sep: int = 6, v_sep: int = 6) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", h_sep)
	flow.add_theme_constant_override("v_separation", v_sep)
	for item: Dictionary in items:
		var text := String(item.get("text", ""))
		if text.strip_edges().is_empty():
			continue
		flow.add_child(bullet(text, int(item.get("size", 14)),
				item.get("color", UiPalette.TEXT_DIM)))
	return flow
