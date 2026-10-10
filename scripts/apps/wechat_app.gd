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

## 公司档位配色统一在 UiPalette（Boss直聘 的联系人头像用同一套）
const TIER_COLORS := UiPalette.COMPANY_TIER_COLORS

@onready var _status_label: Label = get_node(P_TOP + "/TopRight/StatusLabel")
@onready var _channel_label: Label = get_node(P_TOP + "/TopRight/ChannelLabel")
@onready var _contact_list: VBoxContainer = get_node(P_CONTACTS + "/ContactsScroll/ContactList")
@onready var _contacts_hint: Label = get_node(P_CONTACTS + "/ContactsHint")
@onready var _peer_name: Label = get_node(P_HEADER + "/PeerBox/PeerName")
@onready var _peer_meta: Label = get_node(P_HEADER + "/PeerBox/PeerMeta")
@onready var _requirement_label: Label = get_node(P_HEADER + "/RequirementLabel")
@onready var _chat_scroll: ScrollContainer = get_node(P_CHAT + "/ChatScroll")
@onready var _chat_log: VBoxContainer = get_node(P_CHAT + "/ChatScroll/ChatLog")
@onready var _role_buttons_row: HBoxContainer = get_node(P_COMPOSER + "/RoleRow/RoleButtons")
@onready var _attach_card: PanelContainer = get_node(P_COMPOSER + "/AttachRow/AttachCard")
@onready var _attach_title: Label = get_node(P_COMPOSER + "/AttachRow/AttachCard/AttachMargin/AttachBox/AttachTitle")
@onready var _attach_detail: Label = get_node(P_COMPOSER + "/AttachRow/AttachCard/AttachMargin/AttachBox/AttachDetail")
@onready var _go_boss_button: Button = get_node(P_CONTACTS + "/GoBossButton")
@onready var _open_recorder_button: Button = get_node(P_COMPOSER + "/AttachRow/OpenRecorderButton")
@onready var _status_line: Label = get_node(P_COMPOSER + "/SendRow/StatusLine")
@onready var _send_button: Button = get_node(P_COMPOSER + "/SendRow/SendButton")

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


func _ready() -> void:
	_companies = CompanyLibrary.all()

	_apply_styles()
	_build_contacts()

	EventBus.hr_unlocked.connect(_on_hr_unlocked)
	EventBus.ap_changed.connect(_on_ap_changed)
	EventBus.state_reset.connect(_on_state_reset)
	_go_boss_button.pressed.connect(_on_open_boss)
	_open_recorder_button.pressed.connect(_on_open_recorder)
	_send_button.pressed.connect(_on_send)

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
	var group := ButtonGroup.new()
	for co: CompanyData in _companies:
		var row := _make_contact_row(co)
		row.button_group = group
		row.toggled.connect(_on_contact_toggled.bind(co.code))
		_contact_list.add_child(row)
		_rows[co.code] = row


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


func _refresh_contacts() -> void:
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

	# 有子页面盖上来时，两个入口都别再点（避免叠两层 App）
	var covered := _overlay != null
	_open_recorder_button.disabled = covered
	_go_boss_button.disabled = covered


# ============================================================
# 聊天记录
# ============================================================
func _rebuild_chat() -> void:
	for child in _chat_log.get_children():
		child.queue_free()
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


func _on_ap_changed(_left: int) -> void:
	_refresh_top()
	_refresh_composer()


## 状态被整个换掉（开新局 / 读档）：选中联系人、待投递表情包、子页面 —— 一样都不能留
func _on_state_reset() -> void:
	_close_overlay()
	_current = null
	_pending = null
	_role = null
	for child in _role_buttons_row.get_children():
		child.queue_free()
	_role_buttons.clear()
	_syncing = true
	for c: String in _rows:
		(_rows[c] as Button).button_pressed = false
	_syncing = false
	_refresh_all()
	_rebuild_chat()


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
	UiPalette.text(get_node(P_TOP + "/TopCenter/Title"), 40, UiPalette.TEXT)
	UiPalette.text(get_node(P_TOP + "/TopCenter/Subtitle"), 15, UiPalette.TEXT_DIM)
	UiPalette.text(_status_label, 20, UiPalette.ACCENT)
	UiPalette.text(_channel_label, 15, UiPalette.TEXT_DIM)

	UiPalette.text(get_node(P_CONTACTS + "/ContactsCaption"), 22, UiPalette.TEXT)
	UiPalette.text(_contacts_hint, 14, UiPalette.TEXT_DIM)

	UiPalette.text(_peer_name, 24, UiPalette.TEXT)
	UiPalette.text(_peer_meta, 15, UiPalette.TEXT_DIM)
	UiPalette.text(_requirement_label, 16, UiPalette.ACCENT)

	UiPalette.text(get_node(P_COMPOSER + "/RoleRow/RoleCaption"), 16, UiPalette.TEXT_DIM)
	UiPalette.text(_attach_title, 20, UiPalette.TEXT)
	UiPalette.text(_attach_detail, 15, UiPalette.TEXT_DIM)
	UiPalette.text(_status_line, 16, UiPalette.ACCENT)

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
