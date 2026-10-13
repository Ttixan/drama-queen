extends Control
## 微信 App —— 私聊 HR 就是投递
##
## 【为什么投递入口在微信】决策 1.4：Boss直聘 只读（逛公司 / 解锁 HR / 看偏好线索），
## 玩家真正递出表情包的动作发生在**私聊**里。投递的仪式感来自聊天，不是一张表单。
##
## 【职责边界】和录像机一样：读状态、画出来、把输入转成对核心的调用。
## 校验、扣行动点、判定、配回信全在 `Game.submit_audition()` 里，
## 这个文件只负责把结果显示成聊天气泡。这里写判定逻辑 = 数值模拟器白做。
##
## 运行：godot --path <项目> res://scenes/apps/wechat.tscn

const P_TOP := "Page/TopBar/TopMargin/TopRow"
const P_CONTACTS := "Page/BodyWrap/Body/ContactsPanel/ContactsMargin/ContactsBox"
const P_CHAT := "Page/BodyWrap/Body/ChatPanel/ChatMargin/ChatBox"
const P_HEADER := P_CHAT + "/ChatHeader/HeaderMargin/HeaderBox"
const P_COMPOSER := P_CHAT + "/Composer/ComposerMargin/ComposerBox"

const RECORDER_SCENE := "res://scenes/minigame/recorder.tscn"
const BOSS_SCENE := "res://scenes/apps/boss.tscn"
const BUBBLE_WIDTH := 720
const CONTACT_AVATAR := 54

## 被手机壳当成一个 App 打开时才需要返回。独立运行时它是主场景，没有"上一步"。
signal cancelled

## 公司档位配色统一在 UiPalette（Boss直聘 的联系人头像用同一套）
const TIER_COLORS := UiPalette.COMPANY_TIER_COLORS

@onready var _status_label: Label = get_node(P_TOP + "/TopRight/StatusLabel")
@onready var _channel_label: Label = get_node(P_TOP + "/TopRight/ChannelLabel")
## 顶部大字与副标题 —— 事件会话时它们要换成另一套说法（见 _refresh_top）
@onready var _title: Label = get_node(P_TOP + "/TopCenter/Title")
@onready var _subtitle: Label = get_node(P_TOP + "/TopCenter/Subtitle")
@onready var _contact_list: VBoxContainer = get_node(P_CONTACTS + "/ContactsScroll/ContactList")
@onready var _contacts_hint: Label = get_node(P_CONTACTS + "/ContactsHint")
@onready var _peer_name: Label = get_node(P_HEADER + "/PeerBox/PeerName")
@onready var _peer_meta: Label = get_node(P_HEADER + "/PeerBox/PeerMeta")
@onready var _requirement_label: Label = get_node(P_HEADER + "/RequirementLabel")
@onready var _chat_scroll: ScrollContainer = get_node(P_CHAT + "/ChatScroll")
@onready var _chat_log: VBoxContainer = get_node(P_CHAT + "/ChatScroll/ChatLog")
@onready var _role_row: Control = get_node(P_COMPOSER + "/RoleRow")
@onready var _attach_row: Control = get_node(P_COMPOSER + "/AttachRow")
@onready var _send_row: Control = get_node(P_COMPOSER + "/SendRow")
@onready var _role_buttons_row: HBoxContainer = get_node(P_COMPOSER + "/RoleRow/RoleButtons")
@onready var _attach_card: PanelContainer = get_node(P_COMPOSER + "/AttachRow/AttachCard")
@onready var _attach_title: Label = get_node(P_COMPOSER + "/AttachRow/AttachCard/AttachMargin/AttachBox/AttachTitle")
@onready var _attach_detail: Label = get_node(P_COMPOSER + "/AttachRow/AttachCard/AttachMargin/AttachBox/AttachDetail")
@onready var _go_boss_button: Button = get_node(P_CONTACTS + "/GoBossButton")
@onready var _open_recorder_button: Button = get_node(P_COMPOSER + "/AttachRow/OpenRecorderButton")
@onready var _status_line: Label = get_node(P_COMPOSER + "/SendRow/StatusLine")
@onready var _send_button: Button = get_node(P_COMPOSER + "/SendRow/SendButton")
@onready var _back_button: Button = get_node("Page/BackButton")

var _companies: Array[CompanyData] = []
var _current: CompanyData
var _role: RoleRequirement
var _pending: Clip
var _rows: Dictionary = {}            ## code -> Button
var _row_labels: Dictionary = {}      ## code -> {name, state}
var _role_buttons: Dictionary = {}    ## tier -> Button
var _overlay: Node                    ## 当前嵌进来盖在整页上的子 App
## 程序化改按钮状态时会触发 toggled，用它挡住自己绕自己
var _syncing := false

## ---- 事件会话（GDD 四、系统划分把「随机事件」归给微信的「联系其他人」）----
## 当前打开的是哪个事件说话人。空串 = 在看某家公司的 HR。
##
## 【为什么不和 _current 合成一个「会话」类型】两者要的东西差得远：HR 会话要
## 角色档位 / 待投递表情包 / 投递次数，事件会话只要一个待处理的 `EventData`。
## 合成一个类型就得在每个用到的地方判它的类型字段。一个空串当开关，
## 判断集中在本文件唯一的 `_is_event_chat()` 里。
var _event_speaker: StringName = &""
var _event_box: VBoxContainer               ## 联系人列表顶上那一段
var _event_caption: Label
var _event_rows: Dictionary = {}            ## speaker -> Button
var _event_row: Control                    ## composer 里事件那一段（脚本建的）
var _event_buttons_row: HBoxContainer
var _event_status: Label
var _event_buttons: Array[Button] = []
## 事件与公司 HR 共用 —— 一次只开一个会话。事件那边会随周重建，
## 分组存成字段，重连时用的是同一个。
var _contact_group: ButtonGroup
var _hr_caption: Label


func _ready() -> void:
	_companies = CompanyLibrary.all()

	_apply_styles()
	_build_contacts()
	_build_event_composer()

	EventBus.hr_unlocked.connect(_on_hr_unlocked)
	EventBus.ap_changed.connect(_on_ap_changed)
	EventBus.state_reset.connect(_on_state_reset)
	EventBus.week_event_offered.connect(_on_week_event_offered)
	EventBus.week_event_resolved.connect(_on_week_event_resolved)
	_go_boss_button.pressed.connect(_on_open_boss)
	_open_recorder_button.pressed.connect(_on_open_recorder)
	_send_button.pressed.connect(_on_send)
	_back_button.pressed.connect(func() -> void: cancelled.emit())

	# 【开局先打开「找上门的人」】周初事件是 GDD 一周流程的阶段 1，它得先被看见 ——
	# 否则玩家会一路投递到周末，才发现有人在等他回话。
	var opening := Game.pending_event()
	if opening != null and not opening.speaker.is_empty():
		_select_event_speaker(opening.speaker)
		return

	var first := _first_contact_code()
	if first != "":
		_select_company(first)
	else:
		# 开局五家全锁是正常状态 —— 玩家还没逛过 Boss直聘
		_refresh_all()
		_rebuild_chat()


# ============================================================
# 联系人列表
# ============================================================
func _build_contacts() -> void:
	_contact_group = ButtonGroup.new()

	# 事件固定在最上面：它一周只来一次，位置飘的话玩家会找不到它
	_event_caption = Label.new()
	_event_caption.name = "EventCaption"
	_event_caption.text = "找上门的人"
	_contact_list.add_child(_event_caption)

	_event_box = VBoxContainer.new()
	_event_box.name = "EventList"
	_event_box.add_theme_constant_override("separation", 8)
	_contact_list.add_child(_event_box)

	_hr_caption = Label.new()
	_hr_caption.name = "HrCaption"
	_hr_caption.text = "公司 HR"
	_contact_list.add_child(_hr_caption)

	for co: CompanyData in _companies:
		var row := _make_contact_row(co)
		row.button_group = _contact_group
		row.toggled.connect(_on_contact_toggled.bind(co.code))
		_contact_list.add_child(row)
		_rows[co.code] = row


# ============================================================
# 事件会话（GDD 四、系统划分：微信的「联系其他人（随机事件）」）
# ============================================================
func _is_event_chat() -> bool:
	return _event_speaker != &""


## 会话列表的顺序：**这周还没回的排最前**，其余按遇到的先后倒序。
func _speakers_in_order() -> Array[StringName]:
	var out: Array[StringName] = []
	var ev := Game.pending_event()
	if ev != null and not ev.speaker.is_empty():
		out.append(ev.speaker)
	var history: Array[Dictionary] = Game.state.event_history
	for i in range(history.size() - 1, -1, -1):
		var sp := StringName(history[i].get("speaker", ""))
		if not sp.is_empty() and not out.has(sp):
			out.append(sp)
	return out


## 说话人的显示名。事件本里才有 —— 找不到就退回代号，别在界面上留空
func _speaker_name(speaker: StringName) -> String:
	var ev := Game.pending_event()
	if ev != null and ev.speaker == speaker:
		return ev.speaker_name
	var history: Array[Dictionary] = Game.state.event_history
	for i in range(history.size() - 1, -1, -1):
		if StringName(history[i].get("speaker", "")) != speaker:
			continue
		var found := EventLibrary.find(StringName(history[i].get("event", "")))
		if found != null:
			return found.speaker_name
	return String(speaker)


## 这个人此刻的状态：等你回话 / 已回过 / 没理会
func _speaker_state(speaker: StringName) -> String:
	var ev := Game.pending_event()
	if ev != null and ev.speaker == speaker:
		return "等你回话"
	var history: Array[Dictionary] = Game.state.event_history
	for i in range(history.size() - 1, -1, -1):
		if StringName(history[i].get("speaker", "")) != speaker:
			continue
		return "没理会" if int(history[i].get("choice", -1)) < 0 else "已回过"
	return ""


## 重建事件那一段。每周换人，所以整段重建。
##
## 【为什么不逐条改状态】这里最多四五条，而"谁在列表里"本身每周都在变 ——
## 逐条更新要额外维护一份索引，重建反而直白。
func _refresh_event_contacts() -> void:
	for child in _event_box.get_children():
		# 【为什么先 remove_child 再 queue_free】queue_free 要到帧末才真删，
		# 期间它还算在子节点里 —— 而本函数每次刷新都会跑，
		# 一帧内刷新两次就会叠出两份看得见的旧行。
		_event_box.remove_child(child)
		child.queue_free()
	_event_rows.clear()

	_syncing = true
	for sp: StringName in _speakers_in_order():
		var row := _make_event_row(sp)
		row.button_group = _contact_group
		row.toggled.connect(_on_event_toggled.bind(sp))
		row.button_pressed = (sp == _event_speaker)
		_event_box.add_child(row)
		_event_rows[sp] = row
	_syncing = false

	# 开局第一天一个人都没有，这时候两行标题也别挂着
	var any_events := not _event_rows.is_empty()
	_event_caption.visible = any_events
	_event_box.visible = any_events
	if not any_events:
		_event_speaker = &""


func _on_event_toggled(on: bool, speaker: StringName) -> void:
	if _syncing or not on:
		return
	_select_event_speaker(speaker)


func _select_event_speaker(speaker: StringName) -> void:
	_current = null
	_event_speaker = speaker
	_role = null
	_syncing = true
	for c: String in _rows:
		(_rows[c] as Button).button_pressed = false
	_syncing = false
	# 角色档位那一排是 HR 专用的，切到事件会话要清掉
	for child in _role_buttons_row.get_children():
		child.queue_free()
	_role_buttons.clear()
	_refresh_all()
	_rebuild_chat()
	_scroll_chat_to_bottom()


func _make_event_row(speaker: StringName) -> Button:
	var display_name := _speaker_name(speaker)
	var row := Button.new()
	row.name = "Event_" + String(speaker)
	row.toggle_mode = true
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size = Vector2(0, 82)
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

	# 头像用名字首字 + 事件专用的青色：和下面那排公司 HR 一眼分得开
	var avatar := Panel.new()
	avatar.custom_minimum_size = Vector2(CONTACT_AVATAR, CONTACT_AVATAR)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar.add_theme_stylebox_override("panel", UiPalette.rounded(UiPalette.EVENT, 12))
	hbox.add_child(avatar)

	var initial := Label.new()
	initial.set_anchors_preset(Control.PRESET_FULL_RECT)
	initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	initial.text = display_name.substr(0, 1)
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.add_theme_font_size_override("font_size", 24)
	initial.add_theme_color_override("font_color", UiPalette.INK)
	avatar.add_child(initial)

	var text_box := VBoxContainer.new()
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 2)
	hbox.add_child(text_box)

	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = display_name
	text_box.add_child(name_label)

	var state := Label.new()
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state.text = _speaker_state(speaker)
	state.add_theme_font_size_override("font_size", 15)
	state.add_theme_color_override("font_color",
			UiPalette.EVENT if state.text == "等你回话" else UiPalette.TEXT_DIM)
	text_box.add_child(state)

	var tail := Label.new()
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tail.add_theme_font_size_override("font_size", 15)
	tail.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	hbox.add_child(tail)

	row.add_theme_stylebox_override("normal",
			UiPalette.button(UiPalette.PANEL_SOFT, UiPalette.LINE, 1, 14))
	row.add_theme_stylebox_override("hover",
			UiPalette.button(Color("35353f"), UiPalette.LINE, 2, 14))
	row.add_theme_stylebox_override("pressed",
			UiPalette.button(Color("26343a"), UiPalette.EVENT, 3, 14, 3))
	UiPalette.text(name_label, 18, UiPalette.TEXT)
	return row


func _make_contact_row(co: CompanyData) -> Button:
	var row := Button.new()
	row.name = "Contact_" + co.code
	row.toggle_mode = true
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size = Vector2(0, 92)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# 内容全部 MOUSE_FILTER_IGNORE —— 点击必须透给按钮本身，否则 hover / pressed 失灵
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
	avatar.custom_minimum_size = Vector2(CONTACT_AVATAR, CONTACT_AVATAR)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar.add_theme_stylebox_override("panel",
			UiPalette.rounded(TIER_COLORS.get(co.tier, UiPalette.LINE), 12))
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
	name_label.text = co.hr_name
	text_box.add_child(name_label)

	var meta := Label.new()
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.text = "%s · %s" % [co.display_name, co.hr_title]
	meta.add_theme_font_size_override("font_size", 15)
	meta.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	text_box.add_child(meta)

	var state := Label.new()
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	state.add_theme_font_size_override("font_size", 15)
	hbox.add_child(state)

	_row_labels[co.code] = {"name": name_label, "state": state}
	return row


## 默认选中第一家**已解锁**的公司。
## 【都没解锁时不选任何一家】开局五家全锁是**正常状态**（还没逛过 Boss直聘），
## 强行选中第一家只会让玩家看到一个"能点但发不出去"的界面；
## 不选 + 右边一句「点下面去 Boss直聘」更直接。
func _first_contact_code() -> String:
	for co: CompanyData in _companies:
		if Game.is_hr_unlocked(co.code):
			return co.code
	return ""


func _on_contact_toggled(on: bool, code: String) -> void:
	if _syncing or not on:
		return
	_select_company(code)


func _select_company(code: String) -> void:
	_current = CompanyLibrary.by_code(code)
	# 【两个开关必须成对】`_is_event_chat()` 只看 `_event_speaker`，
	# 切回 HR 会话时忘了清它，界面会一直停在「事件会话」那一套上 ——
	# 表现是 HR 的三排 composer 全不见、头部还在显示事件内容。
	_event_speaker = &""
	_role = null
	_syncing = true
	for c: String in _rows:
		(_rows[c] as Button).button_pressed = (c == code)
	_syncing = false
	_build_role_buttons()
	_refresh_all()
	_rebuild_chat()
	_scroll_chat_to_bottom()


# ============================================================
# 角色档位
# ============================================================
func _build_role_buttons() -> void:
	for child in _role_buttons_row.get_children():
		child.queue_free()
	_role_buttons.clear()
	if _current == null:
		return

	var group := ButtonGroup.new()
	for role: RoleRequirement in _current.roles:
		var b := Button.new()
		b.name = "Role_%d" % role.tier
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 62)
		b.text = "%s\n演技 %d ｜ 匹配 %.0f%%" % [
			role.tier_name(), _required_acting(role), role.match_line * 100.0]
		b.add_theme_font_size_override("font_size", 16)
		b.add_theme_stylebox_override("normal",
				UiPalette.button(UiPalette.PANEL_SOFT, UiPalette.LINE, 2, 12, 0, 8))
		b.add_theme_stylebox_override("hover",
				UiPalette.button(Color("35353f"), UiPalette.ACCENT, 2, 12, 0, 8))
		b.add_theme_stylebox_override("pressed",
				UiPalette.button(UiPalette.ACCENT, UiPalette.ACCENT, 2, 12, 3, 8))
		b.add_theme_stylebox_override("disabled",
				UiPalette.button(Color("1c1c22"), UiPalette.LINE, 1, 12, 0, 8))
		b.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		b.add_theme_color_override("font_pressed_color", UiPalette.INK)
		b.add_theme_color_override("font_disabled_color", Color("5a5a63"))
		b.toggled.connect(_on_role_toggled.bind(role.tier))
		_role_buttons_row.add_child(b)
		_role_buttons[role.tier] = b

	_auto_pick_role()


## 演技门槛 = 公司门槛与角色要求取「且」（与 AuditionResolver 的口径一致）
func _required_acting(role: RoleRequirement) -> int:
	if _current == null or role == null:
		return 0
	return maxi(_current.acting_threshold, role.acting_required)


func _acting_ok(role: RoleRequirement) -> bool:
	return Game.acting() >= _required_acting(role)


func _on_role_toggled(on: bool, tier: int) -> void:
	if _syncing or not on or _current == null:
		return
	_role = _current.role_of(tier)
	_refresh_composer()


## 没选过 / 选的那个现在不够格 → 自动落在第一个够格的档位上。
## 【为什么要自动落】行动点只有 21 个，让玩家先选一个投出去一定不过的档位
## 是在骗他浪费一天。够格才给选，并且在按钮上写明要求。
func _auto_pick_role() -> void:
	if _current == null or _current.roles.is_empty():
		return
	if _role == null or not _acting_ok(_role):
		_role = null
		for role: RoleRequirement in _current.roles:
			if _acting_ok(role):
				_role = role
				break
	_syncing = true
	for tier: int in _role_buttons:
		var b: Button = _role_buttons[tier]
		b.disabled = not _acting_ok(_current.role_of(tier))
		b.button_pressed = (_role != null and tier == _role.tier)
	_syncing = false


# ============================================================
# 刷新
# ============================================================
func _refresh_all() -> void:
	_refresh_top()
	_refresh_contacts()
	_refresh_header()
	_refresh_composer()


func _refresh_top() -> void:
	_status_label.text = "第 %d 天 · 第 %d 周 ｜ 行动点 %d" % [
		Game.day(), Game.week(), Game.ap_left()]
	_channel_label.text = "本周还可投递 %d / %d 次 ｜ 演技 %d" % [
		Game.submissions_left_this_week(), GameState.MAX_SUBMIT_PER_WEEK, Game.acting()]
	# 【标题也要跟着会话换】事件会话不是「私聊 HR」—— 那时玩家读的是别人找上门说什么，
	# 副标题还写「发一段表情包过去 —— 这就是投递」就对不上了
	var in_event := _is_event_chat()
	_title.text = "找上门的人" if in_event else "私聊 HR"
	_subtitle.text = "回不回、怎么回，都在你" if in_event else "发一段表情包过去 —— 这就是投递"


func _refresh_contacts() -> void:
	# 事件那一段随周换人，每次都重建（最多四五条，代价可忽略）
	_refresh_event_contacts()
	for co: CompanyData in _companies:
		var unlocked := Game.is_hr_unlocked(co.code)
		var labels: Dictionary = _row_labels[co.code]
		var state: Label = labels["state"]
		var name_label: Label = labels["name"]
		state.text = "已私聊" if unlocked else "未解锁"
		state.add_theme_color_override("font_color",
				UiPalette.POSITIVE if unlocked else UiPalette.TEXT_DIM)
		name_label.add_theme_color_override("font_color",
				UiPalette.TEXT if unlocked else UiPalette.TEXT_DIM)
		var row: Button = _rows[co.code]
		row.add_theme_stylebox_override("normal",
				UiPalette.button(UiPalette.PANEL_SOFT if unlocked else Color("1c1c22"),
						UiPalette.LINE, 1, 14))
		row.add_theme_stylebox_override("hover",
				UiPalette.button(Color("35353f"), UiPalette.LINE, 2, 14))
		row.add_theme_stylebox_override("pressed",
				UiPalette.button(Color("3d3d26"), UiPalette.ACCENT, 3, 14, 3))
	var locked := 0
	for co: CompanyData in _companies:
		if not Game.is_hr_unlocked(co.code):
			locked += 1
	_contacts_hint.text = "灰色的还没解锁 —— 先在 Boss直聘 逛过那家公司的招聘页" if locked > 0 else "五家都聊上了"


func _refresh_header() -> void:
	if _is_event_chat():
		_refresh_event_header()
		return
	if _current == null:
		_peer_name.text = "还没选联系人"
		_peer_meta.text = "左边挑一个 HR 开始私聊"
		_requirement_label.text = "—"
		return
	var unlocked := Game.is_hr_unlocked(_current.code)
	_peer_name.text = "%s（%s）" % [_current.hr_name, _current.display_name]
	_peer_meta.text = "%s · %s" % [_current.hr_title, "已私聊" if unlocked else "还没解锁"]
	var lines: Array[String] = []
	lines.append("演技门槛 %d" % _current.acting_threshold)
	for role: RoleRequirement in _current.roles:
		lines.append("%s %.0f%%" % [role.tier_name(), role.match_line * 100.0])
	_requirement_label.text = "\n".join(lines)


## 发不出去的原因，按优先级给一条。空串 = 可以发。
func _block_reason() -> String:
	if _current == null:
		return "先在左边挑一个联系人"
	if not Game.is_hr_unlocked(_current.code):
		return "还没加上 %s 的 HR —— 点下面「去 Boss直聘」看它的招聘页" % _current.code
	if _pending == null:
		return "还没有表情包 —— 点「去录像机」拼一段 3 帧的"
	if _role == null:
		return "演技还不够这家公司的任何一个档位（现在 %d）" % Game.acting()
	if Game.submissions_left_this_week() <= 0:
		return "本周 %d 次投递已经用完了 —— 等周末结算翻篇" % GameState.MAX_SUBMIT_PER_WEEK
	if Game.ap_left() <= 0:
		return "今天的行动点已经用掉了"
	return ""


func _refresh_composer() -> void:
	# 【两套 composer，一次只露一套】HR 那套是「挑档位 + 附表情包 + 发送」，
	# 事件那套是「二选一」。两者没有共用部件，硬塞进一套就得在每处判分支，
	# 所以按会话类型直接显隐。
	var in_event := _is_event_chat()
	_role_row.visible = not in_event
	_attach_row.visible = not in_event
	_send_row.visible = not in_event
	_event_row.visible = in_event

	# 有子页面盖上来时，两个入口都别再点（避免叠两层 App）。
	# 事件会话里它们本来就无从下手，一并禁掉。
	var covered := _overlay != null
	_open_recorder_button.disabled = covered or in_event
	_go_boss_button.disabled = covered or in_event

	if in_event:
		_refresh_event_composer()
		return
	_refresh_hr_composer()


## HR 会话那套 composer
func _refresh_hr_composer() -> void:
	# 附件卡
	if _pending == null:
		_attach_title.text = "还没有表情包"
		_attach_title.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		_attach_detail.text = "点右边「去录像机」拼一段 3 帧的 —— 每投一次都要重新拼"
	else:
		_attach_title.text = "待投递：%s" % " → ".join(_pending.all_labels())
		_attach_title.add_theme_color_override("font_color", UiPalette.TEXT)
		_attach_detail.text = _pending.summarize()
	_attach_card.add_theme_stylebox_override("panel",
			UiPalette.panel(UiPalette.PANEL_SOFT, 14, 2,
					UiPalette.ACCENT if _pending != null else UiPalette.LINE))

	var reason := _block_reason()
	_send_button.disabled = reason != ""
	if reason.is_empty():
		_status_line.text = "可以发了 —— 消耗 %d 点行动点，本周还剩 %d 次" % [
			_current.ap_cost, Game.submissions_left_this_week()]
		_status_line.add_theme_color_override("font_color", UiPalette.POSITIVE)
	else:
		_status_line.text = reason
		_status_line.add_theme_color_override("font_color", UiPalette.ACCENT)


# ============================================================
# 事件 composer（二选一）
# ============================================================
## composer 里事件那一段是**脚本建的**：`wechat.tscn` 那份静态布局是给 HR 会话摆的，
## 往里加节点要动 .tscn；而这一段只有三个部件，脚本建更省事，
## 也和录像机 / 手机壳里那些动态部件同一个套路。
func _build_event_composer() -> void:
	var box := VBoxContainer.new()
	box.name = "EventRow"
	box.add_theme_constant_override("separation", 8)
	box.visible = false
	get_node(P_COMPOSER).add_child(box)
	_event_row = box

	# 【这里不放开场白】它已经在上面那条气泡里了 —— 同一句话在屏幕上下各出现一次
	# 只会让人以为有两件事。这一段的职责就是「给两个按钮 + 说清为什么不能点」。

	_event_buttons_row = HBoxContainer.new()
	_event_buttons_row.add_theme_constant_override("separation", 12)
	box.add_child(_event_buttons_row)
	for i in 2:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# 按钮里要放两行（选项名 + 代价收益），矮了会被裁
		b.custom_minimum_size = Vector2(0, 88)
		b.pressed.connect(_on_event_option.bind(i))
		b.add_theme_font_size_override("font_size", 20)
		b.add_theme_color_override("font_color", UiPalette.INK)
		b.add_theme_color_override("font_hover_color", UiPalette.INK)
		b.add_theme_color_override("font_pressed_color", UiPalette.INK)
		b.add_theme_stylebox_override("normal",
				UiPalette.button(UiPalette.EVENT, UiPalette.EVENT, 2, 14))
		b.add_theme_stylebox_override("hover",
				UiPalette.button(UiPalette.EVENT.lightened(0.12), UiPalette.EVENT, 3, 14))
		b.add_theme_stylebox_override("pressed",
				UiPalette.button(UiPalette.EVENT.darkened(0.15), UiPalette.EVENT, 3, 14))
		b.add_theme_stylebox_override("disabled",
				UiPalette.button(Color("2a2a30"), UiPalette.LINE, 1, 14))
		b.add_theme_color_override("font_disabled_color", Color("5a5a63"))
		_event_buttons_row.add_child(b)
		_event_buttons.append(b)

	_event_status = Label.new()
	_event_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.text(_event_status, 16, UiPalette.ACCENT)
	box.add_child(_event_status)


## 事件会话的头部。右边那块平时放「演技门槛 / 各档匹配线」，这里摆两个选项的
## 代价与收益 —— 玩家下决心之前要看的就是这个。
func _refresh_event_header() -> void:
	_peer_name.text = _speaker_name(_event_speaker)
	_peer_meta.text = "找你有点事"
	var ev := Game.pending_event()
	if ev == null or ev.speaker != _event_speaker:
		_requirement_label.text = "这条已经过去了"
		return
	var lines: Array[String] = []
	for o: EventOption in ev.options:
		lines.append("%s：%s" % [o.label, o.describe()])
	_requirement_label.text = "\n".join(lines)


func _refresh_event_composer() -> void:
	var ev := Game.pending_event()
	if ev == null or ev.speaker != _event_speaker:
		# 已经回过、或者整周没理会 —— 这段会话只剩读
		for b: Button in _event_buttons:
			b.visible = false
		_event_status.text = "这条已经过去了"
		_event_status.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		return

	# 【逐条给原因，而不是笼统说一句「不能选」】两个选项的代价不一样，
	# 被拦的理由也可能不一样（一个要行动点、另一个免费）
	var blocked: Array[String] = []
	for i in _event_buttons.size():
		var b: Button = _event_buttons[i]
		var o: EventOption = null
		if i < ev.options.size():
			o = ev.options[i]
		if o == null:
			b.visible = false
			continue
		b.visible = true
		b.text = "%s\n%s" % [o.label, o.describe()]
		var reason := Game.event_option_block_reason(i)
		b.disabled = reason != ""
		if not reason.is_empty():
			blocked.append("%s：%s" % [o.label, reason])
	if blocked.is_empty():
		_event_status.text = "选一个 —— 今天还剩 %d 点行动点" % Game.ap_left()
		_event_status.add_theme_color_override("font_color", UiPalette.POSITIVE)
	else:
		_event_status.text = "；".join(blocked)
		_event_status.add_theme_color_override("font_color", UiPalette.ACCENT)


## 在微信里回了一句。规则全在 `DailyActions.resolve_event`，
## 这里只负责重画 —— 聊天记录是**从状态重建**的，所以不必手工往日志里补气泡。
func _on_event_option(index: int) -> void:
	var r := Game.resolve_event(index)
	if not r.get("ok", false):
		_add_note("没能回话：" + String(r.get("reason", "")))
	_rebuild_chat()
	_refresh_all()
	_scroll_chat_to_bottom()


# ============================================================
# 聊天记录
# ============================================================
func _rebuild_chat() -> void:
	for child in _chat_log.get_children():
		child.queue_free()
	if _is_event_chat():
		_rebuild_event_chat()
		return
	if _current == null:
		_add_note("还没有联系人 —— 点下面「去 Boss直聘」看一家公司的招聘页，就能加上它的 HR")
		return

	var unlocked := Game.is_hr_unlocked(_current.code)
	if not unlocked:
		_add_note("你还没在 Boss直聘 上看过 %s 的招聘页，微信里加不上这位 HR" % _current.code)
		return

	# 口味线索：隐藏公式下的学习通道。**正本在 Boss直聘 的招聘页上**
	# （进过那页才解锁了这家 HR，所以这里不会提前泄底）；
	# 这里复述一条是**便利**，不是新增信息 —— 拼表情包时不用来回切 App。
	_add_note("这家的偏好：" + _current.hint)

	var found := 0
	for entry: Dictionary in Game.state.history:
		if String(entry.get("company_code", "")) != _current.code:
			continue
		found += 1
		_add_entry_bubbles(entry)
	if found == 0:
		_add_note("还没有投过 %s —— 拼好表情包就能发第一条" % _current.display_name)


## 把履历里的一条投递还原成「玩家气泡 + HR 回信」
func _add_entry_bubbles(entry: Dictionary) -> void:
	var labels: Array = entry.get("labels", [])
	_add_bubble("【投递】《%s》· %s\n表情包：%s" % [
		entry.get("play_title", "?"),
		RoleRequirement.TIER_NAMES.get(int(entry.get("role_tier", 0)), "?"),
		" → ".join(labels) if not labels.is_empty() else "—",
	], true, Color(0, 0, 0, 0))

	var mail: Dictionary = entry.get("mail", {})
	if mail.is_empty():
		_add_note("（这封回信是早期版本投的，没存下来）")
		return
	var passed: bool = entry.get("passed", false)
	_add_bubble(String(mail.get("text", "")), false,
			UiPalette.POSITIVE if passed else UiPalette.DANGER)


## 事件会话的聊天记录。
##
## 【为什么文案是现查的，不是存进履历的】履历只记「选了第几个选项」，
## 文案回头从 `EventLibrary` 里取 —— 于是狗牙改一遍文案（他一定会改），
## 所有历史会话跟着更新，不用迁移任何存档。
func _rebuild_event_chat() -> void:
	_add_note("你和「%s」的聊天" % _speaker_name(_event_speaker))

	var found := 0
	for h: Dictionary in Game.state.event_history:
		if StringName(h.get("speaker", "")) != _event_speaker:
			continue
		found += 1
		_add_event_entry(h)

	# 这周还没回的那条，把话摆在这儿等着
	var ev := Game.pending_event()
	if ev != null and ev.speaker == _event_speaker:
		_add_bubble(ev.intro, false, UiPalette.EVENT)
		_add_note("（在下面回一句）")
		return

	if found == 0:
		_add_note("还没有聊过")


## 把履历里的一条事件还原成「他说的 → 我回的 → 他回的」
func _add_event_entry(h: Dictionary) -> void:
	var ev := EventLibrary.find(StringName(h.get("event", "")))
	if ev == null:
		# 事件被删掉、或代号被改过：存档里那条就取不到内容了。
		# 明说一句，而不是留一段空白让玩家以为界面坏了
		_add_note("（这条事件的内容已经改过，读不出来了）")
		return
	_add_bubble(ev.intro, false, UiPalette.EVENT)
	var choice := int(h.get("choice", -1))
	if choice < 0:
		_add_note("（这周没理会）")
		return
	if choice >= ev.options.size():
		return
	_add_bubble(String(ev.options[choice].label), true, Color(0, 0, 0, 0))
	_add_bubble(String(ev.options[choice].reply), false, UiPalette.POSITIVE)


func _add_bubble(text: String, mine: bool, border: Color) -> void:
	var row := HBoxContainer.new()
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var card := PanelContainer.new()
	# 固定宽度而不是自适应：气泡宽度随文字长短抖动会显得很毛躁，
	# 而且固定宽度才能保证左右对齐看起来是「一列」
	card.custom_minimum_size = Vector2(BUBBLE_WIDTH, 0)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	card.add_child(margin)

	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", UiPalette.TEXT)
	margin.add_child(label)

	card.add_theme_stylebox_override("panel", UiPalette.panel(
			UiPalette.CHAT_SELF if mine else UiPalette.PANEL, 16, 2,
			border if border.a > 0.0 else (UiPalette.ACCENT if mine else UiPalette.LINE)))

	if mine:
		row.add_child(spacer)
		row.add_child(card)
	else:
		row.add_child(card)
		row.add_child(spacer)
	_chat_log.add_child(row)


## 系统提示（居中、暗色、小字）—— 不装成任何人说的话
func _add_note(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	_chat_log.add_child(label)


func _scroll_chat_to_bottom() -> void:
	# 等一帧让容器算完高度，否则拿到的是旧 max_value，滚不到底
	await get_tree().process_frame
	_chat_scroll.scroll_vertical = int(_chat_scroll.get_v_scroll_bar().max_value)


# ============================================================
# 发送 = 投递
# ============================================================
func _on_send() -> void:
	if _block_reason() != "":
		_refresh_composer()
		return
	var res := Game.submit_audition(_pending, _current, _role)

	if res.get("rejected", false):
		# 机械性被拦（次数/行动点/不完整），不是判定失败 —— 这类原因可以明说
		_add_note("没发出去：" + "；".join(res.get("fail_reasons", [])))
		_scroll_chat_to_bottom()
		_refresh_all()
		return

	var labels: Array = _pending.all_labels()
	_add_bubble("【投递】《%s》· %s\n表情包：%s" % [
		res.get("casting", {}).get("剧名", "?"),
		RoleRequirement.TIER_NAMES.get(int(res.get("role_tier", 0)), "?"),
		" → ".join(labels),
	], true, Color(0, 0, 0, 0))

	var mail: Dictionary = res.get("mail", {})
	_add_bubble(String(mail.get("text", "")), false,
			UiPalette.POSITIVE if res.get("passed", false) else UiPalette.DANGER)

	# 表情包一次性消耗（决策 1.6）：投出去就没了，下次必须重新拼
	_pending = null
	_refresh_all()
	_scroll_chat_to_bottom()


# ============================================================
# 子页面（录像机 / Boss直聘）
# ============================================================
## 真机上这两个 App 由手机壳切换。手机壳还没做，所以先内嵌打开。
##
## 【这不是"又一个开发脚手架"】上个版本这里是一个 `DEV_UNLOCK_ALL` 开关，
## 直接把「先逛 Boss直聘 才解锁 HR」短路掉了。现在换成真的能打开 Boss直聘 ——
## 于是这条规则**真的会生效**：从零解锁一家公司、再投出去，全程没有作弊开关。
## 让调用方把本页当 App 打开时显示「返回桌面」（见 phone_shell.gd）
func enable_back() -> void:
	_back_button.visible = true


func _open_overlay(scene_path: String) -> Node:
	if _overlay != null:
		return null
	_overlay = load(scene_path).instantiate()
	add_child(_overlay)
	if _overlay.has_method("enable_back"):
		_overlay.enable_back()
	if _overlay.has_signal("cancelled"):
		_overlay.connect("cancelled", _close_overlay)
	_refresh_composer()
	return _overlay


func _close_overlay() -> void:
	if _overlay != null:
		if _overlay.is_connected("cancelled", _close_overlay):
			_overlay.disconnect("cancelled", _close_overlay)
		_overlay.queue_free()
		_overlay = null
	if EventBus.recorder_finished.is_connected(_on_clip_ready):
		EventBus.recorder_finished.disconnect(_on_clip_ready)
	_refresh_composer()


func _on_open_recorder() -> void:
	if _open_overlay(RECORDER_SCENE) == null:
		return
	# 只在这时候订阅：录像机点「确认」才会 emit，平时挂着没意义
	EventBus.recorder_finished.connect(_on_clip_ready)


func _on_open_boss() -> void:
	var boss := _open_overlay(BOSS_SCENE)
	if boss != null:
		_add_note("去看看谁在招人 —— 加上的 HR 会直接出现在左边的联系人里")
		_scroll_chat_to_bottom()


## 录像机点「确认」→ 拿到待投递的表情包，关掉子页面
func _on_clip_ready(clip: Clip) -> void:
	_pending = clip
	_close_overlay()
	_add_note("录好了一段表情包，选好角色就能发给 %s" % _current.hr_name)
	_scroll_chat_to_bottom()


# ============================================================
# 信号
# ============================================================
func _on_hr_unlocked(code: String) -> void:
	_refresh_contacts()
	if _current == null:
		# 从 Boss直聘 回来时本来没选中任何人 —— 直接把刚加上的这位打开
		_select_company(code)
	else:
		_refresh_header()
		_refresh_composer()


## 周初排定了一个事件 —— 直接把那条会话打开，别让玩家在一列人里自己找谁找他。
## 【什么时候会走到这里】每周第一天，由 `Game._roll_week_event()` 发出。
## 手机壳开着的 App 不会被记住，所以正常情况下这行是兜底；
## 但「事件必须在周初被看见」是 GDD 阶段 1 的要求，这条线不能断。
func _on_week_event_offered(event_id: StringName) -> void:
	var ev := EventLibrary.find(event_id)
	if ev == null:
		return
	_select_event_speaker(ev.speaker)


func _on_week_event_resolved(_event_id: StringName, _index: int) -> void:
	_refresh_contacts()


func _on_ap_changed(_left: int) -> void:
	_refresh_top()
	_refresh_composer()


## 状态被整个换掉（开新局 / 读档）：选中联系人、待投递表情包、子页面 —— 一样都不能留
func _on_state_reset() -> void:
	_close_overlay()
	_current = null
	_pending = null
	_role = null
	_event_speaker = &""
	for child in _role_buttons_row.get_children():
		child.queue_free()
	_role_buttons.clear()
	_syncing = true
	for c: String in _rows:
		(_rows[c] as Button).button_pressed = false
	_syncing = false
	_refresh_all()
	_rebuild_chat()

	# 【清完再看有没有人在等】开新局与读档都会走到这里（读档时**不会**有
	# `week_event_offered` 那条信号，因为那个事件是存档里就带着的）。
	# 放在最后：上面的 _refresh_all 已经把事件那一段重建好了，
	# 这时候选中才有对应的行可以按下去。
	var waiting := Game.pending_event()
	if waiting != null and not waiting.speaker.is_empty():
		_select_event_speaker(waiting.speaker)


# ============================================================
# 样式
# ============================================================
func _apply_styles() -> void:
	get_node("Bg").color = UiPalette.BG

	var top_sb := StyleBoxFlat.new()
	top_sb.bg_color = UiPalette.PANEL
	top_sb.border_width_bottom = 3
	top_sb.border_color = UiPalette.WECHAT
	get_node("Page/TopBar").add_theme_stylebox_override("panel", top_sb)

	_node_panel(get_node("Page/BodyWrap/Body/ContactsPanel"), UiPalette.PANEL, 20, 2, UiPalette.LINE)
	_node_panel(get_node("Page/BodyWrap/Body/ChatPanel"), UiPalette.PANEL, 20, 2, UiPalette.LINE)
	_node_panel(get_node(P_CHAT + "/ChatHeader"), UiPalette.PANEL_SOFT, 16, 0)
	_node_panel(get_node(P_CHAT + "/Composer"), UiPalette.PANEL_SOFT, 18, 2, UiPalette.LINE)

	var chip := StyleBoxFlat.new()
	chip.bg_color = UiPalette.WECHAT
	chip.set_corner_radius_all(12)
	get_node(P_TOP + "/BrandRow/BrandChip").add_theme_stylebox_override("panel", chip)

	UiPalette.text(get_node(P_TOP + "/BrandRow/BrandText"), 26, UiPalette.WECHAT)
	UiPalette.text(_title, 40, UiPalette.TEXT)
	UiPalette.text(_subtitle, 15, UiPalette.TEXT_DIM)
	UiPalette.text(_status_label, 20, UiPalette.ACCENT)
	UiPalette.text(_channel_label, 15, UiPalette.TEXT_DIM)

	UiPalette.text(get_node(P_CONTACTS + "/ContactsCaption"), 22, UiPalette.TEXT)
	UiPalette.text(_contacts_hint, 14, UiPalette.TEXT_DIM)
	# 联系人列表里那两行分组标题（事件在上、公司在下）
	UiPalette.text(_event_caption, 16, UiPalette.EVENT)
	UiPalette.text(_hr_caption, 16, UiPalette.TEXT_DIM)

	UiPalette.text(_peer_name, 24, UiPalette.TEXT)
	UiPalette.text(_peer_meta, 15, UiPalette.TEXT_DIM)
	UiPalette.text(_requirement_label, 16, UiPalette.ACCENT)

	UiPalette.text(get_node(P_COMPOSER + "/RoleRow/RoleCaption"), 16, UiPalette.TEXT_DIM)
	UiPalette.text(_attach_title, 20, UiPalette.TEXT)
	UiPalette.text(_attach_detail, 15, UiPalette.TEXT_DIM)
	UiPalette.text(_status_line, 16, UiPalette.ACCENT)

	_style_action(_back_button, UiPalette.PANEL_SOFT, UiPalette.TEXT, UiPalette.LINE, 20)
	_style_action(_go_boss_button, UiPalette.PANEL_SOFT, UiPalette.TEXT, UiPalette.ACCENT, 18)
	_style_action(_open_recorder_button, UiPalette.PANEL_SOFT, UiPalette.TEXT, UiPalette.LINE, 20)
	_style_action(_send_button, UiPalette.ACCENT, UiPalette.INK, UiPalette.ACCENT, 24)
	_send_button.add_theme_stylebox_override("disabled",
			UiPalette.button(Color("2a2a30"), UiPalette.LINE, 1, 14))
	_send_button.add_theme_color_override("font_disabled_color", Color("5a5a63"))

	# 滚动条（联系人 + 聊天）
	for bar: VScrollBar in [
			_contact_list.get_parent().get_v_scroll_bar(),
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
