extends Control
## 日历 —— 桌上那本台历，也就是「你的日程与进度」
##
## 【它的职责】状态栏 + 今日安排 + 本周进度，**外加周末结算浮层与重开一局**。
## 原来这些都在手机壳里（手机屏的「上半部分」），改版后搬到这儿：
## 桌子上的台历本来就是「今天该做什么」，4 个 App 才归手机。
## **它自己不含任何玩法逻辑**：打工、上课、结束今天全是在调 `Game` 上的方法。
## 这条边界要守住 —— 一旦把「打工 +30 元」写进这里，数值模拟器就白做了。
##
## 【为什么「今日安排」值得单独一屏】
## 数值表定义了打工 30 元/次、表演课 100 元/次，但 GDD 里根本没写玩家在哪儿点它们。
## 放这一屏有三个好处：
##   1. 一天只有 1 点行动点，一眼就能看清「今天还剩什么能做」
##   2. 门槛原因**直接写在卡片上**（没钱 / 次数用完 / 没行动点），不必进二级页面才知道
##   3. 4 个 App 的职责保持 GDD 原样，不用为两个动作再造一个 App
##
## 【返回桌面】桌子（`desk_screen.tscn`）把本场景当子页面打开，
## 所以要有回去的路：与录像机 / 微信 / Boss直聘 被嵌进手机时用的是同一套约定 ——
## `cancelled` 信号 + `enable_back()`，由调用方决定要不要露出「返回桌面」。

## 上层（桌子）把本场景当子页面打开时，玩家要回去就发这条
signal cancelled
## 「去投递」那张卡要把玩家送到手机屏的微信里 —— 但微信不归本屏管（它归手机屏），
## 所以只发请求，由桌子决定怎么切过去。
signal open_app_requested(scene_path: String)

const PLAN_MARGIN := "Page/BodyWrap/Body/PlanPanel/PlanMargin/PlanBox"
const INFO_MARGIN := "Page/BodyWrap/Body/InfoPanel/InfoMargin/InfoBox"
const P_STATUS := "Page/StatusBar/StatusMargin/StatusRow"

const REPORT_SCENE := "res://scenes/main/week_report.tscn"

@onready var _left_box: HBoxContainer = get_node(P_STATUS + "/LeftBox")
@onready var _right_box: HBoxContainer = get_node(P_STATUS + "/RightBox")
@onready var _plan_list: VBoxContainer = get_node(PLAN_MARGIN + "/PlanList")
@onready var _plan_hint: Label = get_node(PLAN_MARGIN + "/PlanHint")
@onready var _info_list: VBoxContainer = get_node(INFO_MARGIN + "/InfoList")
@onready var _restart_button: Button = get_node(INFO_MARGIN + "/RestartButton")
@onready var _report_layer: Control = get_node("ReportLayer")

## 「重开一局」的二次确认窗口。**为什么需要它**：
## 一局是三周、二十一天，误触一下就把进度全清了 —— 而这个按钮就贴在信息面板底部。
## 用时间戳而不是 `await`，是因为它必须能被"任何一次重新刷新"打断（见 _refresh_restart）。
const RESTART_CONFIRM_MS := 5000

var _day_label: Label
var _ap_label: Label
var _money_label: Label
var _acting_label: Label
var _fame_label: Label
var _rep_label: Label
var _ps5_label: Label
## 「返回桌面」—— 只有被桌子当子页面打开时才露出来（见 enable_back）
var _back_button: Button
var _back_enabled := false

## 动作卡：key -> {button, title, detail, state}
var _cards: Dictionary = {}
var _report: Node
## 重开按钮的待确认时间戳（毫秒）。0 = 不在待确认状态
var _restart_armed_at := 0


func _ready() -> void:
	_apply_styles()
	_build_status()
	_build_plan()

	EventBus.state_reset.connect(_on_state_reset)
	EventBus.ap_changed.connect(_on_ap_changed)
	_refresh_all()


# ============================================================
# 状态栏
# ============================================================
func _build_status() -> void:
	# 返回桌面排在最前 —— 独立运行时它一直藏着（那时手机壳就是最外层，没地方可回）
	_back_button = Button.new()
	_back_button.text = "← 桌面"
	_back_button.focus_mode = Control.FOCUS_NONE
	_back_button.visible = false
	_back_button.pressed.connect(func() -> void: cancelled.emit())
	_left_box.add_child(_back_button)
	UiPalette.text(_back_button, 20, UiPalette.TEXT)
	_back_button.add_theme_stylebox_override("normal",
			UiPalette.button(UiPalette.PANEL_SOFT, UiPalette.LINE, 2, 12, 0, 12))
	_back_button.add_theme_stylebox_override("hover",
			UiPalette.button(UiPalette.PANEL_SOFT.lightened(0.1), UiPalette.ACCENT, 3, 12, 0, 12))
	_back_button.add_theme_stylebox_override("pressed",
			UiPalette.button(UiPalette.PANEL_SOFT, UiPalette.ACCENT, 3, 12, 0, 12))

	_day_label = _chip(_left_box, 24, UiPalette.TEXT)
	_ap_label = _chip(_left_box, 22, UiPalette.POSITIVE)
	_money_label = _chip(_right_box, 24, UiPalette.ACCENT)
	_acting_label = _chip(_right_box, 20, UiPalette.TEXT)
	_fame_label = _chip(_right_box, 20, UiPalette.TEXT)
	_rep_label = _chip(_right_box, 20, UiPalette.TEXT)
	_ps5_label = _chip(_right_box, 20, UiPalette.TEXT)


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
	# （App 归手机屏管 —— 见 `phone_screen.gd`，那边自己有一份同样的判断）
	if _report != null:
		return
	get_viewport().set_input_as_handled()
	cancelled.emit()


func _chip(parent: Node, size: int, color: Color) -> Label:
	var l := Label.new()
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiPalette.text(l, size, color)
	parent.add_child(l)
	return l


func _refresh_status() -> void:
	_day_label.text = "第 %d 天 / %d ｜ 第 %d 周" % [
		Game.day(), GameState.TOTAL_DAYS, Game.week()]
	_ap_label.text = "行动点 %d" % Game.ap_left()
	_ap_label.add_theme_color_override("font_color",
			UiPalette.POSITIVE if Game.ap_left() > 0 else UiPalette.TEXT_DISABLED)

	_money_label.text = "%d 元" % Game.money()
	# 【欠债要显眼】金钱可以为负，这件事在界面上必须一眼看出来，
	# 否则玩家只会觉得"数字变红了"，不知道那是「被解雇」结局的一半条件。
	_money_label.add_theme_color_override("font_color",
			UiPalette.DANGER if Game.money() < 0 else UiPalette.ACCENT)
	_acting_label.text = "演技 %d" % Game.acting()
	_fame_label.text = "知名度 %d" % Game.fame()
	_rep_label.text = "风评 %+d" % Game.reputation()
	_rep_label.add_theme_color_override("font_color",
			UiPalette.DANGER if Game.reputation() < 0 else UiPalette.TEXT)

	var paid := Economy.ps5_installments_paid(Game.state)
	var total_rounds := BalanceLibrary.data().ps5_installments
	_ps5_label.text = "PS5 %d / %d 期" % [paid, total_rounds]
	_ps5_label.add_theme_color_override("font_color",
			UiPalette.POSITIVE if Game.ps5_paid_off() else UiPalette.TEXT_DIM)


# ============================================================
# 今日安排（4 张动作卡）
# ============================================================
func _build_plan() -> void:
	_cards["submit"] = _make_card("投递试镜", "去微信挑一个 HR，把表情包发过去（占 1 点行动点）")
	_cards["work"] = _make_card("去打工", "+%d 元 · 每周最多 %d 次" % [
			Economy.work_income(), BalanceLibrary.data().work_max_per_week])
	_cards["class"] = _make_card("上表演课", "−%d 元 → 演技 +%d · 每周最多 %d 次" % [
			Economy.class_fee(), Economy.class_gain(), BalanceLibrary.data().class_max_per_week])
	_cards["end"] = _make_card("结束今天", "用掉剩下的时间，进入第 %d 天" % mini(Game.day() + 1, GameState.TOTAL_DAYS))

	(_cards["submit"]["button"] as Button).pressed.connect(_on_submit_pressed)
	(_cards["work"]["button"] as Button).pressed.connect(_on_work_pressed)
	(_cards["class"]["button"] as Button).pressed.connect(_on_class_pressed)
	(_cards["end"]["button"] as Button).pressed.connect(_on_end_day_pressed)


func _make_card(title: String, detail: String) -> Dictionary:
	var b := Button.new()
	b.name = "Card_" + title
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 132)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 【必须显式 EXPAND】容器只把剩余空间分给带 SIZE_EXPAND 的子节点，
	# 少了这一行卡片会缩成内容宽度（录像机的部件卡踩过同一个坑）
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 内容全部 MOUSE_FILTER_IGNORE —— 点击必须透给按钮本身，否则 hover / pressed 失灵
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	b.add_child(margin)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)

	var title_label := Label.new()
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.text = title
	UiPalette.text(title_label, 24, UiPalette.TEXT)
	box.add_child(title_label)

	var detail_label := Label.new()
	detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_label.text = detail
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.text(detail_label, 15, UiPalette.TEXT_DIM)
	box.add_child(detail_label)

	var state_label := Label.new()
	state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.text(state_label, 15, UiPalette.POSITIVE)
	box.add_child(state_label)

	_plan_list.add_child(b)
	_style_card(b)
	return {"button": b, "title": title_label, "detail": detail_label, "state": state_label}


func _style_card(b: Button) -> void:
	b.add_theme_stylebox_override("normal",
			UiPalette.button(UiPalette.PANEL_SOFT, UiPalette.LINE, 2, 16, 0, 16))
	b.add_theme_stylebox_override("hover",
			UiPalette.button(Color("35353f"), UiPalette.ACCENT, 2, 16, 0, 16))
	b.add_theme_stylebox_override("pressed",
			UiPalette.button(UiPalette.ACCENT, UiPalette.ACCENT, 2, 16, 4, 16))
	b.add_theme_stylebox_override("disabled",
			UiPalette.button(Color("1c1c22"), UiPalette.LINE, 1, 16, 0, 16))


## 一张卡的可用状态：能点就写清"点下去会发生什么"，不能点就写清"为什么"
func _set_card(key: String, enabled: bool, reason: String, ok_text: String) -> void:
	var card: Dictionary = _cards[key]
	var b: Button = card["button"]
	b.disabled = not enabled
	var sp: Label = card["state"]
	if enabled:
		sp.text = ok_text
		sp.add_theme_color_override("font_color", UiPalette.POSITIVE)
	else:
		sp.text = reason
		sp.add_theme_color_override("font_color", UiPalette.ACCENT)
	(card["title"] as Label).add_theme_color_override("font_color",
			UiPalette.TEXT if enabled else UiPalette.TEXT_DISABLED)
	(card["detail"] as Label).add_theme_color_override("font_color",
			UiPalette.TEXT_DIM if enabled else UiPalette.TEXT_DISABLED)


func _refresh_plan() -> void:
	var over := Game.state.finished
	# 【标题也要跟着换】结束后这张卡不再是「结束今天」——
	# 留着原来的字会让玩家以为还能再过一天，点下去却直接跳出结局。
	(_cards["end"]["title"] as Label).text = "看结局" if over else "结束今天"
	if not over:
		_plan_hint.text = "一天只能做一件事。行动点用完，剩下的时间就是发呆。"
		# 这一行随天数变，建卡时那份会过期
		(_cards["end"]["detail"] as Label).text = "用掉剩下的时间，进入第 %d 天" % (
				mini(Game.day() + 1, GameState.TOTAL_DAYS))
	else:
		_plan_hint.text = "三周结束了 —— 点下面看你这三周的下场。"
		(_cards["end"]["detail"] as Label).text = "这一局已经结束，结局存在最近一期周报里"

	# 投递：真正能不能发，微信里还会再判一次（那里才知道有没有表情包、投哪家）
	var submit_block := ""
	if over:
		submit_block = "本局已结束"
	elif Game.ap_left() <= 0:
		submit_block = Economy.REASON_AP
	elif Game.submissions_left_this_week() <= 0:
		submit_block = "本周 %d 次投递已经用完 —— 等周末翻篇" % GameState.MAX_SUBMIT_PER_WEEK
	_set_card("submit", submit_block.is_empty(), submit_block,
			"本周还剩 %d 次 ｜ 点开微信挑 HR" % Game.submissions_left_this_week())

	_set_card("work", Economy.can_work(Game.state), Economy.work_block_reason(Game.state),
			"点一下 +%d 元，本周还剩 %d 次" % [
				Economy.work_income(), Economy.work_left_this_week(Game.state)])
	_set_card("class", Economy.can_take_class(Game.state), Economy.class_block_reason(Game.state),
			"点一下 −%d 元，演技 +%d" % [Economy.class_fee(), Economy.class_gain()])

	if over:
		_set_card("end", true, "", "看结局")
	else:
		_set_card("end", true, "", "第 %d 天 → 第 %d 天" % [
				Game.day(), mini(Game.day() + 1, GameState.TOTAL_DAYS)])


# ============================================================
# 右侧：这一周
# ============================================================
func _refresh_info() -> void:
	for child in _info_list.get_children():
		child.queue_free()

	var st := Game.state
	var bal := BalanceLibrary.data()
	_row("本周投递", "%d / %d 部" % [st.submissions_this_week, GameState.MAX_SUBMIT_PER_WEEK],
			"周末统一播出 —— 投递瞬间只出通过 / 失败")
	_row("打工", "%d / %d 次" % [st.work_this_week, bal.work_max_per_week], "")
	_row("表演课", "%d / %d 次" % [st.class_this_week, bal.class_max_per_week], "")

	var paid := Economy.ps5_installments_paid(st)
	_row("PS5 分期", "%d / %d 期（%d / %d 元）" % [paid, bal.ps5_installments, st.ps5_paid, bal.ps5_total],
			"凑齐才算活明白")
	var due_day := WeekCycle.next_installment_day(st)
	if due_day > 0:
		_row("下一期截止", "第 %d 天 −%d 元" % [due_day, Economy.ps5_amount()],
				"付不出只扣风评，钱留着")
	if st.money < 0:
		_row("欠债", "%d 元" % st.money, "欠债 + 失败次数够多就是「被解雇」", UiPalette.DANGER)

	var pending := _pending_count()
	if pending > 0:
		_row("待播出", "%d 部" % pending, "周末的《有瓜有戏》会一起报出来")

	_row("累计投递", "%d 次（成功 %d）" % [st.submissions_total, st.successes_total], "")


## 本周已投出去、还没播出的作品数 —— 「行动已经花掉但结果还没到」是这段时间的体感
func _pending_count() -> int:
	var n := 0
	for h: Dictionary in WeekCycle.plays_of_week(Game.state, Game.week()):
		n += 1
	return n


func _row(key: String, value: String, hint: String, value_color: Color = UiPalette.TEXT) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_info_list.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)

	var k := Label.new()
	k.text = key
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiPalette.text(k, 18, UiPalette.TEXT_DIM)
	head.add_child(k)

	var v := Label.new()
	v.text = value
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiPalette.text(v, 20, value_color)
	head.add_child(v)

	if not hint.is_empty():
		var h := Label.new()
		h.text = hint
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiPalette.text(h, 14, UiPalette.TEXT_DISABLED)
		box.add_child(h)


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
		# 先刷新再开浮层 —— 否则浮层底下那条状态栏还停在结算前的数字，
		# 而它只是被压暗、并没有隐藏，玩家一眼就能看出「上面写 225、下面写 200」
		_refresh_all()
		_open_report(res["report"])
	else:
		_refresh_all()


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


# ============================================================
# 重开一局（两步确认）
# ============================================================
## 【为什么要两步】一局是二十一天，而这个按钮就贴在面板底部 —— 误触一下进度全没。
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
			UiPalette.DANGER if armed else UiPalette.TEXT_DIM)
	_restart_button.add_theme_color_override("font_hover_color",
			UiPalette.DANGER if armed else UiPalette.TEXT)
	_restart_button.add_theme_color_override("font_pressed_color",
			UiPalette.DANGER if armed else UiPalette.TEXT)


# ============================================================
# 刷新与信号
# ============================================================
func _refresh_all() -> void:
	_refresh_status()
	_refresh_plan()
	_refresh_info()
	_refresh_restart()


func _on_ap_changed(_left: int) -> void:
	_refresh_all()


## 状态被整个换掉（开新局 / 读档）
func _on_state_reset() -> void:
	_close_report()
	_refresh_all()


# ============================================================
# 样式
# ============================================================
func _apply_styles() -> void:
	get_node("Bg").color = UiPalette.BG

	# 顶栏只留一条亮色下边线 —— 和录像机同一个手法
	var bar := StyleBoxFlat.new()
	bar.bg_color = UiPalette.PANEL
	bar.border_width_bottom = 3
	bar.border_color = UiPalette.ACCENT
	get_node("Page/StatusBar").add_theme_stylebox_override("panel", bar)

	_style_panel(get_node("Page/BodyWrap/Body/PlanPanel"), UiPalette.PANEL, 20, 2)
	_style_panel(get_node("Page/BodyWrap/Body/InfoPanel"), UiPalette.PANEL, 20, 2)

	# 重开按钮做得低调：它是"退路"，不该跟四张动作卡抢注意力
	_restart_button.focus_mode = Control.FOCUS_NONE
	_restart_button.add_theme_font_size_override("font_size", 17)
	_restart_button.add_theme_stylebox_override("normal",
			UiPalette.button(UiPalette.PANEL_SOFT, UiPalette.LINE, 1, 12))
	_restart_button.add_theme_stylebox_override("hover",
			UiPalette.button(UiPalette.PANEL_SOFT.lightened(0.08), UiPalette.DANGER, 2, 12))
	_restart_button.add_theme_stylebox_override("pressed",
			UiPalette.button(UiPalette.PANEL_SOFT.darkened(0.1), UiPalette.DANGER, 2, 12))
	_restart_button.pressed.connect(_on_restart_pressed)

	UiPalette.text(get_node(PLAN_MARGIN + "/PlanCaption"), 30, UiPalette.TEXT)
	UiPalette.text(_plan_hint, 15, UiPalette.TEXT_DIM)
	UiPalette.text(get_node(INFO_MARGIN + "/InfoCaption"), 30, UiPalette.TEXT)


func _style_panel(node: Node, bg: Color, radius: int, border: int) -> void:
	node.add_theme_stylebox_override("panel", UiPalette.panel(bg, radius, border, UiPalette.LINE))
