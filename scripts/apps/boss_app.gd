extends Control
## Boss直聘 —— 三层：公司列表 → 招聘详情 → 初次沟通（聊天）
##
## 【它的产出只有一个】让微信里多一个联系人。玩家**不在这里求职**（决策 1.4）：
## 「看」与「投」要分开 —— 投递花行动点（全局 21 点），看不用。混在一起玩家会以为投递免费。
##
## 【三层怎么走】
##   1. **公司列表**（左栏）= 缩略卡。只放文案里真有的字段，编不了的一律不显示
##   2. **招聘详情**（右栏）= 点开一家公司
##   3. **初次沟通**（右栏，盖住详情）= 点 HR 卡或底部「继续沟通」→ 逐句放对话，
##      放完 HR 说「加微信」→ **到这一步才解锁联系人**
##
## 【为什么解锁挪到聊天之后】原先是「点开招聘页 = 浏览过 = 解锁」，于是玩家一句话没说，
## 微信里就凭空多了一个人。现在这条链路是完整的：
## 看公司 → 看职位 → 说上话 → 拿到联系方式 → 去微信投递。
##
## 【对话从哪来】`data/companies/{代号}_*.md` 的「## 初次沟通」小节，
## 格式见 `data/companies/README.md`（狗牙按那张表写，程序照放）。
##
## 【左栏为什么是它】手机屏把左栏让出来时，本 App 交出**公司列表**
## （约定见 `phone_screen.gd`）；右栏留给详情与聊天。

signal cancelled
## 放完对话后请上层帮忙打开微信 —— 联系人刚加上，玩家多半想立刻去投递。
## 【为什么只发信号不自己开】微信不归本 App 管，它住在手机屏里，由那边接。
signal open_app_requested(scene_path: String)

const WECHAT_SCENE := "res://scenes/apps/wechat.tscn"
const P_TOP := "Page/TopBar/TopMargin/TopRow"
const P_LIST := "Page/BodyWrap/Body/ListPanel/ListMargin/ListBox"
const P_CONTENT := "Page/BodyWrap/Body/PostPanel/PostMargin/PostBox/PostScroll/PostContent"
const P_POST := "Page/BodyWrap/Body/PostPanel"
const P_POST_BOX := P_POST + "/PostMargin/PostBox"
const P_CHAT := "Page/BodyWrap/Body/ChatPanel"
const P_CHAT_BOX := P_CHAT + "/ChatMargin/ChatBox"

## 公司信息三张小卡：字段名 → 中文标题
const META_FIELDS: Array[Array] = [
	["industry", "行业"],
	["funding", "融资"],
	["scale", "规模"],
]

## 聊天逐条播放的间隔（秒）。**设成 0 = 一次放完** —— 「跳过」按钮与测试都走那条。
const CHAT_STEP := 0.85
## 气泡最大宽度：超了就折行。小于它时按文字实际宽度收窄（短句子不该拉成一条长条）
const MAX_BUBBLE_W := 560.0
const BUBBLE_FONT := 17
## 玩家那一侧的头像字
const ME_MARK := "你"

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
@onready var _hr_card: Button = get_node(P_CONTENT + "/HrCard")
@onready var _hint_panel: PanelContainer = get_node(P_CONTENT + "/HintPanel")
@onready var _hint_text: Label = get_node(P_CONTENT + "/HintPanel/HintMargin/HintBox/HintText")
@onready var _detail_caption: Label = get_node(P_CONTENT + "/DetailCaption")
@onready var _detail_text: Label = get_node(P_CONTENT + "/DetailText")
@onready var _note_label: Label = get_node(P_CONTENT + "/NoteLabel")
@onready var _post_panel: PanelContainer = get_node(P_POST)
@onready var _contact_button: Button = get_node(P_POST_BOX + "/PostFoot/FootMargin/FootRow/ContactButton")
@onready var _foot_hint: Label = get_node(P_POST_BOX + "/PostFoot/FootMargin/FootRow/FootHint")
@onready var _chat_panel: PanelContainer = get_node(P_CHAT)
@onready var _chat_back: Button = get_node(P_CHAT_BOX + "/ChatHead/ChatBack")
@onready var _chat_name: Label = get_node(P_CHAT_BOX + "/ChatHead/ChatWho/ChatName")
@onready var _chat_title: Label = get_node(P_CHAT_BOX + "/ChatHead/ChatWho/ChatTitle")
@onready var _chat_online: Label = get_node(P_CHAT_BOX + "/ChatHead/ChatOnline")
@onready var _chat_scroll: ScrollContainer = get_node(P_CHAT_BOX + "/ChatScroll")
@onready var _chat_feed: VBoxContainer = get_node(P_CHAT_BOX + "/ChatScroll/ChatFeed")
@onready var _chat_hint: Label = get_node(P_CHAT_BOX + "/ChatFoot/ChatHint")
@onready var _chat_skip: Button = get_node(P_CHAT_BOX + "/ChatFoot/ChatSkip")
@onready var _chat_to_wechat: Button = get_node(P_CHAT_BOX + "/ChatFoot/ChatToWechat")
@onready var _back_button: Button = get_node("Page/BackButton")

var _companies: Array[CompanyData] = []
var _current: CompanyData
var _rows: Dictionary = {}         ## code -> Button
var _row_labels: Dictionary = {}   ## code -> {state}
var _meta_labels: Dictionary = {}  ## 字段名 -> Label
var _hr_labels: Dictionary = {}    ## HrCard 里的三个 Label
var _syncing := false
## 聊天状态。`_chat_step` 设成 0 表示一次放完（「跳过」与测试用）
var _chat_step := CHAT_STEP
var _chat_lines: Array[ChatLine] = []
var _chat_index := 0
var _chat_done := false
## 玩家中途退了：**不再解锁** —— 得把话说完（或点跳过）才拿得到联系方式
var _chat_aborted := false


func _ready() -> void:
	_companies = CompanyLibrary.all()
	_apply_styles()
	_build_meta_cards()
	_build_hr_card()
	_build_company_list()

	EventBus.hr_unlocked.connect(_on_hr_unlocked)
	EventBus.state_reset.connect(_on_state_reset)
	_back_button.pressed.connect(func() -> void: cancelled.emit())
	_hr_card.pressed.connect(_open_chat)
	_contact_button.pressed.connect(_open_chat)
	_chat_back.pressed.connect(_close_chat)
	_chat_skip.pressed.connect(skip_chat)
	_chat_to_wechat.pressed.connect(func() -> void: open_app_requested.emit(WECHAT_SCENE))

	# 【不自动打开第一家】自动打开等于白送一个 HR —— 「说上话才拿到联系方式」得是真动作
	_show_empty_state()
	_refresh_top()
	_refresh_list()


## 让调用方把本页嵌进来时打开「返回」（见 wechat_app.gd 的「去 Boss直聘」）
func enable_back() -> void:
	_back_button.visible = true


## 手机屏把左栏让出来时，本 App 交出**公司列表**
func take_sidebar() -> Control:
	return get_node("Page/BodyWrap/Body/ListPanel")


func sidebar_title() -> String:
	return "Boss直聘 · 公司"


# ============================================================
# 第一层：公司列表（缩略卡）
# ============================================================
func _build_company_list() -> void:
	var group := ButtonGroup.new()
	for co: CompanyData in _companies:
		var row := _make_company_row(co)
		row.button_group = group
		row.toggled.connect(_on_company_toggled.bind(co.code))
		_company_list.add_child(row)
		_rows[co.code] = row


## 一张缩略卡。**排布照 Boss 的列表页，字段只用文案里真有的** ——
## 没有「经验/学历」就不写，没有「城市」也不编一个。
## 【为什么职位名摆在最上面】列表页一眼要能答「这家在招什么」，
## 公司名反而是次要的（它还叫「A 公司」，见 data/companies/README.md 的待补）。
func _make_company_row(co: CompanyData) -> Button:
	var row := Button.new()
	row.name = "Company_" + co.code
	row.toggle_mode = true
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size = Vector2(0, 152)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	row.add_child(margin)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	# ① 职位 + 薪资
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)

	var title := Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = co.position_title
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.text(title, 19, UiPalette.TEXT)
	head.add_child(title)

	var salary := Label.new()
	salary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	salary.text = co.salary
	salary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	salary.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	UiPalette.text(salary, 17, UiPalette.POSITIVE)
	head.add_child(salary)

	# ② 代号 + 公司 + 行业／融资／规模
	var meta := HBoxContainer.new()
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_theme_constant_override("separation", 8)
	box.add_child(meta)

	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(24, 24)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", UiPalette.rounded(
			UiPalette.COMPANY_TIER_COLORS.get(co.tier, UiPalette.LINE), 6))
	meta.add_child(chip)

	var mark := Label.new()
	mark.set_anchors_preset(Control.PRESET_FULL_RECT)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.text = co.code
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiPalette.text(mark, 14, UiPalette.INK)
	chip.add_child(mark)

	var facts := Label.new()
	facts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	facts.text = _facts_line(co)
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiPalette.text(facts, 15, UiPalette.TEXT_DIM)
	meta.add_child(facts)

	# ③ 标签
	var chips := HBoxContainer.new()
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_theme_constant_override("separation", 6)
	box.add_child(chips)
	for t: String in co.tags:
		chips.add_child(_tiny_chip(t))

	# ④ HR + 这一家的门槛／联系状态
	var foot := HBoxContainer.new()
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_theme_constant_override("separation", 10)
	box.add_child(foot)

	var hr := Label.new()
	hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hr.text = "%s · %s" % [co.hr_name, co.hr_title]
	hr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiPalette.text(hr, 15, UiPalette.TEXT_DIM)
	foot.add_child(hr)

	var acting := Label.new()
	acting.mouse_filter = Control.MOUSE_FILTER_IGNORE
	acting.text = "演技 %d" % co.acting_threshold
	acting.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiPalette.text(acting, 15, UiPalette.ACCENT)
	foot.add_child(acting)

	var state := Label.new()
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiPalette.text(state, 15, UiPalette.TEXT_DIM)
	foot.add_child(state)

	_row_labels[co.code] = {"state": state}
	return row


## 「公司 · 行业 · 融资 · 规模」，空的字段直接不出现
func _facts_line(co: CompanyData) -> String:
	var parts: Array[String] = [co.display_name]
	for v: String in [co.industry, co.funding, co.scale]:
		if not v.is_empty():
			parts.append(v)
	return "　".join(parts)


func _tiny_chip(text: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UiPalette.panel(Color("33333d"), 8))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 10)
	m.add_theme_constant_override("margin_top", 3)
	m.add_theme_constant_override("margin_bottom", 3)
	chip.add_child(m)
	var l := Label.new()
	l.text = text
	UiPalette.text(l, 14, UiPalette.TEXT_DIM)
	m.add_child(l)
	return chip


func _on_company_toggled(on: bool, code: String) -> void:
	if _syncing or not on:
		return
	_select_company(code)


func _select_company(code: String) -> void:
	_close_chat()
	_current = CompanyLibrary.by_code(code)
	_syncing = true
	for c: String in _rows:
		(_rows[c] as Button).button_pressed = (c == code)
	_syncing = false

	_show_posting()
	_refresh_list()
	_refresh_top()


# ============================================================
# 第二层：招聘详情
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
		UiPalette.text(caption, 14, UiPalette.TEXT_DIM)
		box.add_child(caption)

		var value := Label.new()
		value.text = "—"
		UiPalette.text(value, 18, UiPalette.TEXT)
		box.add_child(value)

		_meta_row.add_child(card)
		_meta_labels[field[0]] = value


## HR 卡：头像 + 名字·职位 + 活跃状态 + 一个「›」。整张卡可点 = 进聊天
## 【活跃状态是文案里的真话】md 的 HR 行后半段（「刚刚活跃｜今日回复 100+ 次」），
## 抠不到就不显示这一行 —— 编一句假的比少一行难看
func _build_hr_card() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_hr_card.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 14)
	margin.add_child(hbox)

	var avatar := Panel.new()
	avatar.custom_minimum_size = Vector2(58, 58)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar.add_theme_stylebox_override("panel", UiPalette.rounded(Color("4a4a58"), 29))
	hbox.add_child(avatar)

	var face := Label.new()
	face.set_anchors_preset(Control.PRESET_FULL_RECT)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.text = "HR"
	face.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	face.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiPalette.text(face, 18, UiPalette.TEXT)
	avatar.add_child(face)

	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.add_theme_constant_override("separation", 3)
	hbox.add_child(texts)

	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiPalette.text(name_label, 21, UiPalette.TEXT)
	texts.add_child(name_label)

	var title_label := Label.new()
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiPalette.text(title_label, 15, UiPalette.TEXT_DIM)
	texts.add_child(title_label)

	var status_label := Label.new()
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiPalette.text(status_label, 14, UiPalette.POSITIVE)
	texts.add_child(status_label)

	var arrow := Label.new()
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.text = "›"
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiPalette.text(arrow, 26, UiPalette.TEXT_DISABLED)
	hbox.add_child(arrow)

	_hr_labels = {"name": name_label, "title": title_label, "status": status_label}


func _show_empty_state() -> void:
	_current = null
	_company_name.text = "还没选公司"
	_company_tagline.text = "左边点一家公司，看它的招聘页"
	_lock_state.text = ""
	_meta_row.visible = false
	_job_panel.visible = false
	_hr_card.visible = false
	_hint_panel.visible = false
	_detail_caption.visible = false
	_detail_text.visible = false
	_note_label.visible = false
	_foot_hint.text = "左边挑一家公司"
	_contact_button.disabled = true


func _show_posting() -> void:
	var co := _current
	_company_name.text = co.display_name
	_company_tagline.text = co.tagline
	_meta_row.visible = true
	_job_panel.visible = true
	_hr_card.visible = true
	_hint_panel.visible = true
	_detail_caption.visible = true
	_detail_text.visible = true

	for field: Array in META_FIELDS:
		var v: String = co.get(field[0])
		(_meta_labels[field[0]] as Label).text = "—" if v.is_empty() else v

	_job_title.text = co.position_title
	_job_salary.text = co.salary
	_job_experience.text = "要求　" + co.experience if not co.experience.is_empty() else ""
	_build_tags(co.tags)

	(_hr_labels["name"] as Label).text = co.hr_name
	(_hr_labels["title"] as Label).text = co.hr_title
	var status := co.hr_status
	(_hr_labels["status"] as Label).text = status
	(_hr_labels["status"] as Label).visible = not status.is_empty()

	_hint_text.text = co.hint
	_detail_text.text = co.posting_text
	_note_label.text = "注：" + co.posting_note if not co.posting_note.is_empty() else ""
	_note_label.visible = not co.posting_note.is_empty()
	_foot_hint.text = "点 HR 聊两句，聊完微信里就有他了"
	_contact_button.disabled = false
	_set_lock_state(false)


func _build_tags(tags: Array[String]) -> void:
	for child in _tag_row.get_children():
		_tag_row.remove_child(child)
		child.queue_free()
	for t: String in tags:
		_tag_row.add_child(_tiny_chip(t))


## 微信联系人的状态：`fresh` = 刚聊完加上（那一下要显眼，玩家才知道自己拿到了什么）
func _set_lock_state(fresh: bool) -> void:
	if _current == null:
		return
	var co := _current
	if fresh:
		_lock_state.text = "✓ 刚加上联系人：%s · %s —— 去微信私聊就能投递" % [co.hr_name, co.hr_title]
		_lock_state.add_theme_color_override("font_color", UiPalette.POSITIVE)
	elif Game.is_hr_unlocked(co.code):
		_lock_state.text = "已在微信联系人里：%s · %s" % [co.hr_name, co.hr_title]
		_lock_state.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	else:
		_lock_state.text = "还没联系过 —— 点上面的 HR 说两句"
		_lock_state.add_theme_color_override("font_color", UiPalette.TEXT_DIM)


# ============================================================
# 第三层：初次沟通（聊天）
# ============================================================
func _open_chat() -> void:
	if _current == null:
		return
	_chat_lines = _current.opening_chat
	_chat_index = 0
	_chat_done = false
	_chat_aborted = false
	_clear_feed()
	_chat_name.text = _current.hr_name
	_chat_title.text = _current.hr_title
	_chat_online.text = _current.hr_status
	_chat_online.visible = not _current.hr_status.is_empty()
	_push_card()
	_post_panel.visible = false
	_chat_panel.visible = true
	_chat_to_wechat.visible = false
	_chat_hint.text = "HR 正在输入…"

	if _chat_lines.is_empty():
		# 文案一句都没写（连占位都没有）—— 不能把玩家卡死在这里，直接给联系方式
		_push_system("（这家还没写初次沟通的文案，先直接加上了）")
		_finish_chat()
		return
	if _chat_step <= 0.0:
		skip_chat()
	else:
		_play_chat()


## 把剩下的话一次放完 —— 「跳过」走这条，**测试也走这条**（不必等计时器）
func skip_chat() -> void:
	_chat_step = 0.0
	while _chat_index < _chat_lines.size():
		_push_line(_chat_lines[_chat_index])
		_chat_index += 1
	_finish_chat()
	_scroll_chat()


func _play_chat() -> void:
	while _chat_index < _chat_lines.size() and _chat_step > 0.0:
		_push_line(_chat_lines[_chat_index])
		_chat_index += 1
		_scroll_chat()
		await get_tree().create_timer(_chat_step).timeout
	_finish_chat()


## 回详情页。**中途退出了就不解锁** —— 得把话说完（或点跳过）才拿得到联系方式
func _close_chat() -> void:
	_chat_aborted = true
	_chat_index = _chat_lines.size()
	if _chat_panel != null:
		_chat_panel.visible = false
	if _post_panel != null and _current != null:
		_post_panel.visible = true


## 对话放完 —— **解锁就发生在这里**，不在「点开招聘页」那一步
func _finish_chat() -> void:
	if _chat_done or _chat_aborted or _current == null:
		return
	_chat_done = true
	var fresh := Game.unlock_hr(_current.code)
	_push_system("已把 %s 加进微信联系人" % _current.hr_name)
	_chat_hint.text = "去微信私聊就能投递 —— 发一段表情包就是投递" if fresh \
			else "这位早就在你的微信联系人里了"
	_chat_to_wechat.visible = true
	_set_lock_state(fresh)
	_refresh_list()
	_refresh_top()
	_scroll_chat()


func _push_line(line: ChatLine) -> void:
	var text := line.display_text()
	if text.is_empty():
		return
	if line.is_system():
		_push_system(text)
	else:
		_chat_feed.add_child(_bubble(line))


## 一个气泡。`me` = 右边（带「你」的头像），HR = 左边
func _bubble(line: ChatLine) -> Control:
	var mine := line.is_mine()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	if mine:
		row.add_child(_expander())

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var bg := Color("2f5f4a") if mine else UiPalette.PANEL_SOFT
	panel.add_theme_stylebox_override("panel", UiPalette.panel(bg, 14))

	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 11)
	panel.add_child(margin)

	var label := Label.new()
	var text := line.display_text()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 【为什么要把宽度算出来】autowrap 打开时 Label 的最小宽度会塌成几个字，
	# 短句子就会被压成一条竖条。按文字实际宽度给个下限，才既收窄又折行。
	label.custom_minimum_size = Vector2(_bubble_width(text), 0)
	UiPalette.text(label, BUBBLE_FONT, UiPalette.TEXT if not mine else Color("eaf7ef"))
	margin.add_child(label)
	row.add_child(panel)

	row.add_child(_avatar_mark(ME_MARK if mine else _current.hr_name.substr(0, 1)))
	if not mine:
		row.add_child(_expander())
	return row


func _bubble_width(text: String) -> float:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BUBBLE_FONT).x
	return minf(MAX_BUBBLE_W, w + 4.0)


func _expander() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(0, 0)
	return c


func _avatar_mark(mark: String) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(40, 40)
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel", UiPalette.rounded(Color("4a4a58"), 20))
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.text = mark
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiPalette.text(l, 15, UiPalette.TEXT)
	panel.add_child(l)
	return panel


## 居中那行小字（系统提示）—— 游戏自己发的，不是文案
func _push_system(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.text(l, 15, UiPalette.TEXT_DISABLED)
	_chat_feed.add_child(l)


## 聊天顶上那张职位卡（照抄招聘页的摘要）—— 参照图里就是先摆卡再说话
func _push_card() -> void:
	var co := _current
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiPalette.panel(UiPalette.PANEL_SOFT, 16))

	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	card.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)

	var title := Label.new()
	title.text = co.position_title
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.text(title, 20, UiPalette.TEXT)
	head.add_child(title)

	var salary := Label.new()
	salary.text = co.salary
	salary.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	UiPalette.text(salary, 18, UiPalette.POSITIVE)
	head.add_child(salary)

	var facts := Label.new()
	facts.text = _facts_line(co)
	facts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.text(facts, 15, UiPalette.TEXT_DIM)
	box.add_child(facts)

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	box.add_child(chips)
	for t: String in co.tags:
		chips.add_child(_tiny_chip(t))

	var hr := Label.new()
	hr.text = "%s · %s" % [co.hr_name, co.hr_title]
	UiPalette.text(hr, 15, UiPalette.TEXT_DIM)
	box.add_child(hr)

	_chat_feed.add_child(card)


## 【为什么先 remove_child 再 queue_free】`queue_free` 要等这一帧结束才真的摘掉节点，
## 在那之前 `get_child_count()` 还是旧数量 —— 界面看不出来，但断言会数错。
func _clear_feed() -> void:
	for child in _chat_feed.get_children():
		_chat_feed.remove_child(child)
		child.queue_free()


## 让最新一条露出来。**必须延后一帧**：刚 add_child 的控件还没算好高度，
## 立刻设 scroll_vertical 会被夹回旧的最大值（看着就是「滚不到底」）。
func _scroll_chat() -> void:
	if _chat_scroll != null:
		_chat_scroll.set_deferred("scroll_vertical", 1_000_000)


## 现在是不是停在聊天层（测试用）
func chat_open() -> bool:
	return _chat_panel.visible


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
			else "点开一家 → 点 HR 聊两句 → 他会把你加到微信里"


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


## 状态被整个换掉（开新局 / 读档）：清掉选中态与聊天，回到空状态
func _on_state_reset() -> void:
	_syncing = true
	for c: String in _rows:
		(_rows[c] as Button).button_pressed = false
	_syncing = false
	_close_chat()
	_clear_feed()
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
	_node_panel(_post_panel, UiPalette.PANEL, 20, 2, UiPalette.LINE)
	_node_panel(_chat_panel, UiPalette.PANEL, 20, 2, UiPalette.LINE)
	_node_panel(_job_panel, UiPalette.PANEL_SOFT, 16, 2, UiPalette.LINE)
	_node_panel(_hint_panel, Color("2a3326"), 16, 2, UiPalette.POSITIVE)
	_node_panel(get_node(P_POST_BOX + "/PostFoot"), UiPalette.PANEL, 0, 2, UiPalette.LINE)

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

	UiPalette.text(_company_name, 26, UiPalette.TEXT_DIM)
	UiPalette.text(_company_tagline, 32, UiPalette.TEXT)
	UiPalette.text(_lock_state, 16, UiPalette.TEXT_DIM)
	UiPalette.text(_job_title, 26, UiPalette.TEXT)
	UiPalette.text(_job_salary, 22, UiPalette.POSITIVE)
	UiPalette.text(_job_experience, 16, UiPalette.TEXT_DIM)
	UiPalette.text(get_node(P_CONTENT + "/HintPanel/HintMargin/HintBox/HintCaption"), 14, UiPalette.POSITIVE)
	UiPalette.text(_hint_text, 18, UiPalette.TEXT)
	UiPalette.text(_detail_caption, 18, UiPalette.TEXT_DIM)
	UiPalette.text(_detail_text, 17, UiPalette.TEXT)
	UiPalette.text(_note_label, 15, UiPalette.TEXT_DIM)
	UiPalette.text(_foot_hint, 15, UiPalette.TEXT_DIM)

	_style_action(_back_button, UiPalette.ACCENT, UiPalette.INK, UiPalette.ACCENT, 22)
	_style_action(_contact_button, UiPalette.ACCENT, UiPalette.INK, UiPalette.ACCENT, 22)
	_style_action(_chat_to_wechat, UiPalette.ACCENT, UiPalette.INK, UiPalette.ACCENT, 20)
	_style_action(_chat_back, UiPalette.PANEL_SOFT, UiPalette.TEXT, UiPalette.LINE, 18)
	_style_action(_chat_skip, UiPalette.PANEL_SOFT, UiPalette.TEXT_DIM, UiPalette.LINE, 18)

	# HR 卡：平时低调，鼠标上来才亮 —— 它是「下一步」，但不该跟职位抢眼
	_hr_card.focus_mode = Control.FOCUS_NONE
	_hr_card.add_theme_stylebox_override("normal",
			UiPalette.button(UiPalette.PANEL_SOFT, UiPalette.LINE, 2, 16))
	_hr_card.add_theme_stylebox_override("hover",
			UiPalette.button(Color("35353f"), UiPalette.ACCENT, 2, 16))
	_hr_card.add_theme_stylebox_override("pressed",
			UiPalette.button(Color("3d3d26"), UiPalette.ACCENT, 3, 16, 3))

	UiPalette.text(_chat_name, 26, UiPalette.TEXT)
	UiPalette.text(_chat_title, 15, UiPalette.TEXT_DIM)
	UiPalette.text(_chat_online, 15, UiPalette.POSITIVE)
	UiPalette.text(_chat_hint, 15, UiPalette.TEXT_DIM)

	for bar: VScrollBar in [
			_company_list.get_parent().get_v_scroll_bar(),
			_detail_text.get_parent().get_parent().get_v_scroll_bar(),
			_chat_scroll.get_v_scroll_bar()]:
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
