extends Control
## 手机屏 —— 左边一台手机（App 列表 / 某个 App 的二级列表），右边是内容
##
## 【和日历的分工】改版后：**日历** = 你的日程与进度（完整状态栏 + 今日安排 +
## 本周进度 + 结算浮层），**手机** = 那 4 个 App。所以这一屏只有一条**窄状态栏**
## （第 N 天 · 行动点 · 钱）：行动点每天只有 1 点，而花掉它的按钮在日历那边 ——
## 不摆出来，玩家每做一步都得跑回日历看一眼还剩几点。
##
## 【左栏为什么会换】点开一个 App 之后，左栏从「App 列表」换成**那个 App 的二级列表**
## （比如微信换成联系人）。约定：愿意交出来的 App 实现两个方法 ——
##   `take_sidebar() -> Control`  把列表交出来（连同它的子节点）
##   `sidebar_title() -> String`  左栏顶上显示什么
## 没实现的 App 就把右栏整个占满，左栏继续列 App（玩家能直接换一个）。
##
## 【为什么可以「搬走 App 的列表」】那些 App 的脚本用**绝对路径**抓自己的节点
## （`@onready var _contact_list = get_node("Page/BodyWrap/...")`），而 `@onready`
## 在 `_ready()` 就把它抓进变量了。所以**等 App `_ready()` 之后再搬**，引用依然有效，
## 路径不再被用到。反过来说：搬之前必须先 `add_child`，不能拿没进树的场景去搬。
##
## 【返回桌面】与录像机 / 微信 / Boss直聘 被嵌进手机时同一套约定：
## `cancelled` 信号 + `enable_back()`，由桌子决定要不要露出返回入口。

const P_HUD := "Page/HudBar/HudMargin/HudRow"
const P_COLUMN := "Page/BodyWrap/Body/AppColumn/ColumnMargin/ColumnBox"
const P_CONTENT := "Page/BodyWrap/Body/ContentPanel/ContentMargin/ContentHost"

const DEFAULT_HINT := "悬浮看每个 App 是干什么的"

## 上层（桌子）离开本屏
signal cancelled

@onready var _hud_left: HBoxContainer = get_node(P_HUD + "/HudLeft")
@onready var _hud_right: HBoxContainer = get_node(P_HUD + "/HudRight")
@onready var _caption: Label = get_node(P_COLUMN + "/ColumnHead/ColumnCaption")
@onready var _column_back: Button = get_node(P_COLUMN + "/ColumnHead/ColumnBack")
@onready var _column_hint: Label = get_node(P_COLUMN + "/ColumnHint")
@onready var _app_list: VBoxContainer = get_node(P_COLUMN + "/AppList")
@onready var _sidebar_host: Control = get_node(P_COLUMN + "/SidebarHost")
@onready var _content: Control = get_node(P_CONTENT)

var _day_label: Label
var _ap_label: Label
var _money_label: Label
var _back_button: Button
var _back_enabled := false
## scene_path -> Button（判断某个 App 开着没有、要不要标成选中）
var _app_rows: Dictionary = {}
## 当前打开的 App（同一时刻只允许一个）
var _current: Node
var _current_path := ""
## 从 App 手里接管过来的二级列表
var _sidebar: Control
## 右栏空着时的提示（开 App 时收起来）
var _empty_hint: Label


func _ready() -> void:
	_apply_styles()
	_build_hud()
	_build_app_list()
	_build_empty_hint()
	_show_app_list()

	EventBus.ap_changed.connect(_on_ap_changed)
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.state_reset.connect(_on_state_reset)
	_refresh_hud()


# ============================================================
# 窄状态栏
# ============================================================
func _build_hud() -> void:
	_back_button = Button.new()
	_back_button.text = "← 桌面"
	_back_button.focus_mode = Control.FOCUS_NONE
	_back_button.visible = false
	_back_button.pressed.connect(func() -> void: cancelled.emit())
	_hud_left.add_child(_back_button)
	UiPalette.text(_back_button, 20, UiPalette.TEXT)
	_back_button.add_theme_stylebox_override("normal",
			UiPalette.button(UiPalette.PANEL_SOFT, UiPalette.LINE, 2, 12, 0, 12))
	_back_button.add_theme_stylebox_override("hover",
			UiPalette.button(UiPalette.PANEL_SOFT.lightened(0.1), UiPalette.ACCENT, 3, 12, 0, 12))
	_back_button.add_theme_stylebox_override("pressed",
			UiPalette.button(UiPalette.PANEL_SOFT, UiPalette.ACCENT, 3, 12, 0, 12))

	_day_label = _chip(_hud_left, 24, UiPalette.TEXT)
	_ap_label = _chip(_hud_left, 22, UiPalette.POSITIVE)
	_money_label = _chip(_hud_right, 24, UiPalette.ACCENT)


func _chip(parent: Node, size: int, color: Color) -> Label:
	var l := Label.new()
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiPalette.text(l, size, color)
	parent.add_child(l)
	return l


## 窄 = 只回答「现在是第几天、还能做几件事、还有多少钱」这三件事。
## 属性（演技 / 知名度 / 风评）不在这儿 —— 它们在日历上，那是做决定的地方。
func _refresh_hud() -> void:
	_day_label.text = "第 %d 天 · 第 %d 周" % [Game.day(), Game.week()]
	_ap_label.text = "行动点 %d" % Game.ap_left()
	_money_label.text = "%d 元" % Game.money()


# ============================================================
# 左栏 · App 列表
# ============================================================
func _build_app_list() -> void:
	for app: Dictionary in AppCatalog.APPS:
		var row := _make_app_row(app)
		_app_list.add_child(row)
		_app_rows[String(app["scene"])] = row
	_column_back.pressed.connect(_back_to_app_list)


## 一行 App。**悬浮就把它的作用写进下面那行小字** —— 这是这版改版点名要的：
## 不点进去也知道每个 App 是干什么的。
##
## `tooltip_text` 也一起设：手机上用手指是悬不起来的（没有 hover），
## 长按弹出的系统提示是那边唯一的等价物。
func _make_app_row(app: Dictionary) -> Button:
	var hint := String(app["hint"])
	var b := Button.new()
	b.name = "App_" + String(app["name"])
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 96)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.tooltip_text = hint
	b.mouse_entered.connect(func() -> void: _column_hint.text = hint)
	b.mouse_exited.connect(func() -> void: _column_hint.text = DEFAULT_HINT)
	b.pressed.connect(open_app.bind(String(app["scene"])))

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
	UiBits.one_line(name_label, 20, 220)
	text_box.add_child(name_label)

	var sub := Label.new()
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.text = hint
	UiPalette.text(sub, 14, UiPalette.TEXT_DIM)
	UiBits.one_line(sub, 14, 220)
	text_box.add_child(sub)

	b.add_theme_stylebox_override("normal",
			UiPalette.button(UiPalette.PANEL_SOFT, UiPalette.LINE, 2, 16, 0, 12))
	b.add_theme_stylebox_override("hover",
			UiPalette.button(Color("2d2d36"), app["color"], 2, 16, 0, 12))
	b.add_theme_stylebox_override("pressed",
			UiPalette.button(app["color"], app["color"], 2, 16, 4, 12))
	return b


func _build_empty_hint() -> void:
	_empty_hint = Label.new()
	_empty_hint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_empty_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_hint.text = "右边是空的 ——\n在左边挑一个 App 打开"
	UiPalette.text(_empty_hint, 24, UiPalette.TEXT_DISABLED)
	_content.add_child(_empty_hint)


# ============================================================
# 打开 / 关闭 App
# ============================================================
## 打开一个 App。路径见 `AppCatalog.APPS`；已经开着就先关掉（点第二次 = 收起）
##
## **公开**是为了让桌子能直接用：日历上「去投递」那张卡会请求开微信，
## 而微信归本屏管，桌子只需要找到本屏、调这一下。
func open_app(scene_path: String) -> void:
	# 【点同一个 App = 什么都不做，不是「收起」】原来这里是 toggle：已经开着就关掉。
	# 于是「按过「← 全部」之后再点这个 App」的第一次点击变成了关闭 ——
	# 玩家看到的就是「点一次没进去，得点两次」。切 App 是点**另一个**图标的事。
	if _current != null:
		if _current_path == scene_path:
			return
		_close_app()
	_current = load(scene_path).instantiate()
	_current_path = scene_path
	_content.add_child(_current)
	if _current.has_signal("cancelled"):
		_current.cancelled.connect(_close_app)
	# App 之间互相「顶开」：Boss聊完会说「去微信聊」，微信也这么被打开过。
	# 【为什么由本屏接】切 App 是这一层的事，App 自己不该知道别家住在哪儿 ——
	# 它只发一个场景路径，剩下交给这里（`open_app` 会先关掉当前那个）。
	if _current.has_signal("open_app_requested"):
		_current.open_app_requested.connect(open_app)
	# 【故意不调 `enable_back()`】那是「被当成整屏打开」时的约定，各 App 的返回按钮
	# 写的是自己原来那位宿主的话（Boss 上写着「返回微信」，本屏根本没有微信那回事）。
	# 现在本屏就是宿主：顶上一条「← 桌面」、左边一列 App，两层导航都齐了 ——
	# 再放一个说不清回哪儿的按钮，只会让玩家点错。
	_empty_hint.visible = false
	_take_sidebar()


## 问 App 要它的二级列表，接到左栏来。
## 交给左栏之后，这个列表就归本屏管了（关闭 App 时要自己收掉）。
func _take_sidebar() -> void:
	if not _current.has_method("take_sidebar"):
		return
	var side: Variant = _current.take_sidebar()
	if not (side is Control):
		return
	_sidebar = side as Control
	# 【必须 reparent 不能 add_child】它已经在原来那棵树上了（挂在 App 自己身上），
	# `add_child` 会直接报「already has a parent」并把它留在原地。
	_sidebar.reparent(_sidebar_host)
	# 【铺满靠锚点，不靠 size_flags】`SidebarHost` 是个**普通 Control**（不是容器），
	# 子节点铺满只能靠锚点。这么做的关键好处：**容器的尺寸不再被这个外来列表撑开** ——
	# 左栏因此永远是一块定宽的「小手机」，不管换到哪个 App。
	# （用布局容器的话，列表自己声明的宽度会把整列顶宽：Boss 的卡片曾把左栏从 470 撑到 777，
	# 那多出来的部分又被右栏的 App 画在上面 —— 看着就是「右边把左边遮了」。）
	_sidebar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _current.has_method("sidebar_title"):
		_caption.text = String(_current.sidebar_title())
	else:
		_caption.text = "二级"
	_app_list.visible = false
	_sidebar_host.visible = true
	_column_back.visible = true
	_column_hint.visible = false


func _close_app() -> void:
	if _current == null:
		return
	# 二级列表已经被接到左栏下了，不跟着 App 一起消失 —— 得自己收
	if _sidebar != null:
		_sidebar.queue_free()
		_sidebar = null
	if _current.has_signal("cancelled") and _current.cancelled.is_connected(_close_app):
		_current.cancelled.disconnect(_close_app)
	_current.queue_free()
	_current = null
	_current_path = ""
	_empty_hint.visible = true
	_show_app_list()


func _show_app_list() -> void:
	_caption.text = "App"
	_app_list.visible = true
	_sidebar_host.visible = false
	_column_back.visible = false
	_column_hint.visible = true
	_column_hint.text = DEFAULT_HINT


## 左栏顶上那个「← 全部」：回 App 列表 = **离开当前 App**。
##
## 【为什么不只把左栏换回来】只换左栏的话，右栏还停在 App 里刚才那一层
## （Boss 聊到一半、聊天盖着详情）—— 左边回到列表、右边还是聊天，两边对不上（真踩过）。
## 「回主界面」本来就是离开这个 App：关掉它，右栏回到空态。
## 关掉的同时也会把左栏换回列表（`_close_app` 里做了），所以这里只要这一个动作。
func _back_to_app_list() -> void:
	_close_app()


## 现在开着哪个 App（测试与桌子用）
func current_app_path() -> String:
	return _current_path


# ============================================================
# 返回桌面
# ============================================================
func enable_back() -> void:
	_back_enabled = true
	if _back_button != null:
		_back_button.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if not _back_enabled or not event.is_action_pressed("ui_cancel"):
		return
	# 安卓返回键的惯例：先关最上面那一层，再谈退到哪去
	get_viewport().set_input_as_handled()
	if _current != null:
		_close_app()
		return
	cancelled.emit()


# ============================================================
# 信号
# ============================================================
func _on_ap_changed(_left: int) -> void:
	_refresh_hud()


func _on_money_changed(_value: int, _delta: int) -> void:
	_refresh_hud()


## 状态被整个换掉（开新局 / 读档）：开着的 App 必须关掉 —— 它读的是上一局的数据
func _on_state_reset() -> void:
	_close_app()
	_refresh_hud()


# ============================================================
# 样式
# ============================================================
func _apply_styles() -> void:
	get_node("Bg").color = UiPalette.BG

	# 状态栏只留一条亮色下边线 —— 和录像机 / 日历同一个手法
	var bar := StyleBoxFlat.new()
	bar.bg_color = UiPalette.PANEL
	bar.border_width_bottom = 3
	bar.border_color = UiPalette.ACCENT
	get_node("Page/HudBar").add_theme_stylebox_override("panel", bar)

	get_node("Page/BodyWrap/Body/AppColumn").add_theme_stylebox_override("panel",
			UiPalette.panel(UiPalette.PANEL, 20, 2, UiPalette.LINE))
	get_node("Page/BodyWrap/Body/ContentPanel").add_theme_stylebox_override("panel",
			UiPalette.panel(UiPalette.PANEL, 20, 2, UiPalette.LINE))

	UiPalette.text(_caption, 26, UiPalette.TEXT)
	UiPalette.text(_column_hint, 15, UiPalette.TEXT_DIM)

	_column_back.focus_mode = Control.FOCUS_NONE
	UiPalette.text(_column_back, 17, UiPalette.TEXT)
	_column_back.add_theme_stylebox_override("normal",
			UiPalette.button(UiPalette.PANEL_SOFT, UiPalette.LINE, 2, 10, 0, 10))
	_column_back.add_theme_stylebox_override("hover",
			UiPalette.button(UiPalette.PANEL_SOFT.lightened(0.1), UiPalette.ACCENT, 2, 10, 0, 10))
