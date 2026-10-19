extends Control
## 台历 —— 桌上那本台历，也就是「你的日程与进度」
##
## 【这一版的样子】桌子铺一张模糊的主界面，台历本身是美术给的 1920×1080 插画
## （`assets/ui/calendar/page.png`），界面**住进纸面里**：
##   上：第 N 天（下面一行是周次，再下面才是提示）
##   左：2×2 四格 —— 投递 / 打工 / 上课 / 本周进度
##   右：今日状态（行动点 · 钱 · 演技 · 知名度 · 风评 · PS5）+ 重开一局
##   下：确认安排（下一天）
##
## 【坐标为什么是写死的】纸面在插画里就是固定位置（量出来 234,94 → 1686,1023），
## 而整屏按 1920×1080 等比缩放（`project.godot` 的 canvas_items + keep）。
## 所以这里的 Rect2 用的是**设计坐标**：换图、换窗口大小都不用改。
## 反过来说：插画挪了位置，这几个常量得跟着改（和桌子的 Hotspot 同一个约定）。
##
## 【字体：正文 Light / 标题 Bold】同族两支字：
##   正文 `main_font.tres`（tc-Light），标题 `title_font.tres`（tc-Bold）。
## 抬头、展示数字与卡片标题走 `TITLE_FONT`；长句、说明、按钮走正文。
## 两支都 0 缺字；缺字仍由 `main_font` / `title_font` 里的系统字体兜底。
## 【为什么还留着 FONT_EN 这个名字】只为了让 `_label()` 的默认参数与调用处不用改，
## 它和 FONT_CN 已经是同一支字体。
##
## 【职责】状态 + 今日安排 + 本周进度，外加周末结算浮层与重开一局。
## **它自己不含任何玩法逻辑**：打工、上课、结束今天全是在调 `Game` 上的方法。
## 这条边界要守住 —— 一旦把「打工 +30 元」写进这里，数值模拟器就白做了。
##
## 【返回桌面】桌子（`desk_screen.tscn`）把本场景当子页面打开，
## 所以要有回去的路：与录像机 / 微信 / Boss直聘 被嵌进手机时用的是同一套约定 ——
## `cancelled` 信号 + `enable_back()`，由调用方决定要不要露出「返回桌面」。

## 上层（桌子）把本场景当子页面打开时，玩家要回去就发这条
signal cancelled
## 「去投递」那张卡要把玩家送到手机屏的微信里 —— 但微信不归本屏管（它归手机屏），
## 所以只发请求，由桌子决定怎么切过去。
signal open_app_requested(scene_path: String)

const REPORT_SCENE := "res://scenes/main/week_report.tscn"
## 周结算的第二步：翻牌拿一套复杂表情（`scripts/apps/expression_reward.gd`）。
## 【为什么它不在周报里面】报纸是"这一周发生了什么"的**回顾**，翻牌是"你赢到了什么"的
## **发放**。塞进报纸的翻页序列，玩家会在读账目时突然被要求做选择 —— 两件事分开更清楚。
const REWARD_SCENE := "res://scenes/main/expression_reward.tscn"

const FONT_CN := preload("res://assets/fonts/main_font.tres")
const FONT_EN := FONT_CN
## 标题：同族 Bold。只给「第 N 天」「本周进度」「今日状态」这类抬头与展示数字用。
const TITLE_FONT := UiPalette.TITLE_FONT

# ============================================================
# 版面（设计坐标，1920×1080；纸面 = 234,94 → 1686,1023）
# ============================================================
## 【抬头为什么从 186 起】纸面上沿在 94，但活页圈一直垂到 ~178 ——
## 标题压在圈上会被遮住（第一版就是这么翻车的）。
const TITLE_RECT := Rect2(300, 186, 1320, 88)
const WEEK_RECT := Rect2(300, 276, 1320, 26)
const HINT_RECT := Rect2(320, 304, 1280, 24)
## 返回按钮放在**屏幕左上角、纸面之外**：它是"离开这一页"，不属于台历内容，
## 塞进纸里会和抬头抢位置（第一版试过，按钮贴着纸边很难看）。
const BACK_RECT := Rect2(40, 34, 140, 48)

const CELL := Vector2(400, 214)
const GRID_POS := Vector2(300, 340)
const GRID_GAP := Vector2(36, 30)

const SIDE_RECT := Rect2(1176, 320, 456, 520)
const CTA_RECT := Rect2(640, 858, 640, 96)

# ============================================================
# 颜色（跟着插画的纸面走：深蓝墨线 + 半透明白卡）
# ============================================================
## 纸面那套色号在 `UiPalette` 里（笔记本页也用同一套），这里只是起个短名。
const INK := UiPalette.PAGE_INK
const INK_SOFT := UiPalette.PAGE_INK_SOFT
const INK_FAINT := UiPalette.PAGE_INK_FAINT
const OK_INK := Color("1f7a4d")
## 警示色（欠债 / 负风评 / 重开待确认）。与全局 `UiPalette.DANGER` 同值：
## 「红」在这个项目里只有一种意思，别再为纸面另调一个红。
const WARN_INK := Color("e5484d")

const CARD_BG := UiPalette.PAGE_CARD
const CARD_BG_HOVER := UiPalette.PAGE_CARD_HOVER
const CARD_BG_PRESSED := UiPalette.PAGE_CARD_PRESSED
const CARD_LINE := UiPalette.PAGE_LINE
const CARD_LINE_OFF := UiPalette.PAGE_LINE_OFF

const CTA_BG := Color("1d3446")
const CTA_BG_HOVER := Color("2a4a61")
const CTA_BG_PRESSED := Color("152a3a")
const CTA_TEXT := Color("f3f8fb")
const CTA_TEXT_SOFT := Color(0.76, 0.85, 0.9)

## 「重开一局」的二次确认窗口。**为什么需要它**：一局是三周、二十一天，
## 误触一下就把进度全清了 —— 而这个按钮就贴在状态面板底部。
## 用时间戳而不是 `await`，是因为它必须能被"任何一次重新刷新"打断（见 _refresh_restart）。
const RESTART_CONFIRM_MS := 5000

@onready var _report_layer: Control = get_node("ReportLayer")
@onready var _page: Control = get_node("Page")

var _day_label: Label
var _week_label: Label
var _ap_label: Label
var _money_label: Label
var _acting_label: Label
var _fame_label: Label
var _rep_label: Label
var _ps5_label: Label
var _plan_hint: Label
var _week_list: VBoxContainer
var _info_list: VBoxContainer
var _restart_button: Button

## 「返回桌面」—— 只有被桌子当子页面打开时才露出来（见 enable_back）
var _back_button: Button
var _back_enabled := false

## 动作卡：key -> {button, title, detail, state, 颜色}
var _cards: Dictionary = {}
var _report: Node
## 正在翻的那张牌（`expression_reward.tscn`）。与 `_report` 一样住在 ReportLayer 里
var _reward: Node
## 重开按钮的待确认时间戳（毫秒）。0 = 不在待确认状态
var _restart_armed_at := 0


func _ready() -> void:
	_build_back()
	_build_title()
	_build_grid()
	_build_side()
	_build_cta()

	EventBus.state_reset.connect(_on_state_reset)
	EventBus.ap_changed.connect(_on_ap_changed)
	_refresh_all()
	# 【读档 / 上次结算没翻就退出的情况】牌存在状态里，进日历就补上这一次 ——
	# 延到本帧末尾：`_ready` 里加子节点会被本屏自己的布局再动一遍
	call_deferred("_maybe_open_reward")


# ============================================================
# 文字 / 控件小工具
# ============================================================
## 一个 Label：字体、字号、颜色一次设好。**所有中文都走这张字体**
## （`→` `｜` 缺字形，见文件头）。
func _label(parent: Node, text: String, size: int, color: Color, font: Font = FONT_CN) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiPalette.text(l, size, color)
	l.add_theme_font_override("font", font)
	parent.add_child(l)
	return l


func _place(node: Control, rect: Rect2) -> void:
	node.position = rect.position
	node.size = rect.size
	node.custom_minimum_size = rect.size


func _margin(parent: Control, pad: int, pad_v: int = -1) -> MarginContainer:
	var v := pad if pad_v < 0 else pad_v
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", pad)
	m.add_theme_constant_override("margin_right", pad)
	m.add_theme_constant_override("margin_top", v)
	m.add_theme_constant_override("margin_bottom", v)
	parent.add_child(m)
	return m


## 卡片的统一外观。纸面是浅色，所以这里全是"白卡 + 墨线"，
## 与手机屏/微信那套深色面板是两套皮 —— 不要互相抄色号。
func _style_card(b: Button) -> void:
	b.add_theme_stylebox_override("normal",
			UiPalette.button(CARD_BG, CARD_LINE, 2, 18, 0, 20))
	b.add_theme_stylebox_override("hover",
			UiPalette.button(CARD_BG_HOVER, INK, 3, 18, 0, 20))
	b.add_theme_stylebox_override("pressed",
			UiPalette.button(CARD_BG_PRESSED, OK_INK, 3, 18, 4, 20))
	b.add_theme_stylebox_override("disabled",
			UiPalette.button(Color(1, 1, 1, 0.24), CARD_LINE_OFF, 2, 18, 0, 20))


# ============================================================
# 返回桌面
# ============================================================
func _build_back() -> void:
	# 只有被桌子当子页面打开时才露出来（独立运行时它一直藏着）
	_back_button = Button.new()
	# 【不能写「← 桌面」】中文那套字体没有 ← 字形（实测），会出豆腐块 —— 改用纯汉字
	_back_button.text = "返回桌面"
	_back_button.focus_mode = Control.FOCUS_NONE
	_back_button.visible = false
	_back_button.pressed.connect(func() -> void: cancelled.emit())
	_place(_back_button, BACK_RECT)
	_page.add_child(_back_button)
	_back_button.add_theme_font_override("font", FONT_CN)
	_back_button.add_theme_font_size_override("font_size", 18)
	_back_button.add_theme_color_override("font_color", INK_SOFT)
	_back_button.add_theme_color_override("font_hover_color", INK)
	_back_button.add_theme_color_override("font_pressed_color", INK)
	_back_button.add_theme_stylebox_override("normal",
			UiPalette.button(Color(1, 1, 1, 0.4), CARD_LINE, 2, 12))
	_back_button.add_theme_stylebox_override("hover",
			UiPalette.button(Color(1, 1, 1, 0.85), INK, 2, 12))
	_back_button.add_theme_stylebox_override("pressed",
			UiPalette.button(Color(1, 1, 1, 0.95), OK_INK, 2, 12))


## 由上层（桌子）调用：露出「返回桌面」，并让 Esc / 安卓返回键也能回去。
##
## 【为什么键盘与按钮都要】PC 上是 Esc，手机上是系统返回键 —— Godot 把两者
## 都归到 `ui_cancel`，所以一个入口就够；但光有快捷键玩家发现不了，所以按钮也得有。
func enable_back() -> void:
	_back_enabled = true
	if _back_button != null:
		_back_button.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if not _back_enabled or not event.is_action_pressed("ui_cancel"):
		return
	# 【为什么要判 _report】安卓返回键的惯例是「先关掉当前弹层」。
	# 日历里可能正开着周末结算浮层，那一层才该先吃这一下。
	if _report != null or _reward != null:
		return
	get_viewport().set_input_as_handled()
	cancelled.emit()


# ============================================================
# 抬头：第 N 天
# ============================================================
func _build_title() -> void:
	# 【「第」「天」和中间的数字是两个字体】中文那套大字（38）管"第 / 天"，
	# 日期那个数字交给 BubbleDub（80）—— 台历的抬头本来就是个放大的日期，
	# 让它和右栏那些数字用同一套字，比整行硬用中文体的数字更像一块牌子。
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	_page.add_child(row)
	_place(row, TITLE_RECT)

	var left := _label(row, "第", 38, INK, TITLE_FONT)
	left.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_day_label = _label(row, "1", 80, INK, TITLE_FONT)
	_day_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_day_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var right := _label(row, "天", 38, INK, TITLE_FONT)
	right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_week_label = _label(_page, "第 1 周", 18, INK_SOFT)
	_week_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_week_label, WEEK_RECT)

	_plan_hint = _label(_page, "", 15, INK_FAINT)
	_plan_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plan_hint.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_plan_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_place(_plan_hint, HINT_RECT)


# ============================================================
# 左：2×2（三张动作卡 + 本周进度）
# ============================================================
func _build_grid() -> void:
	_cards["submit"] = _make_card("submit", "投递试镜",
			"去微信挑一个 HR，把表情包发过去", GRID_POS)
	_cards["work"] = _make_card("work", "去打工",
			"+%d 元 · 每周最多 %d 次" % [
				Economy.work_income(), BalanceLibrary.data().work_max_per_week],
			GRID_POS + Vector2(CELL.x + GRID_GAP.x, 0))
	# 【文案里不许有箭头】中文那套字体缺 `→` `←`（实测），只能写汉字 / 「，」
	_cards["class"] = _make_card("class", "上表演课",
			"%d 元，演技 +%d · 每周最多 %d 次" % [
				Economy.class_fee(), Economy.class_gain(),
				BalanceLibrary.data().class_max_per_week],
			GRID_POS + Vector2(0, CELL.y + GRID_GAP.y))

	(_cards["submit"]["button"] as Button).pressed.connect(_on_submit_pressed)
	(_cards["work"]["button"] as Button).pressed.connect(_on_work_pressed)
	(_cards["class"]["button"] as Button).pressed.connect(_on_class_pressed)

	_build_week_card(GRID_POS + Vector2(CELL.x + GRID_GAP.x, CELL.y + GRID_GAP.y))


## 一张动作卡。**内容全部 MOUSE_FILTER_IGNORE** —— 点击必须透给按钮本身，
## 否则 hover / pressed 会失灵（手机屏的 App 行踩过同一个坑）。
func _make_card(key: String, title: String, detail: String, pos: Vector2) -> Dictionary:
	var b := Button.new()
	b.name = "Card_" + key
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_page.add_child(b)
	_place(b, Rect2(pos, CELL))
	_style_card(b)

	var margin := _margin(b, 22, 18)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	# 【垂直居中】卡片比三行字高得多，顶部对齐会在下面留一大块空白
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(box)

	var title_label := _label(box, title, 32, INK, TITLE_FONT)
	var detail_label := _label(box, detail, 16, INK_SOFT)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var state_label := _label(box, "", 16, OK_INK)
	state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	return {
		"button": b, "title": title_label, "detail": detail_label, "state": state_label,
		"title_on": INK, "title_off": INK_FAINT,
		"detail_on": INK_SOFT, "detail_off": INK_FAINT,
		"ok": OK_INK, "warn": WARN_INK,
	}


## 第四格：本周进度。**不是按钮** —— 它只回答「这周还剩几次」，点了没意义。
## （重开一局放在右栏底部：它是退路，不该和今天能做的事并排。)
func _build_week_card(pos: Vector2) -> void:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(panel)
	_place(panel, Rect2(pos, CELL))
	panel.add_theme_stylebox_override("panel",
			UiPalette.panel(Color(1, 1, 1, 0.38), 18, 2, CARD_LINE))

	var margin := _margin(panel, 22, 18)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 10)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(box)

	_label(box, "本周进度", 32, INK, TITLE_FONT)

	_week_list = VBoxContainer.new()
	_week_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_week_list.add_theme_constant_override("separation", 4)
	box.add_child(_week_list)


func _week_row(key: String, value: String, unit: String) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	_week_list.add_child(row)

	var k := _label(row, key, 19, INK_SOFT)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var v := _label(row, value, 26, INK, TITLE_FONT)
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if not unit.is_empty():
		var u := _label(row, unit, 14, INK_FAINT)
		u.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


# ============================================================
# 右：今日状态
# ============================================================
func _build_side() -> void:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(panel)
	_place(panel, SIDE_RECT)
	panel.add_theme_stylebox_override("panel",
			UiPalette.panel(Color(1, 1, 1, 0.55), 18, 2, CARD_LINE))

	var margin := _margin(panel, 24, 20)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)

	_label(box, "今日状态", 32, INK, TITLE_FONT)

	_ap_label = _stat_row(box, "行动点", "点")
	_money_label = _stat_row(box, "金钱", "元")
	_acting_label = _stat_row(box, "演技", "")
	_fame_label = _stat_row(box, "知名度", "")
	_rep_label = _stat_row(box, "风评", "")
	_ps5_label = _stat_row(box, "PS5", "期")

	# 【空白留在"状态"与"杂项"之间】原来它留在杂项和重开之间，看着像忘了排。
	# 状态是每天都要看的，杂项（截止 / 欠债 / 累计）是一周才动一次，本来就该分开。
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var line := ColorRect.new()
	line.color = CARD_LINE_OFF
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)

	# 动态的补充信息（下一期截止 / 欠债 / 累计投递 / PS5 已付）—— 见 `_refresh_info`
	_info_list = VBoxContainer.new()
	_info_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_list.add_theme_constant_override("separation", 4)
	box.add_child(_info_list)

	_restart_button = Button.new()
	_restart_button.text = "重开一局"
	_restart_button.focus_mode = Control.FOCUS_NONE
	_restart_button.custom_minimum_size = Vector2(0, 44)
	_restart_button.add_theme_font_override("font", FONT_CN)
	_restart_button.add_theme_font_size_override("font_size", 16)
	_restart_button.add_theme_color_override("font_color", INK_FAINT)
	_restart_button.add_theme_color_override("font_hover_color", WARN_INK)
	_restart_button.add_theme_color_override("font_pressed_color", WARN_INK)
	_restart_button.add_theme_stylebox_override("normal",
			UiPalette.button(Color(1, 1, 1, 0.3), CARD_LINE_OFF, 1, 12))
	_restart_button.add_theme_stylebox_override("hover",
			UiPalette.button(Color(1, 1, 1, 0.6), WARN_INK, 2, 12))
	_restart_button.add_theme_stylebox_override("pressed",
			UiPalette.button(Color(1, 1, 1, 0.75), WARN_INK, 2, 12))
	_restart_button.pressed.connect(_on_restart_pressed)
	box.add_child(_restart_button)


## 一行状态：左边中文名，右边**纯数字**（BubbleDub），单位单独一个小字。
## 返回那个数字 Label —— 刷新时只改它的 text。
func _stat_row(parent: Node, key: String, unit: String) -> Label:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var k := _label(row, key, 18, INK_SOFT)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var v := _label(row, "0", 30, INK, TITLE_FONT)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	if not unit.is_empty():
		var u := _label(row, unit, 14, INK_FAINT)
		u.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return v


## 补充信息一行（中文 + 中文，不涉及大数字）
func _info_row(key: String, value: String, color: Color = INK) -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	_info_list.add_child(box)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)

	var k := _label(head, key, 16, INK_SOFT)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := _label(head, value, 16, color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


# ============================================================
# 下：确认安排（下一天）
# ============================================================
## 主动作。**它取代了原来那张「结束今天」卡** —— 位置从四宫格里挪到了底部，
## 因为「过完这一天」是整屏唯一的出关口，不该和「今天能做的事」排在同一行。
func _build_cta() -> void:
	var b := Button.new()
	b.name = "Card_end"
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_page.add_child(b)
	_place(b, CTA_RECT)
	b.add_theme_stylebox_override("normal",
			UiPalette.button(CTA_BG, CTA_BG, 0, 18, 0, 22))
	b.add_theme_stylebox_override("hover",
			UiPalette.button(CTA_BG_HOVER, CTA_TEXT, 2, 18, 0, 22))
	b.add_theme_stylebox_override("pressed",
			UiPalette.button(CTA_BG_PRESSED, CTA_TEXT, 2, 18, 3, 22))

	var margin := _margin(b, 24, 12)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	margin.add_child(box)

	var title := _label(box, "确认安排（下一天）", 30, CTA_TEXT, TITLE_FONT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var detail := _label(box, "", 15, CTA_TEXT_SOFT)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 这一行在主动作上是多余的（详情里已经写了"进入第几天"），建出来只为与其它卡同构
	var state := _label(box, "", 15, CTA_TEXT_SOFT)
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.visible = false

	b.pressed.connect(_on_end_day_pressed)

	_cards["end"] = {
		"button": b, "title": title, "detail": detail, "state": state,
		"title_on": CTA_TEXT, "title_off": CTA_TEXT_SOFT,
		"detail_on": CTA_TEXT_SOFT, "detail_off": CTA_TEXT_SOFT,
		"ok": CTA_TEXT_SOFT, "warn": CTA_TEXT_SOFT,
	}


# ============================================================
# 刷新：状态
# ============================================================
func _refresh_status() -> void:
	# 抬头里只有数字在 `_day_label`，「第」「天」是旁边两个静态字
	_day_label.text = str(Game.day())
	_week_label.text = "第 %d 周 · 第 %d / %d 天" % [
		Game.week(), Game.day(), GameState.TOTAL_DAYS]

	_ap_label.text = str(Game.ap_left())
	_ap_label.add_theme_color_override("font_color",
			INK if Game.ap_left() > 0 else INK_FAINT)

	_money_label.text = str(Game.money())
	# 【欠债要显眼】金钱可以为负，这件事在界面上必须一眼看出来，
	# 否则玩家只会觉得"数字变红了"，不知道那是「被解雇」结局的一半条件。
	_money_label.add_theme_color_override("font_color",
			WARN_INK if Game.money() < 0 else INK)

	_acting_label.text = str(Game.acting())
	_fame_label.text = str(Game.fame())
	_rep_label.text = "%+d" % Game.reputation()
	_rep_label.add_theme_color_override("font_color",
			WARN_INK if Game.reputation() < 0 else INK)

	var paid := Economy.ps5_installments_paid(Game.state)
	var total_rounds := BalanceLibrary.data().ps5_installments
	_ps5_label.text = "%d / %d" % [paid, total_rounds]
	_ps5_label.add_theme_color_override("font_color",
			OK_INK if Game.ps5_paid_off() else INK)


# ============================================================
# 刷新：今日安排
# ============================================================
## 一张卡的可用状态：能点就写清"点下去会发生什么"，不能点就写清"为什么"
func _set_card(key: String, enabled: bool, reason: String, ok_text: String) -> void:
	var card: Dictionary = _cards[key]
	var b: Button = card["button"]
	b.disabled = not enabled
	var sp: Label = card["state"]
	sp.text = ok_text if enabled else reason
	sp.add_theme_color_override("font_color", card["ok"] if enabled else card["warn"])
	(card["title"] as Label).add_theme_color_override("font_color",
			card["title_on"] if enabled else card["title_off"])
	(card["detail"] as Label).add_theme_color_override("font_color",
			card["detail_on"] if enabled else card["detail_off"])


func _refresh_plan() -> void:
	var over := Game.state.finished
	# 【标题也要跟着换】结束后这张卡不再是「过一天」——
	# 留着原来的字会让玩家以为还能再过一天，点下去却直接跳出结局。
	if over:
		(_cards["end"]["title"] as Label).text = "看结局"
		_plan_hint.text = "三周结束了 —— 点下面看你这三周的下场。"
		(_cards["end"]["detail"] as Label).text = "这一局已经结束，结局存在最近一期周报里"
	else:
		(_cards["end"]["title"] as Label).text = "确认安排（下一天）"
		_plan_hint.text = "一天只能做一件事。行动点用完，剩下的时间就是发呆。"
		# 这一行随天数变，建卡时那份会过期
		(_cards["end"]["detail"] as Label).text = "结束第 %d 天，进入第 %d 天" % [
				Game.day(), mini(Game.day() + 1, GameState.TOTAL_DAYS)]

	# 投递：真正能不能发，微信里还会再判一次（那里才知道有没有表情包、投哪家）
	var submit_block := ""
	if over:
		submit_block = "本局已结束"
	elif Game.ap_left() <= 0:
		submit_block = Economy.REASON_AP
	elif Game.submissions_left_this_week() <= 0:
		submit_block = "本周 %d 次投递已经用完，等周末翻篇" % GameState.MAX_SUBMIT_PER_WEEK
	_set_card("submit", submit_block.is_empty(), submit_block,
			"本周还剩 %d 次" % Game.submissions_left_this_week())

	_set_card("work", Economy.can_work(Game.state), Economy.work_block_reason(Game.state),
			"点一下 +%d 元，本周还剩 %d 次" % [
				Economy.work_income(), Economy.work_left_this_week(Game.state)])
	_set_card("class", Economy.can_take_class(Game.state), Economy.class_block_reason(Game.state),
			"点一下 -%d 元，演技 +%d" % [Economy.class_fee(), Economy.class_gain()])

	_set_card("end", true, "", "" if over else "进入第 %d 天" % mini(
			Game.day() + 1, GameState.TOTAL_DAYS))


# ============================================================
# 刷新：本周进度（第四格）
# ============================================================
func _refresh_week() -> void:
	# 【先 remove 再 free】`queue_free()` 要到帧末才真正删掉，只调它的话
	# 这一帧里旧行还挂在树上、和新行一起参与布局 —— 会看到行数闪一下变双份。
	for child in _week_list.get_children():
		_week_list.remove_child(child)
		child.queue_free()

	var st := Game.state
	var bal := BalanceLibrary.data()
	_week_row("投递", "%d / %d" % [st.submissions_this_week, GameState.MAX_SUBMIT_PER_WEEK], "部")
	_week_row("打工", "%d / %d" % [st.work_this_week, bal.work_max_per_week], "次")
	_week_row("上课", "%d / %d" % [st.class_this_week, bal.class_max_per_week], "次")
	_week_row("待播出", str(_pending_count()), "部")


## 本周已投出去、还没播出的作品数 —— 「行动已经花掉但结果还没到」是这段时间的体感
func _pending_count() -> int:
	var n := 0
	for h: Dictionary in WeekCycle.plays_of_week(Game.state, Game.week()):
		n += 1
	return n


# ============================================================
# 刷新：右栏补充信息
# ============================================================
func _refresh_info() -> void:
	# 同上：先摘下来，别让它在这一帧里和新行挤在一起
	for child in _info_list.get_children():
		_info_list.remove_child(child)
		child.queue_free()

	var st := Game.state
	var bal := BalanceLibrary.data()
	var due_day := WeekCycle.next_installment_day(st)
	if due_day > 0:
		_info_row("下一期截止", "第 %d 天 -%d 元" % [due_day, Economy.ps5_amount()])
	if st.money < 0:
		_info_row("欠债", "%d 元" % st.money, WARN_INK)
	_info_row("累计投递", "%d 次（成功 %d）" % [st.submissions_total, st.successes_total])
	_info_row("PS5 已付", "%d / %d 元" % [st.ps5_paid, bal.ps5_total], INK_SOFT)


# ============================================================
# 动作
# ============================================================
func _on_submit_pressed() -> void:
	# 投递入口在微信里（决策 1.4：Boss直聘 只读）。这张卡只是把玩家送过去，
	# **不在这里替玩家投** —— 投哪家、投哪个档位、用哪段表情包都得玩家自己决定。
	# 微信归**手机屏**管（改版后 App 都在那边），所以只发请求，由桌子切过去。
	open_app_requested.emit("res://scenes/apps/wechat.tscn")


func _on_work_pressed() -> void:
	var r := Game.work()
	_report_action_issue(r)
	_refresh_all()


func _on_class_pressed() -> void:
	var r := Game.take_class()
	_report_action_issue(r)
	_refresh_all()


func _on_end_day_pressed() -> void:
	if Game.state.finished:
		# 结局已经看过了就再给一次 —— 存档版周报里留着 ending 字段
		var reports: Array = Game.state.reports
		if not reports.is_empty():
			_open_report(reports[reports.size() - 1])
		return
	var res := Game.end_day()
	if res.get("settled", false):
		# 先刷新再开浮层 —— 否则浮层底下那行数字还停在结算前，
		# 而它只是被压暗、并没有隐藏，玩家一眼就能看出「上面写 225、下面写 200」
		_refresh_all()
		_open_report(res["report"])
	else:
		_refresh_all()
		# 试镜成功后按「下一天」：牌在推进时已经排好，这里直接翻。
		# 周末那一支不用管 —— 报纸先弹，关掉报纸时 `_close_report()` 会再问一次。
		_maybe_open_reward()


## 桌面点下去被核心层拒绝时，把原因显示出来。
## 【为什么这里还能被拒】按钮的可用状态是**同一套纯函数**算出来的，正常不会不一致；
## 这条路径是防"状态在两次刷新之间变了"（比如刚读完档），属于兜底而不是主逻辑。
func _report_action_issue(r: Dictionary) -> void:
	if r.get("ok", false) or not r.has("reason"):
		return
	_plan_hint.text = "没做成：" + String(r["reason"])


# ============================================================
# 结算界面
# ============================================================
func _open_report(report: Dictionary) -> void:
	if _report != null:
		return
	_report = load(REPORT_SCENE).instantiate()
	# 在 add_child 之前把数据放好 —— 这样 _ready() 里能直接用它建界面
	_report.set("report", report)
	_report_layer.add_child(_report)
	_report_layer.visible = true
	if _report.has_signal("dismissed"):
		_report.connect("dismissed", _close_report)


func _close_report() -> void:
	if _report != null:
		if _report.has_signal("dismissed") and _report.is_connected("dismissed", _close_report):
			_report.disconnect("dismissed", _close_report)
		_report.queue_free()
		_report = null
	_report_layer.visible = false
	_refresh_all()
	# 周末这一支：报纸是在「下一天」里先弹的，牌早就排好了，等报纸翻完再让玩家翻
	_maybe_open_reward()


# ============================================================
# 翻牌奖励（周结算的第二步）
# ============================================================
## 有牌就开一张。**一次只开一张**：连着拿到两三个档位时，
## 玩家收下一张之后由 `_on_reward_finished` 再问一次 —— 而不是一屏摆三张。
func _maybe_open_reward() -> void:
	if _reward != null or _report != null:
		return
	if not Game.has_pending_flip():
		return
	_reward = load(REWARD_SCENE).instantiate()
	# 【先连信号再 add_child】场景的 `_ready()` 里可能马上翻完（没有牌时它会立刻发
	# `finished`）；连晚了就会漏掉那一次，浮层留在屏幕上关不掉。
	_reward.connect("finished", _on_reward_finished)
	_report_layer.add_child(_reward)
	_report_layer.visible = true


func _on_reward_finished() -> void:
	if _reward == null:
		return
	# 【先摘引用再 queue_free】`finished` 是从它自己的「收下」按钮回调里发出来的，
	# 此刻还在它的调用栈上 —— 立即 free 会把栈拆掉
	var node := _reward
	_reward = null
	node.queue_free()
	_report_layer.visible = false
	_refresh_all()
	# 一周里可能连拿两三个档位：这张收下了就接着问下一张
	_maybe_open_reward()


func _close_reward() -> void:
	if _reward == null:
		return
	_reward.queue_free()
	_reward = null
	_report_layer.visible = false


# ============================================================
# 重开一局（两步确认）
# ============================================================
## 【为什么要两步】一局是二十一天，而这个按钮就贴在状态面板底部 —— 误触一下进度全没。
## 第一次按只是**进入待确认**，按钮文字会变；窗口过期或被刷新打断就自动退出待确认。
func _on_restart_pressed() -> void:
	var now := Time.get_ticks_msec()
	if not _is_restart_armed(now):
		_restart_armed_at = now
		_refresh_restart()
		return
	_restart_armed_at = 0
	# 【new_game() 本身不写存档】它只重置状态（测试也要能干净地调它）。
	# 「重开」这个动作**必须**把旧存档盖掉，否则玩家下次打开游戏会被读回上一局 ——
	# 那会让人以为"重开没生效"。
	Game.new_game()
	EventBus.save_requested.emit()
	_refresh_all()


func _is_restart_armed(now: int) -> bool:
	return _restart_armed_at > 0 and now - _restart_armed_at <= RESTART_CONFIRM_MS


func _refresh_restart() -> void:
	# 过期就在这儿顺手退掉 —— `_refresh_all()` 会被很多事件触发，
	# 于是按钮文字不需要额外的定时器也能自己回到常态
	if _restart_armed_at > 0 and not _is_restart_armed(Time.get_ticks_msec()):
		_restart_armed_at = 0
	var armed := _restart_armed_at > 0
	_restart_button.text = "确定要重开？再点一次" if armed else "重开一局"
	_restart_button.add_theme_color_override("font_color",
			WARN_INK if armed else INK_FAINT)
	_restart_button.add_theme_color_override("font_hover_color", WARN_INK)
	_restart_button.add_theme_color_override("font_pressed_color", WARN_INK)


# ============================================================
# 刷新与信号
# ============================================================
func _refresh_all() -> void:
	_refresh_status()
	_refresh_plan()
	_refresh_week()
	_refresh_info()
	_refresh_restart()


func _on_ap_changed(_left: int) -> void:
	_refresh_all()


## 状态被整个换掉（开新局 / 读档）
func _on_state_reset() -> void:
	# 状态整个换了：上一局的牌 / 报纸都不该留着。关掉之后
	# `_close_report()` 会按**新**状态再问一次有没有牌要翻（读档读到一半的局面）
	_close_reward()
	_close_report()
	_refresh_all()
