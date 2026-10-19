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
## 剧本页 —— 盖在**聊天区**上的一层（不是第三栏，也不是独立的 App）。
## 它在 `BodyWrap` 里排在 `Body` 后面，所以天然画在聊天之上；关掉它还回原来的聊天记录。
const P_SCRIPT := "Page/BodyWrap/ScriptOverlay"
const P_SCRIPT_SHEET := P_SCRIPT + "/ScriptMargin/ScriptBox"

const RECORDER_SCENE := "res://scenes/minigame/recorder.tscn"
const BOSS_SCENE := "res://scenes/apps/boss.tscn"
## 气泡最宽到这里，超了就折行。**短消息按文字实际宽度收窄** ——
## 真微信里「好」就是一个贴着边的窄条，全都拉成一样宽看着像公告栏，不像聊天
const BUBBLE_MAX_W := 720.0
const BUBBLE_FONT := 18

## ---- 「对方正在输入…」 ----
## 【为什么要这段假等待】判定与回信在核心层是**同一帧**出的（`Game.submit_audition`
## 连着发 `audition_submitted` / `hr_replied`），于是点下发送的瞬间，回信就"秒回"砸在
## 脸上 —— 读起来不像聊天，像在查表。这里只推迟**显示**：状态里那条回信早就写好了，
## 中途切去别的 App 再回来会直接看到它（不存在"回信丢了"）。
##
## 时长按字数走：短的一句"好"不能也等四秒，长的回信也不能一闪而过。
const TYPING_BASE := 0.9
const TYPING_PER_CHAR := 0.035
const TYPING_MAX := 4.5
## 三个点之间的错峰（秒）。纯装饰，别调太大 —— 大了像"正在加载"
const TYPING_STAGGER := 0.16
## 头一回点开会话时，那两句自我介绍之前的「正在输入」时长。
## 【为什么不复用 `_typing_seconds`】打招呼没有正文可量字数，也不该按回信那套
## 0.9~4.5 秒 —— 玩家刚点开，一秒出头刚好。
const WELCOME_TYPING := 1.2
const CONTACT_AVATAR := 54
## 气泡旁的头像。比名单上的小一号 —— 它是「谁在说话」的标记，不是可点的行
const CHAT_AVATAR := 40.0
## 自己那一侧的头像字。**与「简历拿来」里的自己用同一个标记**：
## 同一台手机上的同一个人，名片该长得一样
const ME_MARK := "你"

## ---- 文件卡（HR 发的那份 .docx）的留白 ----
## 【为什么要写成常量】Button 不是容器：子节点只按锚点摆，**不会**自动让开
## stylebox 的 content_margin。只给锚点的话图标就贴着卡片左边缘，得显式给留白。
const CARD_PAD := 20
const CARD_PAD_V := 14

## ---- HR 发剧本那三句文案（**占位 · 狗牙**）----
## 【为什么不进存档】和事件会话的 intro / reply 同一个做法：存档只记「谁、哪一档、哪份剧本」，
## 话怎么说是现取现拼的 —— 狗牙改一遍文案，所有历史会话跟着更新，不用迁移存档。
const ASK_SCRIPT := "这部戏你想试哪类角色？龙套、配角、主角各有一份剧本。"
const PICK_SCRIPT := "我想试%s。"
const OFFER_SCRIPT := "这是《%s》的%s剧本，你先看看。"
const REPLY_SCRIPT := "好，我先看剧本。"

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
@onready var _script_overlay: PanelContainer = get_node(P_SCRIPT)
@onready var _script_title: Label = get_node(P_SCRIPT_SHEET + "/ScriptHeader/ScriptTitleBox/ScriptTitle")
@onready var _script_subtitle: Label = get_node(P_SCRIPT_SHEET + "/ScriptHeader/ScriptTitleBox/ScriptSubtitle")
@onready var _script_back_button: Button = get_node(P_SCRIPT_SHEET + "/ScriptHeader/ScriptBackButton")
@onready var _script_scroll: ScrollContainer = get_node(P_SCRIPT_SHEET + "/ScriptScroll")
@onready var _script_text: Label = get_node(P_SCRIPT_SHEET + "/ScriptScroll/ScriptText")

var _companies: Array[CompanyData] = []
var _current: CompanyData
var _role: RoleRequirement
var _pending: Clip
var _rows: Dictionary = {}            ## code -> Button
var _row_labels: Dictionary = {}      ## code -> {name, state}
var _role_buttons: Dictionary = {}    ## tier -> Button
## 聊天记录里那三个「试镜哪档」按钮（脚本建的，每次重建聊天都重来一遍）。
## 留着引用是为了测试能直接按 —— 与 `_event_buttons` 同一个道理。
var _tier_buttons: Array[Button] = []
## 程序化改按钮状态时会触发 toggled，用它挡住自己绕自己
var _syncing := false

## 正在"打字"的那一条：`{kind, code, index}`。空 = 没有在打字。
## - `kind == "mail"`：投递回信，`index` 是它在 `Game.state.history` 里的下标
## - `kind == "welcome"`：头一回点开时 HR 的打招呼（没有 `index`）
## 【为什么不存回信文本】画的时候是从 `Game.state.history` 里取的，存一份只会
## 在模板改了之后对不上 —— 这里只要"哪一条"。
## `index` 是它在 `Game.state.history` 里的下标（**整份履历的下标**，不是本公司的），
## 画聊天记录时靠它把那一条的回信暂时藏起来。
var _typing: Dictionary = {}
## 打字计时器。**不用 `await create_timer`**：本 App 会被手机屏销毁（去录像机 /
## 简历拿来都是整屏切走），挂在协程上的 await 会在对象被释放后继续跑，报一堆错。
## Timer 是子节点，跟着一起没了，干净。
var _typing_timer: Timer

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

	# 打字计时器（见 `_typing` 的注释：不用 await，跟着 App 一起生灭）
	_typing_timer = Timer.new()
	_typing_timer.name = "TypingTimer"
	_typing_timer.one_shot = true
	_typing_timer.timeout.connect(_finish_typing)
	add_child(_typing_timer)

	EventBus.hr_unlocked.connect(_on_hr_unlocked)
	EventBus.ap_changed.connect(_on_ap_changed)
	EventBus.state_reset.connect(_on_state_reset)
	EventBus.week_event_offered.connect(_on_week_event_offered)
	EventBus.week_event_resolved.connect(_on_week_event_resolved)
	_go_boss_button.pressed.connect(_on_open_boss)
	_open_recorder_button.pressed.connect(_on_open_recorder)
	_send_button.pressed.connect(_on_send)
	_back_button.pressed.connect(func() -> void: cancelled.emit())
	_script_back_button.pressed.connect(_close_script)

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
	# 一周可能挂着两条（10-17 起 1~2 条），这里给「先看谁」用的第一条
	var ev := Game.pending_events()
	if not ev.is_empty() and not ev[0].speaker.is_empty():
		return ev[0].speaker
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
	# 【先把**所有**等着回话的人排前面】一周可能两位同时找上门，
	# 只放第一位会让另一位的事件在名单上"隐身"，玩家永远看不到它。
	for ev: EventData in Game.pending_events():
		if ev != null and not ev.speaker.is_empty() and not out.has(ev.speaker):
			out.append(ev.speaker)
	for h: Dictionary in Game.state.event_history:
		var who := StringName(h.get("speaker", ""))
		if who != &"" and not out.has(who):
			out.append(who)
	return out


## 这个人在名单上的状态字（行上那一格总得有字）
func _speaker_state(speaker: StringName) -> String:
	# 【按人判，不按"第一位"判】两位同时找上门时，第二位不能显示成"已回过"
	if Game.pending_event_for(speaker) != null:
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
	# 【换会话就别再"打字"了】回信早在 state 里，切回来直接看到；
	# 不取消的话计时器会在玩家看别的会话时到点，突然重画一遍当前界面
	_cancel_typing()
	_current = null
	_event_speaker = speaker
	_role = null
	_close_script()
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

	# 未读角标：这位手里还压着一件没回的事
	var badge := _make_badge(1 if Game.pending_event_for(speaker) != null else 0)
	if badge != null:
		hbox.add_child(badge)

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

	# 未读角标：**先建出来、默认隐藏** —— 行是开局建一次、之后只改字，
	# 整行重建的话选中态与滚动位置都会跳（见 `_refresh_event_contacts` 的注释）
	var badge := _make_badge(1)
	badge.visible = Game.state.unread_hrs.has(co.code)
	hbox.add_child(badge)

	var state := Label.new()
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	state.add_theme_font_size_override("font_size", 15)
	hbox.add_child(state)

	_row_labels[co.code] = {
		"name": name_label, "state": state,
		"badge": badge, "badge_num": badge.get_node("Num"),
	}
	return row


## 未读角标：红底白字的小圆点。`count <= 0` 时返回 null，调用方按这个判断要不要挂。
func _make_badge(count: int) -> Panel:
	if count <= 0:
		return null
	var dot := Panel.new()
	dot.name = "Badge"
	dot.custom_minimum_size = Vector2(26, 26)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.add_theme_stylebox_override("panel", UiPalette.rounded(UiPalette.DANGER, 13))
	var num := Label.new()
	num.name = "Num"
	num.set_anchors_preset(Control.PRESET_FULL_RECT)
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	num.text = str(count)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.add_theme_font_size_override("font_size", 14)
	num.add_theme_color_override("font_color", UiPalette.INK)
	dot.add_child(num)
	return dot


## HR 行的角标开着还是关着。**只切可见性，不重建行**（重建会丢选中态）
func _sync_hr_badge(code: String) -> void:
	var refs: Dictionary = _row_labels.get(code, {})
	var dot: Panel = refs.get("badge")
	if dot == null:
		return
	dot.visible = Game.state.unread_hrs.has(code)


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
	# 同上：换人 / 回来重选都算离开那条会话，那排点不该跟着走
	_cancel_typing()
	_current = CompanyLibrary.by_code(code)
	# 记进状态：本 App 被切走再建起来时，要落在同一位联系人上（见 `_ready`）
	Game.set_focus_hr(code)
	# 【第一次点开 = 他刚把你加上】这一下要演一句「正在输入」（见 `_start_welcome`）。
	# 必须在 `mark_hr_read` **之前**读：那一句会把未读清掉。
	var fresh := Game.state.unread_hrs.has(code)
	# 点开 = 已读（他的角标在这儿灭掉）
	Game.mark_hr_read(code)
	# 【两个开关必须成对】`_is_event_chat()` 只看 `_event_speaker`，
	# 切回 HR 会话时忘了清它，界面会一直停在「事件会话」那一套上 ——
	# 表现是 HR 的三排 composer 全不见、头部还在显示事件内容。
	_event_speaker = &""
	_role = null
	# 【换人就把剧本页关了】不然 A 家的剧本会挂在那儿，玩家以为它是 B 家的
	_close_script()
	_syncing = true
	for c: String in _rows:
		(_rows[c] as Button).button_pressed = (c == code)
	_syncing = false
	_build_role_buttons()
	_refresh_all()
	if fresh:
		# 头一回点开：先"打"一会儿，那两句自我介绍才落地
		_start_welcome(code)
	else:
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


## 这家公司有没有**任何一个**够得着的档位。没有的话，连剧本都无从要起
func _any_role_ok() -> bool:
	if _current == null:
		return false
	for role: RoleRequirement in _current.roles:
		if _acting_ok(role):
			return true
	return false


## 底部那排档位按钮。**和聊天里那三个按钮是同一件事**：
## 点一个档位 = 跟 HR 要一份这一档的剧本（见 `_pick_tier`）——
## 分成两条路的话，会出现「按钮选着配角、手上却是主角的剧本」。
func _on_role_toggled(on: bool, tier: int) -> void:
	if _syncing or not on or _current == null:
		return
	_role = _current.role_of(tier)
	# 已经拿着这一档的剧本时 `_pick_tier` 不重抽，这时才需要自己刷一遍 composer
	if not _pick_tier(tier):
		_refresh_composer()


## 没选过 / 选的那个现在不够格 → 自动落在第一个够格的档位上。
## 【为什么要自动落】行动点只有 21 个，让玩家先选一个投出去一定不过的档位
## 是在骗他浪费一天。够格才给选，并且在按钮上写明要求。
func _auto_pick_role() -> void:
	if _current == null or _current.roles.is_empty():
		return
	# 【没剧本时不预选】档位是**手上那份剧本**定的。还没要到剧本就先空着 ——
	# 预选一个的话，玩家会以为「已经选好了、可以发了」，而这一排按钮还是摁下去的
	# （已按下的按钮再点一次不发信号），于是永远走不到「要剧本」那一步。
	var wanted := _script_role()
	if wanted != null:
		_role = wanted
	elif _role != null and not _acting_ok(_role):
		_role = null
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
		# 未读角标跟着状态走（新解锁 +1、点开 -1）
		_sync_hr_badge(co.code)
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
	# 【「正在输入」写在头部】真微信也是这么提示的。聊天里那三个小点太容易
	# 被当成装饰（尤其底下一堆旧气泡时）—— 这一行是要玩家抬头就看见的。
	if not _typing.is_empty() and String(_typing.get("code", "")) == _current.code:
		_peer_meta.text = "正在输入…"
	else:
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
	# 【先看剧本，再看档位】提提 10-16 定的流程：选档位 → HR 发剧本 → 去拼表情包 → 发过来。
	# 于是「手上这份剧本」就是**这一部戏里你演谁** —— 投递只认它，不认底部那排按钮。
	# 【为什么必须排在「档位」前面】还没要到剧本时底部那排本来就是空的，
	# 这时候说「演技不够」是假话 —— 该做的是回聊天里挑一个档位，不是去涨演技。
	var entry := Game.hr_script_of(_current.code)
	if entry.is_empty():
		if not _any_role_ok():
			return "演技还不够这家公司的任何一个档位（现在 %d）" % Game.acting()
		return "还没拿到剧本 —— 在下面挑一个档位，HR 会把剧本发过来"
	var doc := _script_doc()
	if doc == null:
		return "手上那份剧本读不出来了 —— 再挑一个档位要一份"
	if _role == null:
		return "演技还不够这家公司的任何一个档位（现在 %d）" % Game.acting()
	if doc.tier != _role.tier:
		return "手上那份是「%s」的剧本 —— 想投%s，先在下面挑它再要一份" % [
			doc.tier_name(), _role.tier_name()]
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
	var ev := Game.pending_event_for(_event_speaker)
	if ev == null:
		_requirement_label.text = "这条已经过去了"
		return
	var lines: Array[String] = []
	for o: EventOption in ev.options:
		lines.append("%s：%s" % [o.label, o.describe()])
	_requirement_label.text = "\n".join(lines)


func _refresh_event_composer() -> void:
	var ev := Game.pending_event_for(_event_speaker)
	if ev == null:
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
	# 【必须带 id】一周挂着两条时，光有 index 分不清在回谁的事
	var ev := Game.pending_event_for(_event_speaker)
	var r := Game.resolve_event(index, ev.id if ev != null else &"")
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
	_tier_buttons.clear()
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

	# 【刚点开时也在"打字"】第一次打开这位（进来前他还有未读）—— 整段先只摆那排点：
	# 自我介绍、口味线索、履历都等它落地再一起出现。
	# 【为什么整段都等，而不是只藏那两句招呼】只藏招呼的话，下面的历史记录照样铺满屏，
	# 「正在输入」就成了一句假话 —— 玩家看到的是"记录都在，还装什么打字"。
	if String(_typing.get("kind", "")) == "welcome" \
			and String(_typing.get("code", "")) == _current.code:
		_add_typing_bubble()
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

	# 【正在打字的是哪一条】`mail` 用下标藏履历里的那封回信；`script` 藏「他发剧本」那一段。
	# 下标是**整份履历**的下标，所以下面要对全部履历计数，不能只数本公司的。
	var typing_kind := ""
	if not _typing.is_empty() and String(_typing.get("code", "")) == _current.code:
		typing_kind = String(_typing.get("kind", ""))
	var typing_index := -1
	if typing_kind == "mail":
		typing_index = int(_typing.get("index", -1))

	var found := 0
	var index := -1
	for entry: Dictionary in Game.state.history:
		index += 1
		if String(entry.get("company_code", "")) != _current.code:
			continue
		found += 1
		_add_entry_bubbles(entry, index == typing_index)
	if found == 0:
		_add_note("还没有投过 %s —— 拼好表情包就能发第一条" % _current.display_name)

	# 正在输入时，聊天就停在那一排点上 —— 底下再追一句「试哪类角色」，
	# 看起来像 HR 一边打字一边已经问完了，很怪。等回信落地再问。
	if typing_index >= 0:
		_add_typing_bubble()
		return

	# 【他在"打"剧本】只画到「我想试X」，那句发送 + 文件卡等计时器到点再补上。
	if typing_kind == "script":
		_add_script_turn(true)
		_add_typing_bubble()
		return

	# 眼前这一句永远排在最后：要么是 HR 在问「试哪类角色」，要么是他刚发过来的剧本
	_add_script_turn()


## 主角的名字。**单一来源是内容池**（`data/casting_pool.tres` 的 `player_name`）——
## 邮件里的【玩家名】、电子报直呼其名、这里微信里的自我介绍，读的都是它。
## 【为什么不自己造一个占位】同一个名字要在三处显示，各存一份必然对不上；
## 而且「开一局自己取名字」是**往后要加的功能**（见 `进度.md` 待办），
## 到那天要改的是「名字从哪儿来」这一件事，不是三个界面。
func _player_name() -> String:
	var pool := MailLibrary.casting_pool()
	var who := pool.player_name if pool != null else ""
	return who if not who.strip_edges().is_empty() else "我"


## 把履历里的一条投递还原成「玩家气泡 + HR 回信」。
##
## `hide_mail` = 这一条正是"对方还在打字"的那条：只画我的投递，回信等计时器到点再画
## （见 `_typing`）。**只藏回信、不藏投递** —— 玩家得先看见自己发出去了。
func _add_entry_bubbles(entry: Dictionary, hide_mail := false) -> void:
	var labels: Array = entry.get("labels", [])
	_add_bubble("【投递】《%s》· %s\n表情包：%s" % [
		entry.get("play_title", "?"),
		RoleRequirement.TIER_NAMES.get(int(entry.get("role_tier", 0)), "?"),
		" → ".join(labels) if not labels.is_empty() else "—",
	], true)

	if hide_mail:
		return
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

	# 这周还没回的那条，把话摆在这儿等着（一周内同一个人只会来一次）
	var ev := Game.pending_event_for(_event_speaker)
	if ev != null:
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
	# 用真正渲染的那支字体量（见 `UiPalette.FONT` 的注释）
	var font := UiPalette.FONT
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


# ============================================================
# 「对方正在输入…」
# ============================================================
## 回信要"打"多久：按字数线性增长；短句最少 0.9 秒，再长也封顶 4.5 秒
## （等四秒半已经像卡住了，不像人）。
func _typing_seconds(text: String) -> float:
	return clampf(TYPING_BASE + text.length() * TYPING_PER_CHAR, TYPING_BASE, TYPING_MAX)


## 头一回点开这位：先"打"一会儿招呼，再把整段聊天铺出来。
##
## 【为什么放在点开时，而不是加好友时】加好友那一刻玩家还在 Boss直聘 里
## （微信根本不在场上），这边演给谁看？等他真的点进这条会话，才是"对方开口了"。
func _start_welcome(code: String) -> void:
	_typing = {"kind": "welcome", "code": code}
	_typing_timer.start(WELCOME_TYPING)
	_rebuild_chat()
	# 头部那行「正在输入…」（见 `_refresh_header`）
	_refresh_header()
	_scroll_chat_to_bottom()


## 玩家点了一个档位：先把「我想试X」画出来，他那句「这是《…》的剧本」+ 文件
## 等打字到点再出现。
##
## 【为什么时长按 `OFFER_SCRIPT` 算】那才是他真正要"打"的那句话 ——
## 按档位名或文件名算都对不上长度。
func _start_script_typing(doc: ScriptDoc) -> void:
	if _current == null or doc == null:
		return
	_typing = {"kind": "script", "code": _current.code}
	_typing_timer.start(_typing_seconds(OFFER_SCRIPT % [doc.play_title, doc.role_name]))
	_rebuild_chat()
	# 头部那行「正在输入…」
	_refresh_header()
	_scroll_chat_to_bottom()


## 玩家刚把表情包发出去：开始"打字"，那条回信先不画。
##
## 【位置为什么用履历下标】同一个人投过很多次，按回信文本比对迟早撞（模板会重复）；
## 下标由投递那一刻的 `history.size() - 1` 给出，是唯一的，也不依赖任何新字段。
## `text` 只用来算"打"多久（见 `_typing_seconds`），不往 `_typing` 里存。
func _start_typing(code: String, index: int, text: String) -> void:
	_typing = {"kind": "mail", "code": code, "index": index}
	_typing_timer.start(_typing_seconds(text))
	_rebuild_chat()
	# 头部那行「正在输入…」跟着一起亮（见 `_refresh_header`）
	_refresh_header()
	_scroll_chat_to_bottom()


## 到点：回信落地，顺手把那声"叮"放在这一刻。
## 【提示音为什么从 `Sfx` 挪到这儿】声音得跟着**气泡出现**走，而不是跟着核心层的
## `hr_replied` 信号 —— 那条信号在玩家点发送的同一帧就发了，那时对方还在打字。
func _finish_typing() -> void:
	if _typing.is_empty():
		return
	_typing.clear()
	Sfx.play(&"mail_reply")
	_rebuild_chat()
	_refresh_all()
	_scroll_chat_to_bottom()


## 离开这条会话 / 换人 / 开新局：别再画那排点了。
## 回信本身早在 state 里，回到这条会话会直接看到 —— 只是没有"打字"这一段。
func _cancel_typing() -> void:
	if _typing.is_empty():
		return
	_typing.clear()
	if _typing_timer != null:
		_typing_timer.stop()


## 三个点的灰气泡：对方头像 + 一个只有三个点的卡。
## 点用 `Panel` + 全圆角画（项目里头像/角标都是这个画法），
## 每个点各自一条 tween 错开起跳，才像有人在敲字。
func _add_typing_bubble() -> void:
	var row := HBoxContainer.new()
	row.name = "TypingRow"
	row.add_theme_constant_override("separation", 10)

	row.add_child(_bubble_avatar(false))

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	card.add_theme_stylebox_override("panel",
			UiPalette.panel(UiPalette.PANEL_SOFT, 16, 2, UiPalette.LINE))

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	card.add_child(margin)

	var dots := HBoxContainer.new()
	dots.add_theme_constant_override("separation", 6)
	margin.add_child(dots)
	var pulses: Array[Panel] = []
	for i in 3:
		var dot := Panel.new()
		# 【点要够大够亮】10px + `TEXT_DIM` + 0.3 透明在深色底上几乎看不见 ——
		# 玩家会以为「对方根本没在打字」。这里用正文色、12px，呼吸幅度也更明显。
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.modulate.a = 0.4
		dot.add_theme_stylebox_override("panel", UiPalette.rounded(UiPalette.TEXT, 6))
		dots.add_child(dot)
		pulses.append(dot)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(card)
	row.add_child(spacer)
	_chat_log.add_child(row)

	# 【起 tween 必须等进树之后】`create_tween()` 要求节点已在场景树里：
	# 上面那几行只是拼装，整行到这一句才挂上聊天区 —— 早一步调就是拿 null。
	for i in pulses.size():
		_pulse_dot(pulses[i], i * TYPING_STAGGER)


## 一个点的呼吸循环。**tween 绑在点上**（`dot.create_tween()`），
## 聊天记录重建、点被释放时它自己就没了 —— 不用手动回收。
func _pulse_dot(dot: Panel, delay: float) -> void:
	var tw := dot.create_tween().set_loops()
	tw.tween_interval(delay)
	tw.tween_property(dot, "modulate:a", 1.0, 0.22)
	tw.tween_property(dot, "modulate:a", 0.4, 0.22)
	tw.tween_interval(0.42)


func _scroll_chat_to_bottom() -> void:
	# 等一帧让容器算完高度，否则拿到的是旧 max_value，滚不到底
	await get_tree().process_frame
	_chat_scroll.scroll_vertical = int(_chat_scroll.get_v_scroll_bar().max_value)


# ============================================================
# 剧本：HR 在聊天里发过来的那份 .docx
# ============================================================
## 聊天记录的最后一段：要么是 HR 在问「试哪类角色」，要么是他刚发过来的那份剧本。
##
## 【为什么它永远在最后】聊天的顺序就是对话的顺序：自我介绍 → 口味线索 → 履历 →
## **眼前这一句**。投递之后剧本被清掉（见 `_on_send`），这一段自己就变回「问下一部」——
## 不需要任何「已经问过没有」的标记，全部从 `Game.hr_script_of` 推出来。
## `hide_offer` = 他还在"打"这份剧本：只画到「我想试X」，发送那句话、文件卡、
## 我那句「我先看剧本」都等打字到点再补（见 `_start_script_typing`）。
func _add_script_turn(hide_offer := false) -> void:
	if _current == null or not Game.is_hr_unlocked(_current.code):
		return
	if Game.hr_script_of(_current.code).is_empty():
		# 【一个档都够不着时先不摆选项】三个按钮全灰着摆在那儿，玩家只会反复点 ——
		# 提提 10-16 定的：这时候干脆不出现，只留一句说清差什么。
		if not _any_role_ok():
			_add_note("（这家公司的档位他现在都够不着 —— 先把演技练上去，再来找他要剧本）")
			return
		_add_bubble(ASK_SCRIPT, false)
		_add_tier_buttons()
		return
	var doc := _script_doc()
	if doc == null:
		# 那几份 .tres 没生成、或剧本被改过：明说一句，并让玩家能重新要一份
		_add_note("（那份剧本读不出来了 —— 再挑一个档位要一份）")
		_add_tier_buttons()
		return
	# 【邀请那句话要留在记录里】（提提 10-16）挑完档位之后它不该消失 ——
	# 聊天记录是「你和这个人聊过什么」，不是「眼前还剩什么待办」。
	# 跟着它一起留下的是我要的档 + 他发过来的文件，读起来就是一段完整对话。
	_add_bubble(ASK_SCRIPT, false)
	# 【顺序是「我先开口 → 他再发」】挑完档位不是 HR 自说自话，
	# 是玩家要了哪一档、HR 才把那一档的剧本递过来。
	# 这一句由**手上那份剧本**推出来，所以换档时它跟着换，不用额外存。
	_add_bubble(PICK_SCRIPT % doc.tier_name(), true)
	# 我这句已经发出去了，剩下的等他"打完"（见 `_start_script_typing`）
	if hide_offer:
		return
	_add_bubble(OFFER_SCRIPT % [doc.play_title, doc.role_name], false)
	_add_file_card(doc)
	_add_bubble(REPLY_SCRIPT, true)
	_add_note("（点一下文件看剧本）")


## 手上那份剧本。没有 / 内容读不出来时返回 null。
##
## 【为什么按 (剧本序号, 档位) 还原，而不是把正文存进存档】
## 存档里只有两个数 —— 狗牙改剧本内容、改角色名、甚至改文件名，读档回来照样对得上。
func _script_doc() -> ScriptDoc:
	if _current == null:
		return null
	var entry := Game.hr_script_of(_current.code)
	if entry.is_empty():
		return null
	return ScriptLibrary.for_play_tier(int(entry.get("play", 0)), int(entry.get("tier", -1)))


## 手上那份剧本对应的档位（没有剧本时 null）—— 发送栏那一排看它
func _script_role() -> RoleRequirement:
	if _current == null:
		return null
	var doc := _script_doc()
	return _current.role_of(doc.tier) if doc != null else null


## 聊天里那三个「试镜哪档」按钮。**竖排、带门槛**（与「简历拿来」的三选一同一个样子）：
## 够格的标出匹配线，不够格的直接灰掉并写明还差多少演技。
func _add_tier_buttons() -> void:
	if _current == null:
		return
	# 缩进一点 —— 让它看着像「在这个会话里回答 HR」，而不是一条系统提示
	var indent := MarginContainer.new()
	indent.add_theme_constant_override("margin_left", 50)
	var box := VBoxContainer.new()
	box.name = "TierChoices"
	box.add_theme_constant_override("separation", 10)
	indent.add_child(box)

	for role: RoleRequirement in _current.roles:
		var b := Button.new()
		b.name = "Tier_%d" % role.tier
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _acting_ok(role):
			b.text = "试镜「%s」｜ 匹配 %.0f%%" % [role.tier_name(), role.match_line * 100.0]
		else:
			b.text = "试镜「%s」—— 还差：要演技 %d（现在 %d）" % [
				role.tier_name(), _required_acting(role), Game.acting()]
			b.disabled = true
		b.add_theme_stylebox_override("normal",
				UiPalette.button(UiPalette.PANEL_SOFT, UiPalette.SCRIPT, 2, 14, 0, 12))
		b.add_theme_stylebox_override("hover",
				UiPalette.button(Color("35353f"), UiPalette.SCRIPT, 2, 14, 0, 12))
		b.add_theme_stylebox_override("pressed",
				UiPalette.button(Color("3a2c1c"), UiPalette.SCRIPT, 3, 14, 3, 12))
		b.add_theme_stylebox_override("disabled",
				UiPalette.button(Color("1c1c22"), UiPalette.LINE, 1, 14, 0, 12))
		b.add_theme_color_override("font_color", UiPalette.SCRIPT)
		b.add_theme_color_override("font_hover_color", UiPalette.SCRIPT)
		b.add_theme_color_override("font_pressed_color", UiPalette.SCRIPT)
		b.add_theme_color_override("font_disabled_color", Color("5a5a63"))
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_on_tier_pressed.bind(role.tier))
		box.add_child(b)
		_tier_buttons.append(b)

	_chat_log.add_child(indent)


func _on_tier_pressed(tier: int) -> void:
	_pick_tier(tier)


## 点一个档位 = 跟 HR 要一份这一档的剧本。返回 true 表示这次真的换了一份。
##
## 【同一档不重抽】手上已经是这一档的剧本时什么都不做 ——
## 否则玩家手滑多点一下剧本就从头换一本，刚看过的内容白看了。
func _pick_tier(tier: int) -> bool:
	if _current == null:
		return false
	var entry := Game.hr_script_of(_current.code)
	if not entry.is_empty() and int(entry.get("tier", -1)) == tier:
		return false
	var doc := Game.request_script(_current, tier)
	if doc == null:
		return false
	_role = _current.role_of(doc.tier)
	_auto_pick_role()
	_refresh_composer()
	# 【剧本也是"他发过来的"】点完档位不能同一帧就把 .docx 拍在脸上 ——
	# 和投递回信一样，先让那边打一会儿字（见 `_start_script_typing`）。
	_start_script_typing(doc)
	return true


## 一条文件消息：头像 + [W] 文件名 / 大小。**整张卡可点** —— 点开就是剧本页。
func _add_file_card(doc: ScriptDoc) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_bubble_avatar(false))
	row.add_child(_file_card(doc))
	row.add_child(spacer)
	_chat_log.add_child(row)


func _file_card(doc: ScriptDoc) -> Button:
	var b := Button.new()
	b.name = "ScriptCard"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(360, 96)
	b.add_theme_stylebox_override("normal",
			UiPalette.button(UiPalette.PANEL_SOFT, UiPalette.LINE, 2, 16))
	b.add_theme_stylebox_override("hover",
			UiPalette.button(Color("35353f"), UiPalette.SCRIPT, 2, 16))
	b.add_theme_stylebox_override("pressed",
			UiPalette.button(Color("2a2622"), UiPalette.SCRIPT, 3, 16, 3))
	b.pressed.connect(_open_script)

	# 内容全部 MOUSE_FILTER_IGNORE —— 点击要透给按钮本身，否则 hover / pressed 失灵
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", CARD_PAD)
	margin.add_theme_constant_override("margin_right", CARD_PAD)
	margin.add_theme_constant_override("margin_top", CARD_PAD_V)
	margin.add_theme_constant_override("margin_bottom", CARD_PAD_V)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 14)
	margin.add_child(hbox)

	# 那个「W」：真 Word 图标的蓝底白字，玩家一眼认出是文档。
	# 【为什么是 PanelContainer 而不是 Panel】Panel 不是容器 —— 塞在里面的 Label
	# 得自己摆锚点，于是字会飘（提提一眼看出来的那个「偏」）。PanelContainer 会把
	# 子节点铺满自己的内容区，Label 靠两个 alignment 居中，尺寸怎么变都不会偏。
	var icon := PanelContainer.new()
	icon.name = "WordIcon"
	icon.custom_minimum_size = Vector2(56, 56)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_theme_stylebox_override("panel", UiPalette.rounded(UiPalette.DOCX, 10))
	hbox.add_child(icon)

	var w := Label.new()
	w.name = "WordMark"
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w.text = "W"
	w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	w.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	w.add_theme_font_size_override("font_size", 28)
	w.add_theme_color_override("font_color", UiPalette.PAPER)
	icon.add_child(w)

	var text_box := VBoxContainer.new()
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_box.add_theme_constant_override("separation", 4)
	hbox.add_child(text_box)

	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = doc.file_name()
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.text(name_label, 20, UiPalette.TEXT)
	text_box.add_child(name_label)

	var size_label := Label.new()
	size_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_label.text = doc.size_text()
	UiPalette.text(size_label, 15, UiPalette.TEXT_DIM)
	text_box.add_child(size_label)

	return b


## 把剧本页铺出来（橘色那一页，盖在聊天区上）。关掉就回到刚才那条会话。
func _open_script() -> void:
	var doc := _script_doc()
	if doc == null:
		return
	_script_title.text = doc.file_name()
	_script_subtitle.text = "《%s》· %s ｜ %d 场" % [
		doc.play_title, doc.tier_name(), doc.scene_count]
	_script_text.text = doc.body
	_script_overlay.visible = true
	# 每次打开都从头看：上一份剧本滚到哪儿了，与这一份无关
	await get_tree().process_frame
	_script_scroll.scroll_vertical = 0


func _close_script() -> void:
	_script_overlay.visible = false


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

	# 表情包一次性消耗（决策 1.6）：投出去就没了，下次必须重新拼
	_pending = null
	Game.clear_pending_clip()
	# 【这一份剧本也用掉了】投出去之后清掉 —— HR 接着问下一部（提提 10-16 的 B+C）。
	# 【为什么改成整段重建】回信的画面本来就是从履历铺出来的（`_add_entry_bubbles`），
	# 手工再铺一遍等于同一件事写两处；重建还顺手把顺序摆对：回信在上、新问题在下。
	Game.clear_hr_script(_current.code)
	_refresh_all()
	# 【回信晚几秒才"打"出来】刚才那条已经从 state 里铺过了，这里只是让它先藏着：
	# 下标用履历最后一条（`DailyActions.submit` 刚 append 的那条），
	# 按文本比对迟早撞模板，下标是唯一的。
	var mail: Dictionary = res.get("mail", {})
	_start_typing(_current.code, Game.state.history.size() - 1, String(mail.get("text", "")))


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
	# 开新局 / 读档：上一局那条"还没打完的回信"不能跟着留下来
	_cancel_typing()
	_current = null
	_pending = Game.pending_clip()
	_role = null
	_event_speaker = &""
	_close_script()
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

	# 滚动条（联系人 + 聊天 + 剧本）
	for bar: VScrollBar in [
			_contact_list.get_parent().get_v_scroll_bar(),
			_chat_scroll.get_v_scroll_bar(),
			_script_scroll.get_v_scroll_bar()]:
		bar.custom_minimum_size = Vector2(10, 0)
		bar.add_theme_stylebox_override("scroll",
				UiPalette.button(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0, 0))
		bar.add_theme_stylebox_override("grabber", UiPalette.rounded(UiPalette.LINE, 5))
		bar.add_theme_stylebox_override("grabber_highlight", UiPalette.rounded(UiPalette.WECHAT, 5))

	# ---- 剧本页 ----
	# 【纸的比方】这页是「打印出来的剧本」，所以整体离开微信那套绿灰，改用剧本橘 ——
	# 一眼就知道自己不在聊天里了，而是在看一样东西（关掉就回去）。
	_node_panel(_script_overlay, Color("1f1b17"), 18, 2, UiPalette.SCRIPT)
	UiPalette.text(_script_title, 24, UiPalette.SCRIPT)
	UiPalette.text(_script_subtitle, 15, UiPalette.TEXT_DIM)
	UiPalette.text(_script_text, 18, UiPalette.SCRIPT)
	_script_text.add_theme_constant_override("line_spacing", 6)
	_style_action(_script_back_button, UiPalette.PANEL_SOFT, UiPalette.TEXT, UiPalette.SCRIPT, 20)


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
