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
## 气泡最宽到这里，超了就折行。**短消息按文字实际宽度收窄** ——
## 真微信里「好」就是一个贴着边的窄条，全都拉成一样宽看着像公告栏，不像聊天
const BUBBLE_MAX_W := 720.0
const BUBBLE_FONT := 18
const CONTACT_AVATAR := 54
## 气泡旁的头像。比名单上的小一号 —— 它是「谁在说话」的标记，不是可点的行
const CHAT_AVATAR := 40.0
## 自己那一侧的头像字。**与「简历拿来」里的自己用同一个标记**：
## 同一台手机上的同一个人，名片该长得一样
const ME_MARK := "你"

## 被手机壳当成一个 App 打开时才需要返回。独立运行时它是主场景，没有"上一步"。
signal cancelled

## 请求上层换一个 App —— 「去简历拿来」与「去录像机」都是**整屏切过去**，
## 不是把对方塞进右栏。约定与 `boss_app.gd` 相同：本 App 只发一个场景路径，
## 切屏是手机屏的事（它才管着左栏与周围那圈颜色，见 `phone_screen.gd`）。
signal open_app_requested(scene_path: String)

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

	# 【拼好的表情包从状态里取，不从「上次那个实例」取】点「去录像机」会整屏切走，
	# 本 App 随之被手机屏销毁 —— 那段表情包只有存在 `GameState` 里才活得下来。
	_pending = Game.pending_clip()

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

	# 【先看「刚才在聊谁」】去录像机录完回来、去「简历拿来」加完人回来，都会把本 App
	# 重建一遍。落到「第一家已解锁的」而不是他刚才那位，玩家会以为自己点错了。
	var want := Game.focus_hr()
	if not want.is_empty() and Game.is_hr_unlocked(want):
		_select_company(want)
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


## **本周正等着回话**的那个人（没有就空）。
##
## 【它不再等于「名单上有谁」】名单现在把出现过的都留着（见 `_event_speakers`），
## 这个函数回答的是另一个问题：谁那儿还有事没办。名单上那一格「等你回话」、
## 以及底下那排二选一按钮都看它。
## 事情本身另有记录 —— `Game.state.event_history` 存着全过程，电子报与结局都读它。
func _pending_speaker() -> StringName:
	var ev := Game.pending_event()
	if ev != null and not ev.speaker.is_empty():
		return ev.speaker
	return &""


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


## 名单上有哪些人：**出现过的都留着**，包括已经回过的。
##
## 【为什么改】原来只留「正等着回话的那一个」—— 回完话那人就从名单上消失，
## 玩家想回头看那天的对话就找不到了（提提点名）。名单是「你和谁聊过」的记录，
## 不是待办清单：待办从「等你回话」那一格的字上看。
## 正等着的那位排在最前 —— 他才是今天要处理的事。
func _event_speakers() -> Array[StringName]:
	var out: Array[StringName] = []
	var sp := _pending_speaker()
	if sp != &"":
		out.append(sp)
	for h: Dictionary in Game.state.event_history:
		var who := StringName(h.get("speaker", ""))
		if who != &"" and not out.has(who):
			out.append(who)
	return out


## 这个人在名单上的状态字（行上那一格总得有字）
func _speaker_state(speaker: StringName) -> String:
	if speaker == _pending_speaker():
		return "等你回话"
	# 回过的写结果：多数是「已回过」，整周没理会的写「没理会」。
	# 【为什么倒着找】同一个人可能被找上门不止一次，要看的是**最近**那一次
	for i in range(Game.state.event_history.size() - 1, -1, -1):
		var h: Dictionary = Game.state.event_history[i]
		if StringName(h.get("speaker", "")) != speaker:
			continue
		return "没理会" if int(h.get("choice", -1)) < 0 else "已回过"
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
	for sp: StringName in _event_speakers():
		var row := _make_event_row(sp)
		row.button_group = _contact_group
		row.toggled.connect(_on_event_toggled.bind(sp))
		row.button_pressed = (sp == _event_speaker)
		_event_box.add_child(row)
		_event_rows[sp] = row
	_syncing = false

	# 一个人都没有的时候，那两行标题也别挂着
	var any_events := not _event_rows.is_empty()
	_event_caption.visible = any_events
	_event_box.visible = any_events
	# 【故意不在这里清 `_event_speaker`】刚回完话那一刻，玩家正看着那条会话 ——
	# 清了会把他从刚回完的对话里弹出去。该清的地方是开新局 / 读档（`_on_state_reset`）
	# 与切回 HR（`_select_company`）。


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
	# 记进状态：本 App 被切走再建起来时，要落在同一位联系人上（见 `_ready`）
	Game.set_focus_hr(code)
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
				UiPalette.button(Color("35353f"), UiPalette.WECHAT, 2, 12, 0, 8))
		b.add_theme_stylebox_override("pressed",
				UiPalette.button(UiPalette.WECHAT, UiPalette.WECHAT, 2, 12, 3, 8))
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
	var locked := 0
	for co: CompanyData in _companies:
		var unlocked := Game.is_hr_unlocked(co.code)
		if not unlocked:
			locked += 1
		var labels: Dictionary = _row_labels[co.code]
		(labels["state"] as Label).text = "已私聊"
		(labels["name"] as Label).add_theme_color_override("font_color", UiPalette.TEXT)
		var row: Button = _rows[co.code]
		# 【没加上的不摆出来】五家灰着一排占满名单，玩家会以为「这些人已经在我微信里了」——
		# 名单上只该有**真的加上了的**（提提点名）。去哪儿加人写在下面那行提示里。
		row.visible = unlocked
		row.add_theme_stylebox_override("normal",
				UiPalette.button(UiPalette.PANEL_SOFT, UiPalette.LINE, 1, 14))
		row.add_theme_stylebox_override("hover",
				UiPalette.button(Color("35353f"), UiPalette.LINE, 2, 14))
		row.add_theme_stylebox_override("pressed",
				UiPalette.button(UiPalette.WECHAT.darkened(0.6), UiPalette.WECHAT, 3, 14, 3))

	# 【措辞跟着改】灰行已经不显示了，再说「灰色的还没解锁」就指不到东西
	var added := _companies.size() - locked
	_hr_caption.visible = added > 0
	if locked <= 0:
		_contacts_hint.text = "五家都聊上了"
	elif added == 0:
		_contacts_hint.text = "还没加上 HR —— 去「简历拿来」逛一家公司的招聘页"
	else:
		_contacts_hint.text = "还有 %d 家没加上 —— 去「简历拿来」逛他们的招聘页" % locked


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
		return "还没加上 %s 的 HR —— 点下面「简历拿来」看它的招聘页" % _current.code
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

	# 事件会话里这两个入口本来就无从下手（没有 HR 会话可投），禁掉。
	# 【不再需要「有子页面盖着」那一档】跳到录像机 / 简历拿来 现在会整屏切走，
	# 本 App 连同这两个按钮一起被销毁 —— 不存在「两边同时开着」的状态了。
	_open_recorder_button.disabled = in_event
	_go_boss_button.disabled = in_event

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
					UiPalette.WECHAT if _pending != null else UiPalette.LINE))

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
	# 【事件那一段有它自己的色】用它的青（`EVENT`），不是 App 的品牌绿 ——
	# 找上门的人不是「微信自己」，和 HR 那一套分开看
	UiPalette.text(_event_status, 16, UiPalette.EVENT)
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
		_add_note("还没有联系人 —— 点下面「简历拿来」看一家公司的招聘页，就能加上它的 HR")
		return

	var unlocked := Game.is_hr_unlocked(_current.code)
	if not unlocked:
		_add_note("你还没在简历拿来看过 %s 的招聘页，微信里加不上这位 HR" % _current.code)
		return

	# 【加上了就先互相报名字】「简历拿来」那一步是「跟 HR 说上话才拿到联系方式」，
	# 所以微信里这段记录该从「我是谁」开始，而不是一上来只有系统提示。
	# 这两句是**从既有数据拼的**（公司名与 HR 名在 `CompanyData`，主角名读内容池），
	# 所以不用往存档里多存一份 —— 每次重建都对得上。
	_add_bubble("我是%s的%s" % [_current.display_name, _current.hr_name], false)
	_add_bubble("我是%s" % _player_name(), true)

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


## 主角的名字。**单一来源是内容池**（`data/casting_pool.tres` 的 `player_name`）——
## 邮件里的【玩家名】、电子报直呼其名、这里微信里的自我介绍，读的都是它。
## 【为什么不自己造一个占位】同一个名字要在三处显示，各存一份必然对不上；
## 而且「开一局自己取名字」是**往后要加的功能**（见 `进度.md` 待办），
## 到那天要改的是「名字从哪儿来」这一件事，不是三个界面。
func _player_name() -> String:
	var pool := MailLibrary.casting_pool()
	var who := pool.player_name if pool != null else ""
	return who if not who.strip_edges().is_empty() else "我"


## 把履历里的一条投递还原成「玩家气泡 + HR 回信」
func _add_entry_bubbles(entry: Dictionary) -> void:
	var labels: Array = entry.get("labels", [])
	_add_bubble("【投递】《%s》· %s\n表情包：%s" % [
		entry.get("play_title", "?"),
		RoleRequirement.TIER_NAMES.get(int(entry.get("role_tier", 0)), "?"),
		" → ".join(labels) if not labels.is_empty() else "—",
	], true)

	var mail: Dictionary = entry.get("mail", {})
	if mail.is_empty():
		_add_note("（这封回信是早期版本投的，没存下来）")
		return
	_add_bubble(String(mail.get("text", "")), false)


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
		_add_bubble(ev.intro, false)
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
	_add_bubble(ev.intro, false)
	var choice := int(h.get("choice", -1))
	if choice < 0:
		_add_note("（这周没理会）")
		return
	if choice >= ev.options.size():
		return
	_add_bubble(String(ev.options[choice].label), true)
	_add_bubble(String(ev.options[choice].reply), false)


## 一条气泡：**对方在左（灰底）、自己在右（微信绿底）**，两边各带头像。
##
## 【为什么不再按内容上色】原来这条会按「回信成没成」（绿/红）和「哪条会话」（事件的青）
## 换描边色 —— 同一个聊天里于是并着四五种颜色，提提点名的就是这个。
## 现在两种颜色管到底：别人的话一律灰、自己的话一律绿（真微信也是这么分的），
## 成败与是非从信里的字看，不靠颜色猜。
func _add_bubble(text: String, mine: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	# 【一行的顺序就是左右】对方那侧：[头像][气泡][撑开的空控件] → 贴在左边；
	# 自己这侧：[撑开的空控件][气泡][头像] → **顶到右边**，头像贴着屏幕边。
	# 【两个坑都踩过】(1) 把头像统一挂在气泡后面 → 对方的头像跑到自己气泡右边；
	# (2) 把撑开的那个控件一律挂在行尾 → 自己的气泡被推到左边，
	# 看着就是「右边没靠边」（提提 10-16 拿真微信的截图点出来的）。
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if mine:
		row.add_child(spacer)
	else:
		row.add_child(_bubble_avatar(false))

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	card.add_child(margin)

	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", BUBBLE_FONT)
	# 【为什么要自己算宽度】autowrap 打开之后，Label 的最小宽度会塌成几个字，
	# 短句子会被压成一条竖条。按文字实际宽度给个下限，才能既收窄又折行
	# （「简历拿来」那条气泡同一个道理）。
	label.custom_minimum_size = Vector2(_bubble_width(text), 0)
	# 压在品牌绿上的字要用深色（`INK`）：绿底白字发虚，这也是真微信的做法
	label.add_theme_color_override("font_color",
			UiPalette.INK if mine else UiPalette.TEXT)
	margin.add_child(label)

	var bg := UiPalette.WECHAT if mine else UiPalette.PANEL_SOFT
	card.add_theme_stylebox_override("panel", UiPalette.panel(bg, 16, 2,
			UiPalette.WECHAT.lightened(0.18) if mine else UiPalette.LINE))

	# 【气泡本身一定要进来】上面那一支只放了头像，货在这儿 ——
	# 漏了它就是「左边只有个头像、话不见了」（这一版踩过）。
	row.add_child(card)
	if mine:
		row.add_child(_bubble_avatar(true))
	else:
		row.add_child(spacer)
	_chat_log.add_child(row)


## 气泡宽度：按文字实际宽度算（超了 `BUBBLE_MAX_W` 就在那儿折行）。
##
## 【为什么按行取最大】正文里有换行（投递回执、回信正文都是多行的），
## 直接量整串会把所有行当成一行加起来，于是每条都顶到最宽 —— 短消息就又变成通栏了。
func _bubble_width(text: String) -> float:
	var font := ThemeDB.fallback_font
	var w := 0.0
	for line: String in text.split("\n"):
		w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, BUBBLE_FONT).x)
	return minf(BUBBLE_MAX_W, w + 6.0)


## 气泡旁的头像。和左栏联系人用同一套「色块 + 字」的道理：
## - 对方的：这家的**档位色 + 代号**（和名单上那个头像同一个记号，一眼对得上是哪家）
## - 自己的：**品牌绿 + 「你」**
## - 事件会话里的对方：事件专用的青 + 名字首字（和名单上那排同一个记号）
func _bubble_avatar(mine: bool) -> Panel:
	var avatar := Panel.new()
	avatar.custom_minimum_size = Vector2(CHAT_AVATAR, CHAT_AVATAR)
	# 头像贴着气泡顶端，不跟着气泡一起被拉高（长邮件会拉得很长）
	avatar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := UiPalette.WECHAT
	var mark := ME_MARK
	if not mine:
		if _current != null:
			bg = TIER_COLORS.get(_current.tier, UiPalette.LINE)
			mark = _current.code
		else:
			bg = UiPalette.EVENT
			mark = _speaker_name(_event_speaker).substr(0, 1)
	# 圆角方块（不是圆形）：左栏名单里那个头像是同一套形状，只是大一号
	avatar.add_theme_stylebox_override("panel", UiPalette.rounded(bg, 10))

	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = mark
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", UiPalette.INK)
	avatar.add_child(label)
	return avatar


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
	], true)

	var mail: Dictionary = res.get("mail", {})
	_add_bubble(String(mail.get("text", "")), false)

	# 表情包一次性消耗（决策 1.6）：投出去就没了，下次必须重新拼
	_pending = null
	Game.clear_pending_clip()
	_refresh_all()
	_scroll_chat_to_bottom()


# ============================================================
# 去别的 App（整屏切走，不是嵌进右栏）
# ============================================================
## 让调用方把本页当 App 打开时显示「返回桌面」（见 phone_screen.gd）
func enable_back() -> void:
	_back_button.visible = true


## 手机屏把左栏让出来时，本 App 交出自己的**联系人列表**（改版：
## 左栏从「App 列表」换成「当前 App 的二级列表」，微信这一列就是联系人）。
##
## 【为什么可以直接把它搬走】本类的引用都在 `@onready` 里抓好了（`_contact_list`
## 那些），`@onready` 在 `_ready()` 就执行完 —— 所以**只要等本场景进了树**再搬，
## 引用依然有效，绝对路径不再被用到。手机屏那边就是先 `add_child` 再问的。
## 反过来说：搬走之后 `_apply_styles()` 里的 `get_node(P_CONTACTS + ...)` 会失效，
## 所以本方法只该在 `_ready()` 之后被调用（手机屏不会在建树期间调它）。
func take_sidebar() -> Control:
	return get_node("Page/BodyWrap/Body/ContactsPanel")


func sidebar_title() -> String:
	return "微信 · 联系人"


## 「去录像机」拼一段表情包。
##
## 【这一版为什么改成整屏切走】原来是把录像机**内嵌在右栏**（手机壳做出来之前的
## 权宜之计）：同一台手机上于是有了两套导航（外面一层 App 列表、里面一层子页面），
## 而录像机还得挤在 1065 宽的一块里。现在由手机屏换 App —— 左栏跟着变成录像机自己
## 那一列，周围那圈颜色也换过去。
##
## 【代价：本 App 会被销毁】所以「拼好的表情包」与「在聊谁」都在状态层
## （`Game.pending_clip` / `Game.focus_hr`），回来时 `_ready()` 自己取。
## 录完的回程由手机屏负责（它记着是谁顶开的），见 `phone_screen._on_recorder_finished`。
func _on_open_recorder() -> void:
	open_app_requested.emit(RECORDER_SCENE)


## 「去简历拿来」加联系人。那边聊完会有一条「去微信聊」，回程由它自己发；
## 刚加上的那位由 `Game.unlock_hr()` 记进 `focus_hr`，回来时直接就是这条会话。
func _on_open_boss() -> void:
	open_app_requested.emit(BOSS_SCENE)


# ============================================================
# 信号
# ============================================================
## 某家公司的 HR 刚被加上。
## 【主干路径现在已经不经过这里了】「去简历拿来」是整屏切走，加人时本 App 并不在场 ——
## 「回来直接打开刚加上的那位」改由 `GameState.focus_hr` 完成（见 `_ready`）。
## 这条留着是因为本 App 开着的时候也可能解锁（比如以后从别处解锁、或测试里直接调）。
func _on_hr_unlocked(code: String) -> void:
	_refresh_contacts()
	if _current == null:
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


## 状态被整个换掉（开新局 / 读档）：选中联系人、待投递表情包 —— 一样都不能留。
## 【表情包跟着状态走】开新局时它是空的；读档时它是存档里那一段 —— 两者都是状态说了算，
## 所以这里不是「清成 null」，而是「重新问状态要一次」。
func _on_state_reset() -> void:
	_current = null
	_pending = Game.pending_clip()
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
	# 【顶上两个角要圆】右栏底图是圆角 20，顶栏直角会从圆角外露出尖角
	top_sb.corner_radius_top_left = 20
	top_sb.corner_radius_top_right = 20
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
	UiPalette.text(_status_label, 20, UiPalette.WECHAT)
	UiPalette.text(_channel_label, 15, UiPalette.TEXT_DIM)

	UiPalette.text(get_node(P_CONTACTS + "/ContactsCaption"), 22, UiPalette.TEXT)
	UiPalette.text(_contacts_hint, 14, UiPalette.TEXT_DIM)
	# 联系人列表里那两行分组标题（事件在上、公司在下）
	UiPalette.text(_event_caption, 16, UiPalette.EVENT)
	UiPalette.text(_hr_caption, 16, UiPalette.TEXT_DIM)

	UiPalette.text(_peer_name, 24, UiPalette.TEXT)
	UiPalette.text(_peer_meta, 15, UiPalette.TEXT_DIM)
	UiPalette.text(_requirement_label, 16, UiPalette.WECHAT)

	UiPalette.text(get_node(P_COMPOSER + "/RoleRow/RoleCaption"), 16, UiPalette.TEXT_DIM)
	UiPalette.text(_attach_title, 20, UiPalette.TEXT)
	UiPalette.text(_attach_detail, 15, UiPalette.TEXT_DIM)
	UiPalette.text(_status_line, 16, UiPalette.WECHAT)

	_style_action(_back_button, UiPalette.PANEL_SOFT, UiPalette.TEXT, UiPalette.LINE, 20)
	_style_action(_go_boss_button, UiPalette.PANEL_SOFT, UiPalette.TEXT, UiPalette.WECHAT, 18)
	_style_action(_open_recorder_button, UiPalette.PANEL_SOFT, UiPalette.TEXT, UiPalette.LINE, 20)
	_style_action(_send_button, UiPalette.WECHAT, UiPalette.INK, UiPalette.WECHAT, 24)
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
		bar.add_theme_stylebox_override("grabber_highlight", UiPalette.rounded(UiPalette.WECHAT, 5))


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
