extends Control
## 微博 App —— 《有瓜有戏》往期电子报
##
## 【为什么它是只读的】微博在这个游戏里**不是社交工具**，是「你的表演被观众看到了什么」。
## 玩家在这里没有能点的动作，只有能读的结果 —— 这正是设计要的：
## 判定公式是隐藏的，唯一的学习通道就是读报纸的语气，然后自己反推。
##
## 【数据从哪来】`GameState.reports` —— 每周结算时由 `WeekCycle.settle()` 存进去。
## 界面**不重算**任何东西；重算就会出现「报纸上写 A、存档里记 B」。
##
## 运行：godot --path <项目> res://scenes/apps/weibo.tscn

const P_TOP := "Page/TopBar/TopMargin/TopRow"
const P_BODY := "Page/BodyWrap/Body"

signal cancelled

@onready var _status_label: Label = get_node(P_TOP + "/TopRight/StatusLabel")
@onready var _pending_label: Label = get_node(P_TOP + "/TopRight/PendingLabel")
@onready var _feed: VBoxContainer = get_node(P_BODY + "/FeedScroll/Feed")
@onready var _feed_hint: Label = get_node(P_BODY + "/FeedHint")
@onready var _feed_caption: Label = get_node(P_BODY + "/FeedCaption")
@onready var _back_button: Button = get_node("Page/BackButton")


func _ready() -> void:
	_apply_styles()
	_back_button.pressed.connect(func() -> void: cancelled.emit())
	EventBus.state_reset.connect(_refresh_all)
	_refresh_all()


## 让调用方把本页当 App 打开时显示「返回桌面」（见 phone_screen.gd）
func enable_back() -> void:
	_back_button.visible = true


# ============================================================
func _refresh_all() -> void:
	_status_label.text = "第 %d 天 / %d ｜ 第 %d 周" % [
		Game.day(), GameState.TOTAL_DAYS, Game.week()]
	var pending := _pending_count()
	_pending_label.text = "本周 %d 部还没播 —— 周末见" % pending if pending > 0 else "本周还没投过"
	_rebuild_feed()


func _pending_count() -> int:
	return WeekCycle.plays_of_week(Game.state, Game.week()).size()


func _rebuild_feed() -> void:
	for child in _feed.get_children():
		child.queue_free()

	var reports: Array = Game.state.reports
	_feed_caption.text = "往期（%d 期）" % reports.size()
	if reports.is_empty():
		_feed_hint.text = "还没有出过报。投出去的第一部戏会在本周结算时播出 —— 那时候才有第一期。"
		return
	_feed_hint.text = "点不了任何东西 —— 这里只是让你看看观众都说了什么。"

	# 【倒序】最新一期在最上面。读报的人关心的是"上周怎么样"，不是"第一周怎么样"
	for i in range(reports.size() - 1, -1, -1):
		_feed.add_child(_issue_card(reports[i]))


func _issue_card(report: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
			UiPalette.panel(UiPalette.PANEL, 18, 2, UiPalette.LINE))

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var week := int(report.get("week", 1))
	var head := HBoxContainer.new()
	box.add_child(head)

	var title := Label.new()
	title.text = "《有瓜有戏》第 %d 期" % week
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiPalette.text(title, 26, UiPalette.TEXT)
	head.add_child(title)

	var day := Label.new()
	day.text = "第 %d 天" % int(report.get("day", 0))
	UiPalette.text(day, 17, UiPalette.TEXT_DIM)
	head.add_child(day)

	var heads: Array = report.get("headlines", [])
	if heads.is_empty():
		var none := Label.new()
		none.text = "这一期没有你的戏。"
		UiPalette.text(none, 18, UiPalette.TEXT_DISABLED)
		box.add_child(none)
	else:
		for h: Variant in heads:
			var l := Label.new()
			l.text = String(h)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			UiPalette.text(l, 22, UiPalette.TEXT)
			box.add_child(l)

	# 一行小字交代这周播了几部、进账多少 —— 报纸本身不写这些，但玩家想知道
	var plays: Array = report.get("plays", [])
	var sum := Label.new()
	sum.text = "播出 %d 部 ｜ 片酬 +%d 元 ｜ 租金 −%d 元" % [
		plays.size(), int(report.get("payout", 0)), int(report.get("rent", 0))]
	UiPalette.text(sum, 15, UiPalette.TEXT_DIM)
	box.add_child(sum)

	return panel


# ============================================================
func _apply_styles() -> void:
	get_node("Bg").color = UiPalette.BG

	var bar := StyleBoxFlat.new()
	bar.bg_color = UiPalette.PANEL
	bar.border_width_bottom = 3
	bar.border_color = UiPalette.WEIBO
	get_node("Page/TopBar").add_theme_stylebox_override("panel", bar)

	var chip := StyleBoxFlat.new()
	chip.bg_color = UiPalette.WEIBO
	chip.set_corner_radius_all(12)
	get_node(P_TOP + "/BrandRow/BrandChip").add_theme_stylebox_override("panel", chip)

	UiPalette.text(get_node(P_TOP + "/BrandRow/BrandText"), 26, UiPalette.WEIBO)
	UiPalette.text(get_node(P_TOP + "/TopCenter/Title"), 40, UiPalette.TEXT)
	UiPalette.text(get_node(P_TOP + "/TopCenter/Subtitle"), 15, UiPalette.TEXT_DIM)
	UiPalette.text(_status_label, 20, UiPalette.ACCENT)
	UiPalette.text(_pending_label, 15, UiPalette.TEXT_DIM)
	UiPalette.text(_feed_caption, 22, UiPalette.TEXT)
	UiPalette.text(_feed_hint, 15, UiPalette.TEXT_DIM)

	_back_button.focus_mode = Control.FOCUS_NONE
	_back_button.add_theme_font_size_override("font_size", 20)
	_back_button.add_theme_color_override("font_color", UiPalette.TEXT)
	_back_button.add_theme_color_override("font_hover_color", UiPalette.TEXT)
	_back_button.add_theme_color_override("font_pressed_color", UiPalette.TEXT)
	_back_button.add_theme_stylebox_override("normal",
			UiPalette.button(UiPalette.PANEL_SOFT, UiPalette.LINE, 2, 14))
	_back_button.add_theme_stylebox_override("hover",
			UiPalette.button(UiPalette.PANEL_SOFT.lightened(0.08), UiPalette.ACCENT, 3, 14))
	_back_button.add_theme_stylebox_override("pressed",
			UiPalette.button(UiPalette.PANEL_SOFT.darkened(0.1), UiPalette.ACCENT, 3, 14))

	var scroll := get_node(P_BODY + "/FeedScroll") as ScrollContainer
	var sb := scroll.get_v_scroll_bar()
	sb.custom_minimum_size = Vector2(10, 0)
	sb.add_theme_stylebox_override("scroll",
			UiPalette.button(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0, 0))
	sb.add_theme_stylebox_override("grabber", UiPalette.rounded(UiPalette.LINE, 5))
	sb.add_theme_stylebox_override("grabber_highlight", UiPalette.rounded(UiPalette.WEIBO, 5))
