extends Control
## 周末结算 —— 《有瓜有戏》这一期 + 三周的账 + 结局
##
## 【为什么结局和结算在同一个界面】第 21 天的结算与结局是同一件事的两面：
## 看完这周的账，紧接着就是「那这三周下来我成了什么」。
## 拆成两个界面会让玩家连点两次「继续」，而第二次其实没什么可继续的。
##
## 【只读 report，不重算任何东西】所有数字都来自 `WeekCycle.settle()` 的返回值。
## 界面自己再算一遍的话，屏幕上显示的和存档里记的迟早会不一样 ——
## 而这种不一致最难查，因为它只在「某个界面忘记同步」时才出现。
##
## 【被当成浮层用时】它由手机壳实例化（`report` 在 add_child 之前设好），
## 点「翻篇」发 `dismissed` 让手机壳把自己清掉。

signal dismissed

## 由调用方在 add_child 之前赋值。**必须能在 _ready() 里读到**。
var report: Dictionary = {}

@onready var _title: Label = get_node("Center/Card/CardMargin/CardBox/Header/HeaderBox/ReportTitle")
@onready var _subtitle: Label = get_node("Center/Card/CardMargin/CardBox/Header/HeaderBox/ReportSubtitle")
@onready var _day_label: Label = get_node("Center/Card/CardMargin/CardBox/Header/DayLabel")
@onready var _content: VBoxContainer = get_node("Center/Card/CardMargin/CardBox/Scroll/Content")
@onready var _foot_hint: Label = get_node("Center/Card/CardMargin/CardBox/Footer/FootHint")
@onready var _next_button: Button = get_node("Center/Card/CardMargin/CardBox/Footer/NextButton")

## 已经翻到结局页了没有 —— 决定底部的按钮是「看结局」还是「翻篇」
var _on_ending := false


func _ready() -> void:
	_apply_styles()
	_next_button.pressed.connect(_on_next_pressed)
	_build_week()


# ============================================================
# 第一页：这一期的报纸与账
# ============================================================
func _build_week() -> void:
	_on_ending = false
	_clear()
	var week := int(report.get("week", 1))
	_title.text = "《有瓜有戏》第 %d 期" % week
	_subtitle.text = "本周播出的戏，都在这一版里"
	_day_label.text = "第 %d 天 · 第 %d 周结算" % [
		int(report.get("day", 0)), week]

	_build_headlines()
	_build_plays()
	_build_ledger()
	_build_deltas()

	var ending: Dictionary = report.get("ending", {})
	if ending.is_empty():
		var next_day := mini(int(report.get("day", 0)) + 1, GameState.TOTAL_DAYS)
		_foot_hint.text = "这一页翻过去就是第 %d 天。下一期报纸在第 %d 天。" % [
			next_day, mini(int(report.get("day", 0)) + GameState.DAYS_PER_WEEK, GameState.TOTAL_DAYS)]
		_next_button.text = "翻篇"
	else:
		_foot_hint.text = "三周结束了 —— 你这三周的下场，就在下一页。"
		_next_button.text = "看结局"


## 本期头条。**这一版报纸是这个游戏唯一的夸奖 / 批评出口** ——
## 判定公式是隐藏的，玩家只能从标题的语气里读出"这周我到底演得怎么样"。
func _build_headlines() -> void:
	var heads: Array = report.get("headlines", [])
	if heads.is_empty():
		_note("这一期没有你的戏。")
		return
	_section("头版")
	for h: Variant in heads:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		_content.add_child(row)

		var rule := ColorRect.new()
		rule.custom_minimum_size = Vector2(5, 0)
		rule.size_flags_vertical = Control.SIZE_EXPAND_FILL
		rule.color = UiPalette.ACCENT
		row.add_child(rule)

		var l := Label.new()
		l.text = String(h)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiPalette.text(l, 30, UiPalette.TEXT)
		row.add_child(l)


## 本周每一部戏的明细。玩家要能从这一行读出「我为什么拿了低分」。
func _build_plays() -> void:
	var plays: Array = report.get("plays", [])
	_section("本周播出 %d 部" % plays.size())
	if plays.is_empty():
		_note("这周没有成功投出去的作品 —— 没有戏，也就没有播出。")
		return
	for p: Dictionary in plays:
		_play_row(p)


func _play_row(p: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
			UiPalette.panel(UiPalette.PANEL_SOFT, 14, 2, UiPalette.LINE))
	_content.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)

	# 【剧名】与公司 / 档位来自履历；档位、片酬、各项增量来自播出结果
	var entry: Dictionary = p.get("entry", {})
	var code := String(entry.get("company_code", ""))
	var company := CompanyLibrary.by_code(code)
	var cast_name := String(RoleRequirement.TIER_NAMES.get(int(p.get("cast", 0)), "?"))
	var head := Label.new()
	head.text = "《%s》 ｜ %s · %s" % [
		String(entry.get("play_title", "剧名缺失")),
		company.display_name if company != null else code,
		cast_name]
	UiPalette.text(head, 22, UiPalette.TEXT)
	box.add_child(head)

	var grade := int(p.get("grade", BalanceData.Grade.LOW))
	var grade_label := "匹配 %.0f%% → %s" % [
		float(p.get("match_rate", 0.0)) * 100.0, BalanceData.grade_name(grade)]
	var deltas := "片酬 +%d · 演技 +%d · 知名度 %+d · 风评 %+d · 负面 %+d" % [
		int(p.get("payout", 0)), int(p.get("acting_gain", 0)),
		int(p.get("fame", 0)), int(p.get("rep", 0)), int(p.get("neg", 0))]
	var line := Label.new()
	line.text = grade_label + " ｜ " + deltas
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.text(line, 17, _grade_color(grade))
	box.add_child(line)

	# 「低分龙套没被注意到」这一格必须解释，否则玩家会以为漏结算了
	if bool(p.get("unnoticed", false)):
		_no_margin_note(box, "观众没注意到这个龙套 —— 低分但没人在骂你，一切照旧。")

	var headline := String(p.get("headline", ""))
	if not headline.is_empty():
		_no_margin_note(box, "头条：" + headline)


func _grade_color(grade: int) -> Color:
	match grade:
		BalanceData.Grade.HIGH:
			return UiPalette.POSITIVE
		BalanceData.Grade.NORMAL:
			return UiPalette.TEXT_DIM
	return UiPalette.DANGER


## 收支流水。**顺序和 `WeekCycle.settle()` 一致** —— 玩家看到的账要和结算顺序对得上，
## 否则「明明赚了钱却交不起房租」这种事没法直觉理解。
func _build_ledger() -> void:
	_section("这一周的账")
	var payout := int(report.get("payout", 0))
	_ledger_row("片酬", "+%d 元" % payout, UiPalette.POSITIVE if payout > 0 else UiPalette.TEXT_DIM)
	_ledger_row("房租", "−%d 元" % int(report.get("rent", 0)), UiPalette.DANGER)

	var paid := int(report.get("ps5_paid", 0))
	if paid > 0:
		_ledger_row("PS5 分期", "−%d 元" % paid, UiPalette.DANGER)
	elif bool(report.get("ps5_overdue", false)):
		# 【故意不扣钱】逾期只是"这笔没交出去"，扣钱又记逾期等于一罚两遍。
		var penalty := int(report.get("ps5_penalty", 0))
		_ledger_row("PS5 分期", "付不出，这一期没交", UiPalette.DANGER)
		if penalty > 0:
			_ledger_row("逾期惩罚", "风评 −%d" % penalty, UiPalette.DANGER)

	var after := _after_state()
	_ledger_row("期末金钱", "%d 元" % int(after.get("money", 0)),
			UiPalette.DANGER if int(after.get("money", 0)) < 0 else UiPalette.ACCENT)


func _build_deltas() -> void:
	var before: Dictionary = report.get("before", {})
	var after := _after_state()
	if before.is_empty():
		return
	_section("三周走到这里")
	_delta_row("演技", int(before.get("acting", 0)), int(after.get("acting", 0)))
	_delta_row("知名度", int(before.get("fame", 0)), int(after.get("fame", 0)))
	_delta_row("风评", int(before.get("reputation", 0)), int(after.get("reputation", 0)))
	# 负面曝光是隐藏属性（不上状态栏），但周报里要显示 ——
	# 它是「黑红」的唯一来源，不显示就等于让玩家看一个凭空出现的标题
	_delta_row("负面曝光（隐藏）", int(before.get("neg", 0)), int(after.get("neg", 0)))
	var paid := Game.ps5_paid()
	var total := Economy.ps5_total()
	_ledger_row("PS5 已凑", "%d / %d 元" % [paid, total],
			UiPalette.POSITIVE if Game.ps5_paid_off() else UiPalette.TEXT_DIM)


# ============================================================
# 第二页：结局
# ============================================================
func _build_ending() -> void:
	_on_ending = true
	_clear()
	var ending: Dictionary = report.get("ending", {})
	_title.text = "结局 ｜ " + String(ending.get("name", "?"))
	_subtitle.text = String(ending.get("condition", ""))
	_day_label.text = "第 %d 天" % GameState.TOTAL_DAYS

	var name_label := Label.new()
	name_label.text = String(ending.get("name", "?"))
	UiPalette.text(name_label, 64, UiPalette.ACCENT)
	_content.add_child(name_label)

	var text := Label.new()
	text.text = String(ending.get("text", ""))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.text(text, 26, UiPalette.TEXT)
	_content.add_child(text)

	# 【占位文案要让开发者和玩家都看得见】「先做 3 个结局」是文案的工作量，
	# 判定六条都生效了。不标出来的话，读到一段「【文案待补】」会以为是 bug。
	if not bool(ending.get("implemented", false)):
		_note("这个结局的判定已经生效，但文案还是占位 —— 狗牙补完之后这里会换成正文。")

	_section("这一局的账")
	_ledger_row("累计投递", "%d 次（成功 %d）" % [
			Game.state.submissions_total, Game.state.successes_total], UiPalette.TEXT)
	_ledger_row("龙套档成功", "%d 次" % Game.state.count_success_by_tier(RoleRequirement.Tier.EXTRA),
			UiPalette.TEXT)
	_ledger_row("演过的烂片", "%d 部" % Game.state.count_bad_plays(),
			UiPalette.TEXT)
	_ledger_row("期末金钱", "%d 元" % Game.money(),
			UiPalette.DANGER if Game.money() < 0 else UiPalette.ACCENT)
	_ledger_row("演技", "%d" % Game.acting(), UiPalette.TEXT)

	_foot_hint.text = "这一局到此为止。"
	_next_button.text = "再来一局"


func _on_next_pressed() -> void:
	var ending: Dictionary = report.get("ending", {})
	if not _on_ending and not ending.is_empty():
		_build_ending()
		return
	if _on_ending:
		# 先让手机壳把本页清掉，再开新局 ——
		# 反过来的话，新局会先触发 state_reset、把我们这个正在发信号的节点一起清掉
		dismissed.emit()
		Game.new_game()
		return
	dismissed.emit()


# ============================================================
# 小工具
# ============================================================
func _after_state() -> Dictionary:
	var after: Dictionary = report.get("after", {})
	if not after.is_empty():
		return after
	# 重开看结局时读的是**存档版周报**，里面没有 before/after 快照 ——
	# 直接读当前状态，数字仍然是对的（那一局已经结束，状态不会再变）
	return {"money": Game.money(), "acting": Game.acting(),
			"fame": Game.fame(), "reputation": Game.reputation(),
			"neg": Game.state.negative_exposure}


func _clear() -> void:
	for child in _content.get_children():
		child.queue_free()


func _section(title: String) -> void:
	var l := Label.new()
	l.text = "— " + title + " —"
	UiPalette.text(l, 20, UiPalette.TEXT_DIM)
	_content.add_child(l)


func _note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.text(l, 17, UiPalette.TEXT_DISABLED)
	_content.add_child(l)


func _no_margin_note(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.text(l, 16, UiPalette.TEXT_DIM)
	parent.add_child(l)


func _ledger_row(key: String, value: String, value_color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_content.add_child(row)

	var k := Label.new()
	k.text = key
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiPalette.text(k, 19, UiPalette.TEXT_DIM)
	row.add_child(k)

	var v := Label.new()
	v.text = value
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiPalette.text(v, 21, value_color)
	row.add_child(v)


func _delta_row(key: String, from_value: int, to_value: int) -> void:
	var delta := to_value - from_value
	var color := UiPalette.TEXT_DIM
	if delta > 0:
		color = UiPalette.POSITIVE
	elif delta < 0:
		color = UiPalette.DANGER
	_ledger_row(key, "%d → %d（%+d）" % [from_value, to_value, delta], color)


func _apply_styles() -> void:
	get_node("Center/Card").add_theme_stylebox_override("panel",
			UiPalette.panel(UiPalette.PANEL, 24, 3, UiPalette.ACCENT))
	UiPalette.text(_title, 34, UiPalette.TEXT)
	UiPalette.text(_subtitle, 15, UiPalette.TEXT_DIM)
	UiPalette.text(_day_label, 20, UiPalette.ACCENT)
	UiPalette.text(_foot_hint, 17, UiPalette.TEXT_DIM)
	_next_button.focus_mode = Control.FOCUS_NONE
	_next_button.add_theme_font_size_override("font_size", 24)
	_next_button.add_theme_color_override("font_color", UiPalette.INK)
	_next_button.add_theme_color_override("font_hover_color", UiPalette.INK)
	_next_button.add_theme_color_override("font_pressed_color", UiPalette.INK)
	_next_button.add_theme_stylebox_override("normal",
			UiPalette.button(UiPalette.ACCENT, UiPalette.ACCENT, 2, 16))
	_next_button.add_theme_stylebox_override("hover",
			UiPalette.button(UiPalette.ACCENT.lightened(0.12), UiPalette.ACCENT, 3, 16))
	_next_button.add_theme_stylebox_override("pressed",
			UiPalette.button(UiPalette.ACCENT.darkened(0.1), UiPalette.ACCENT, 3, 16))

	var bar: VScrollBar = _content.get_parent().get_v_scroll_bar()
	bar.custom_minimum_size = Vector2(10, 0)
	bar.add_theme_stylebox_override("scroll",
			UiPalette.button(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0, 0))
	bar.add_theme_stylebox_override("grabber", UiPalette.rounded(UiPalette.LINE, 5))
	bar.add_theme_stylebox_override("grabber_highlight", UiPalette.rounded(UiPalette.ACCENT, 5))
