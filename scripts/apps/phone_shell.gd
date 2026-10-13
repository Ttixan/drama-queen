extends Control
## 手机壳 —— 玩家真正拿在手上的那台手机
##
## 【它的职责】桌面 + 状态栏 + 4 个 App 入口。**它自己不含任何玩法逻辑**：
## 打工、上课、结束今天全是在调 `Game` 上的方法，App 也只是被打开的子场景。
## 这条边界要守住 —— 一旦把「打工 +30 元」写进这里，数值模拟器就白做了。
##
## 【为什么「今日安排」放在桌面，而不是做成第 5 个 App】
## 数值表定义了打工 30 元/次、表演课 100 元/次，但 GDD 里根本没写玩家在哪儿点它们。
## 放桌面有三个好处：
##   1. 一天只有 1 点行动点，桌面一眼就能看清「今天还剩什么能做」
##   2. 门槛原因**直接写在卡片上**（没钱 / 次数用完 / 没行动点），不必进二级页面才知道
##   3. 4 个 App 的职责保持 GDD 原样，不用为两个动作再造一个 App

const PLAN_MARGIN := "Page/BodyWrap/Body/PlanPanel/PlanMargin/PlanBox"
const INFO_MARGIN := "Page/BodyWrap/Body/InfoPanel/InfoMargin/InfoBox"
const P_STATUS := "Page/StatusBar/StatusMargin/StatusRow"
const P_DOCK := "Page/Dock/DockMargin/DockRow"

const REPORT_SCENE := "res://scenes/main/week_report.tscn"

## 【为什么 App 表写死在代码里】它是**导航结构**（有哪几个 App 是玩法定义，不是数值），
## 与 `scripts/data/` 里那些"策划要改"的资源不是一类东西。配色沿用 UiPalette 的语义色。
## mark 是图标里的那个字。**必须显式写死**：按名字取首字会让「微信」和「微博」
## 都显示「微」，两个图标长得一模一样。
const APPS := [
	{"name": "Boss直聘", "mark": "聘", "scene": "res://scenes/apps/boss.tscn",
		"color": UiPalette.BOSS, "hint": "看公司 · 解锁 HR"},
	{"name": "录像机", "mark": "录", "scene": "res://scenes/minigame/recorder.tscn",
		"color": UiPalette.ACCENT, "hint": "拼 3 帧表情包"},
	{"name": "微信", "mark": "信", "scene": "res://scenes/apps/wechat.tscn",
		"color": UiPalette.WECHAT, "hint": "私聊 HR 就是投递"},
	{"name": "微博", "mark": "博", "scene": "res://scenes/apps/weibo.tscn",
		"color": UiPalette.WEIBO, "hint": "《有瓜有戏》往期"},
]

@onready var _left_box: HBoxContainer = get_node(P_STATUS + "/LeftBox")
@onready var _right_box: HBoxContainer = get_node(P_STATUS + "/RightBox")
@onready var _plan_list: VBoxContainer = get_node(PLAN_MARGIN + "/PlanList")
@onready var _plan_hint: Label = get_node(PLAN_MARGIN + "/PlanHint")
@onready var _info_list: VBoxContainer = get_node(INFO_MARGIN + "/InfoList")
@onready var _dock_icons: HBoxContainer = get_node(P_DOCK + "/DockIcons")
@onready var _dock_hint: Label = get_node(P_DOCK + "/DockHint")
@onready var _restart_button: Button = get_node(INFO_MARGIN + "/RestartButton")
@onready var _app_layer: Control = get_node("AppLayer")
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

## 动作卡：key -> {button, title, detail, state}
var _cards: Dictionary = {}
## 当前打开的 App（同一时刻只允许一个）
var _app: Node
var _report: Node
## 重开按钮的待确认时间戳（毫秒）。0 = 不在待确认状态
var _restart_armed_at := 0


func _ready() -> void:
	_apply_styles()
	_build_status()
	_build_plan()
	_build_dock()

	EventBus.state_reset.connect(_on_state_reset)
	EventBus.ap_changed.connect(_on_ap_changed)
	_refresh_all()


# ============================================================
# 状态栏
# ============================================================
func _build_status() -> void:
	_day_label = _chip(_left_box, 24, UiPalette.TEXT)
	_ap_label = _chip(_left_box, 22, UiPalette.POSITIVE)
	_money_label = _chip(_right_box, 24, UiPalette.ACCENT)
	_acting_label = _chip(_right_box, 20, UiPalette.TEXT)
	_fame_label = _chip(_right_box, 20, UiPalette.TEXT)
	_rep_label = _chip(_right_box, 20, UiPalette.TEXT)
	_ps5_label = _chip(_right_box, 20, UiPalette.TEXT)


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
# 底部 App 栏
# ============================================================
func _build_dock() -> void:
	for app: Dictionary in APPS:
		_dock_icons.add_child(_make_dock_icon(app))


func _make_dock_icon(app: Dictionary) -> Button:
	var b := Button.new()
	b.name = "App_" + String(app["name"])
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 100)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	b.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 12)
	margin.add_child(hbox)

	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(52, 52)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", UiPalette.rounded(app["color"], 12))
	hbox.add_child(chip)

	var initial := Label.new()
	initial.set_anchors_preset(Control.PRESET_FULL_RECT)
	initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	initial.text = String(app["mark"])
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiPalette.text(initial, 24, UiPalette.INK)
	chip.add_child(initial)

	var text_box := VBoxContainer.new()
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_box.add_theme_constant_override("separation", 2)
	hbox.add_child(text_box)

	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = String(app["name"])
	UiPalette.text(name_label, 20, UiPalette.TEXT)
	text_box.add_child(name_label)

	var hint := Label.new()
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.text = String(app["hint"])
	UiPalette.text(hint, 14, UiPalette.TEXT_DIM)
	text_box.add_child(hint)

	b.add_theme_stylebox_override("normal",
			UiPalette.button(UiPalette.PANEL, UiPalette.LINE, 2, 16, 0, 12))
	b.add_theme_stylebox_override("hover",
			UiPalette.button(Color("2d2d36"), app["color"], 2, 16, 0, 12))
	b.add_theme_stylebox_override("pressed",
			UiPalette.button(app["color"], app["color"], 2, 16, 4, 12))
	b.add_theme_stylebox_override("disabled",
			UiPalette.button(Color("1c1c22"), UiPalette.LINE, 1, 16, 0, 12))

	b.pressed.connect(_on_open_app.bind(String(app["scene"])))
	return b


func _refresh_dock() -> void:
	var blocked := _app != null or _report != null
	for child in _dock_icons.get_children():
		(child as Button).disabled = blocked
	_dock_hint.text = "先关掉手上的页面" if blocked else "点图标打开 App"


# ============================================================
# 动作
# ============================================================
func _on_submit_pressed() -> void:
	# 投递入口在微信里（决策 1.4：Boss直聘 只读）。桌面这张卡只是把玩家送过去，
	# **不在这里替玩家投** —— 投哪家、投哪个档位、用哪段表情包都得玩家自己决定。
	_on_open_app("res://scenes/apps/wechat.tscn")


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
# App 与结算界面
# ============================================================
func _on_open_app(scene_path: String) -> void:
	if _app != null or _report != null:
		return
	_app = load(scene_path).instantiate()
	_app_layer.add_child(_app)
	_app_layer.visible = true
	# 子页面自己决定要不要显示「返回」按钮；这里只是把它打开
	if _app.has_method("enable_back"):
		_app.enable_back()
	if _app.has_signal("cancelled"):
		_app.connect("cancelled", _close_app)
	_refresh_dock()


func _close_app() -> void:
	if _app != null:
		if _app.has_signal("cancelled") and _app.is_connected("cancelled", _close_app):
			_app.disconnect("cancelled", _close_app)
		_app.queue_free()
		_app = null
	_app_layer.visible = false
	# 回来时状态大概率变了（投递花掉行动点、解锁了新 HR），整体重画一遍
	_refresh_all()


func _open_report(report: Dictionary) -> void:
	if _report != null or _app != null:
		return
	_report = load(REPORT_SCENE).instantiate()
	# 在 add_child 之前把数据放好 —— 这样 _ready() 里能直接用它建界面
	_report.set("report", report)
	_report_layer.add_child(_report)
	_report_layer.visible = true
	if _report.has_signal("dismissed"):
		_report.connect("dismissed", _close_report)
	_refresh_dock()


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
	_refresh_dock()
	_refresh_restart()


func _on_ap_changed(_left: int) -> void:
	_refresh_all()


## 状态被整个换掉（开新局 / 读档）
func _on_state_reset() -> void:
	_close_app()
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

	var dock := StyleBoxFlat.new()
	dock.bg_color = UiPalette.PANEL
	dock.border_width_top = 3
	dock.border_color = UiPalette.LINE
	get_node("Page/Dock").add_theme_stylebox_override("panel", dock)

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
	UiPalette.text(_dock_hint, 15, UiPalette.TEXT_DISABLED)


func _style_panel(node: Node, bg: Color, radius: int, border: int) -> void:
	node.add_theme_stylebox_override("panel", UiPalette.panel(bg, radius, border, UiPalette.LINE))
