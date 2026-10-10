extends Control
## Boss直聘 App —— 只读的公司信息页，以及「解锁 HR」这件事本身
##
## 【为什么这个 App 一个动作都没有】决策 1.4：玩家**不在这里求职**。
## 它的全部产出是一个**副作用**：你看过某家的招聘页 → 微信里多一个联系人。
## 「看」和「投」分开是有意的 —— 投递要花行动点（全局只有 21 点），看不用。
## 混在一起玩家很容易点错，而且会以为投递是免费的。
##
## 运行：godot --path <项目> res://scenes/apps/boss.tscn

## 被当成「子页面」嵌进微信时才需要返回（手机壳还没做，先这么串）。
## 独立跑时它是主场景，没有"上一步"可返回，所以按钮默认隐藏。
signal cancelled

const P_TOP := "Page/TopBar/TopMargin/TopRow"
const P_LIST := "Page/BodyWrap/Body/ListPanel/ListMargin/ListBox"
const P_CONTENT := "Page/BodyWrap/Body/PostPanel/PostMargin/PostBox/PostScroll/PostContent"

## 公司信息三张小卡：字段名 → 中文标题
const META_FIELDS: Array[Array] = [
	["industry", "行业"],
	["funding", "融资"],
	["scale", "规模"],
]

@onready var _status_label: Label = get_node(P_TOP + "/TopRight/StatusLabel")
@onready var _channel_label: Label = get_node(P_TOP + "/TopRight/ChannelLabel")
@onready var _company_list: VBoxContainer = get_node(P_LIST + "/ListScroll/CompanyList")
@onready var _list_hint: Label = get_node(P_LIST + "/ListHint")
@onready var _company_name: Label = get_node(P_CONTENT + "/CompanyName")
@onready var _company_tagline: Label = get_node(P_CONTENT + "/CompanyTagline")
@onready var _lock_state: Label = get_node(P_CONTENT + "/LockState")
@onready var _meta_row: HBoxContainer = get_node(P_CONTENT + "/MetaRow")
@onready var _job_panel: PanelContainer = get_node(P_CONTENT + "/JobPanel")
@onready var _job_title: Label = get_node(P_CONTENT + "/JobPanel/JobMargin/JobBox/JobTitle")
@onready var _job_salary: Label = get_node(P_CONTENT + "/JobPanel/JobMargin/JobBox/JobSalary")
@onready var _job_experience: Label = get_node(P_CONTENT + "/JobPanel/JobMargin/JobBox/JobExperience")
@onready var _tag_row: HBoxContainer = get_node(P_CONTENT + "/JobPanel/JobMargin/JobBox/TagRow")
@onready var _hint_panel: PanelContainer = get_node(P_CONTENT + "/HintPanel")
@onready var _hint_text: Label = get_node(P_CONTENT + "/HintPanel/HintMargin/HintBox/HintText")
@onready var _detail_caption: Label = get_node(P_CONTENT + "/DetailCaption")
@onready var _detail_text: Label = get_node(P_CONTENT + "/DetailText")
@onready var _note_label: Label = get_node(P_CONTENT + "/NoteLabel")
@onready var _back_button: Button = get_node("Page/BackButton")

var _companies: Array[CompanyData] = []
var _current: CompanyData
var _rows: Dictionary = {}         ## code -> Button
var _row_labels: Dictionary = {}   ## code -> {tagline, threshold, state}
var _meta_labels: Dictionary = {}  ## 字段名 -> Label
var _syncing := false


func _ready() -> void:
	_companies = CompanyLibrary.all()
	_apply_styles()
	_build_meta_cards()
	_build_company_list()

	EventBus.hr_unlocked.connect(_on_hr_unlocked)
	EventBus.state_reset.connect(_on_state_reset)
	_back_button.pressed.connect(func() -> void: cancelled.emit())

	# 【不自动打开第一家】自动打开等于白送一个 HR —— 「浏览过才解锁」得是玩家真的点过。
	_show_empty_state()
	_refresh_top()
	_refresh_list()


## 让调用方把本页嵌进来时打开「返回」（见 wechat_app.gd 的「去 Boss直聘」）
func enable_back() -> void:
	_back_button.visible = true


# ============================================================
# 公司列表
# ============================================================
func _build_company_list() -> void:
	var group := ButtonGroup.new()
	for co: CompanyData in _companies:
		var row := _make_company_row(co)
		row.button_group = group
		row.toggled.connect(_on_company_toggled.bind(co.code))
		_company_list.add_child(row)
		_rows[co.code] = row


func _make_company_row(co: CompanyData) -> Button:
	var row := Button.new()
	row.name = "Company_" + co.code
	row.toggle_mode = true
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size = Vector2(0, 96)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	row.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 12)
	margin.add_child(hbox)

	var avatar := Panel.new()
	avatar.custom_minimum_size = Vector2(54, 54)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar.add_theme_stylebox_override("panel", UiPalette.rounded(
			UiPalette.COMPANY_TIER_COLORS.get(co.tier, UiPalette.LINE), 12))
	hbox.add_child(avatar)

	var initial := Label.new()
	initial.set_anchors_preset(Control.PRESET_FULL_RECT)
	initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	initial.text = co.code
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.add_theme_font_size_override("font_size", 26)
	initial.add_theme_color_override("font_color", UiPalette.INK)
	avatar.add_child(initial)

	var text_box := VBoxContainer.new()
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 2)
	hbox.add_child(text_box)

	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = co.display_name
	text_box.add_child(name_label)

	var tagline := Label.new()
	tagline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tagline.text = co.tagline
	tagline.add_theme_font_size_override("font_size", 15)
	tagline.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	text_box.add_child(tagline)

	var tail := VBoxContainer.new()
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tail.add_theme_constant_override("separation", 2)
	hbox.add_child(tail)

	var threshold := Label.new()
	threshold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	threshold.text = "演技 %d" % co.acting_threshold
	threshold.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	threshold.add_theme_font_size_override("font_size", 15)
	threshold.add_theme_color_override("font_color", UiPalette.ACCENT)
	tail.add_child(threshold)

	var state := Label.new()
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	state.add_theme_font_size_override("font_size", 15)
	tail.add_child(state)

	_row_labels[co.code] = {"state": state}
	return row


func _on_company_toggled(on: bool, code: String) -> void:
	if _syncing or not on:
		return
	_select_company(code)


func _select_company(code: String) -> void:
	_current = CompanyLibrary.by_code(code)
	_syncing = true
	for c: String in _rows:
		(_rows[c] as Button).button_pressed = (c == code)
	_syncing = false

	_show_posting()
	# 进页即算「浏览过」—— 决策 12 的解锁条件就是这个动作
	var fresh := Game.unlock_hr(_current.code)
	_set_lock_state(fresh)
	_refresh_list()
	_refresh_top()


# ============================================================
# 招聘页
# ============================================================
func _build_meta_cards() -> void:
	for field: Array in META_FIELDS:
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", UiPalette.panel(UiPalette.PANEL_SOFT, 12))

		var margin := MarginContainer.new()
		for side in ["left", "right"]:
			margin.add_theme_constant_override("margin_" + side, 14)
		for side in ["top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 10)
		card.add_child(margin)

		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		margin.add_child(box)

		var caption := Label.new()
		caption.text = field[1]
		caption.add_theme_font_size_override("font_size", 14)
		caption.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		box.add_child(caption)

		var value := Label.new()
		value.text = "—"
		value.add_theme_font_size_override("font_size", 18)
		value.add_theme_color_override("font_color", UiPalette.TEXT)
		box.add_child(value)

		_meta_row.add_child(card)
		_meta_labels[field[0]] = value


func _show_empty_state() -> void:
	_current = null
	_company_name.text = "还没选公司"
	_company_tagline.text = "左边点一家公司，看它的招聘页"
	_lock_state.text = ""
	_meta_row.visible = false
	_job_panel.visible = false
	_hint_panel.visible = false
	_detail_caption.visible = false
	_detail_text.visible = false
	_note_label.visible = false


func _show_posting() -> void:
	var co := _current
	_company_name.text = co.display_name
	_company_tagline.text = co.tagline
	_meta_row.visible = true
	_job_panel.visible = true
	_hint_panel.visible = true
	_detail_caption.visible = true
	_detail_text.visible = true

	for field: Array in META_FIELDS:
		var v: String = co.get(field[0])
		(_meta_labels[field[0]] as Label).text = "—" if v.is_empty() else v

	_job_title.text = co.position_title
	_job_salary.text = "薪资　" + co.salary if not co.salary.is_empty() else ""
	_job_experience.text = "要求　" + co.experience if not co.experience.is_empty() else ""
	_build_tags(co.tags)

	_hint_text.text = co.hint
	_detail_text.text = co.posting_text
	_note_label.text = "注：" + co.posting_note if not co.posting_note.is_empty() else ""
	_note_label.visible = not co.posting_note.is_empty()


func _build_tags(tags: Array[String]) -> void:
	for child in _tag_row.get_children():
		child.queue_free()
	for t: String in tags:
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UiPalette.panel(Color("33333d"), 8))
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", 12)
		m.add_theme_constant_override("margin_right", 12)
		m.add_theme_constant_override("margin_top", 4)
		m.add_theme_constant_override("margin_bottom", 4)
		chip.add_child(m)
		var l := Label.new()
		l.text = t
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		m.add_child(l)
		_tag_row.add_child(chip)


func _set_lock_state(fresh: bool) -> void:
	var co := _current
	if fresh:
		_lock_state.text = "✓ 刚加上联系人：%s · %s —— 去微信私聊就能投递" % [co.hr_name, co.hr_title]
		_lock_state.add_theme_color_override("font_color", UiPalette.POSITIVE)
	else:
		_lock_state.text = "已在微信联系人里：%s · %s" % [co.hr_name, co.hr_title]
		_lock_state.add_theme_color_override("font_color", UiPalette.TEXT_DIM)


# ============================================================
# 刷新
# ============================================================
func _refresh_top() -> void:
	var n := 0
	for co: CompanyData in _companies:
		if Game.is_hr_unlocked(co.code):
			n += 1
	_status_label.text = "已联系 %d / %d 家" % [n, _companies.size()]
	_channel_label.text = "你的演技 %d ｜ 这里只看不投" % Game.acting()
	_list_hint.text = "五家都加上了 —— 去微信挑一家私聊" if n == _companies.size() \
			else "点开一家，HR 会出现在微信的联系人里"


func _refresh_list() -> void:
	for co: CompanyData in _companies:
		var unlocked := Game.is_hr_unlocked(co.code)
		var state: Label = _row_labels[co.code]["state"]
		state.text = "已联系" if unlocked else "未联系"
		state.add_theme_color_override("font_color",
				UiPalette.POSITIVE if unlocked else UiPalette.TEXT_DIM)
		var row: Button = _rows[co.code]
		row.add_theme_stylebox_override("normal",
				UiPalette.button(UiPalette.PANEL_SOFT, UiPalette.LINE, 1, 14))
		row.add_theme_stylebox_override("hover",
				UiPalette.button(Color("35353f"), UiPalette.LINE, 2, 14))
		row.add_theme_stylebox_override("pressed",
				UiPalette.button(Color("3d3d26"), UiPalette.ACCENT, 3, 14, 3))


func _on_hr_unlocked(_code: String) -> void:
	_refresh_list()
	_refresh_top()


## 状态被整个换掉（开新局 / 读档）：清掉选中态，回到空状态
func _on_state_reset() -> void:
	_syncing = true
	for c: String in _rows:
		(_rows[c] as Button).button_pressed = false
	_syncing = false
	_show_empty_state()
	_refresh_top()
	_refresh_list()


# ============================================================
# 样式
# ============================================================
func _apply_styles() -> void:
	get_node("Bg").color = UiPalette.BG

	var top_sb := StyleBoxFlat.new()
	top_sb.bg_color = UiPalette.PANEL
	top_sb.border_width_bottom = 3
	top_sb.border_color = UiPalette.ACCENT
	get_node("Page/TopBar").add_theme_stylebox_override("panel", top_sb)

	_node_panel(get_node("Page/BodyWrap/Body/ListPanel"), UiPalette.PANEL, 20, 2, UiPalette.LINE)
	_node_panel(get_node("Page/BodyWrap/Body/PostPanel"), UiPalette.PANEL, 20, 2, UiPalette.LINE)
	_node_panel(_job_panel, UiPalette.PANEL_SOFT, 16, 2, UiPalette.LINE)
	_node_panel(_hint_panel, Color("2a3326"), 16, 2, UiPalette.POSITIVE)

	var chip := StyleBoxFlat.new()
	chip.bg_color = UiPalette.ACCENT
	chip.set_corner_radius_all(12)
	get_node(P_TOP + "/BrandRow/BrandChip").add_theme_stylebox_override("panel", chip)

	UiPalette.text(get_node(P_TOP + "/BrandRow/BrandText"), 26, UiPalette.ACCENT)
	UiPalette.text(get_node(P_TOP + "/TopCenter/Title"), 40, UiPalette.TEXT)
	UiPalette.text(get_node(P_TOP + "/TopCenter/Subtitle"), 15, UiPalette.TEXT_DIM)
	UiPalette.text(_status_label, 20, UiPalette.ACCENT)
	UiPalette.text(_channel_label, 15, UiPalette.TEXT_DIM)

	UiPalette.text(get_node(P_LIST + "/ListCaption"), 22, UiPalette.TEXT)
	UiPalette.text(_list_hint, 14, UiPalette.TEXT_DIM)

	UiPalette.text(_company_name, 34, UiPalette.TEXT)
	UiPalette.text(_company_tagline, 18, UiPalette.ACCENT)
	UiPalette.text(_lock_state, 16, UiPalette.TEXT_DIM)
	UiPalette.text(_job_title, 24, UiPalette.TEXT)
	UiPalette.text(_job_salary, 18, UiPalette.POSITIVE)
	UiPalette.text(_job_experience, 16, UiPalette.TEXT_DIM)
	UiPalette.text(get_node(P_CONTENT + "/HintPanel/HintMargin/HintBox/HintCaption"), 14, UiPalette.POSITIVE)
	UiPalette.text(_hint_text, 18, UiPalette.TEXT)
	UiPalette.text(_detail_caption, 18, UiPalette.TEXT_DIM)
	UiPalette.text(_detail_text, 17, UiPalette.TEXT)
	UiPalette.text(_note_label, 15, UiPalette.TEXT_DIM)

	_style_action(_back_button, UiPalette.ACCENT, UiPalette.INK, UiPalette.ACCENT, 22)

	for bar: VScrollBar in [
			_company_list.get_parent().get_v_scroll_bar(),
			_detail_text.get_parent().get_parent().get_v_scroll_bar()]:
		bar.custom_minimum_size = Vector2(10, 0)
		bar.add_theme_stylebox_override("scroll",
				UiPalette.button(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0, 0))
		bar.add_theme_stylebox_override("grabber", UiPalette.rounded(UiPalette.LINE, 5))
		bar.add_theme_stylebox_override("grabber_highlight", UiPalette.rounded(UiPalette.ACCENT, 5))


func _node_panel(node: Node, bg: Color, radius: int, border: int,
		border_color: Color = UiPalette.LINE) -> void:
	node.add_theme_stylebox_override("panel", UiPalette.panel(bg, radius, border, border_color))


func _style_action(b: Button, bg: Color, fg: Color, border: Color, font_size: int) -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_stylebox_override("normal", UiPalette.button(bg, border, 2, 14))
	b.add_theme_stylebox_override("hover", UiPalette.button(bg.lightened(0.08), border, 3, 14))
	b.add_theme_stylebox_override("pressed", UiPalette.button(bg.darkened(0.1), border, 3, 14))
