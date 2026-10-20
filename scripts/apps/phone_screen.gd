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
## 左栏现在是**一台手机**：PhoneBody（外框图）在下、ScreenMask（遮罩）裁出屏幕形状，
## 列表挂在遮罩里 —— 所以路径中间多了一层 `ScreenMask`。
const P_COLUMN := "Page/BodyWrap/Body/AppColumn/ScreenMask/ColumnMargin/ColumnBox"
const P_CONTENT := "Page/BodyWrap/Body/ContentPanel/ContentMargin/ContentHost"

const DEFAULT_HINT := "悬浮看每个 App 是干什么的"

## 顶栏整条：美术给的手绘纸条，四个图标**画在纸里**（闪电 / 面具 / 星星 / 金币）
const HUD_BAR_TEX := preload("res://assets/ui/phone/hud_bar.png")
## 返回桌面压的那张米色通用框（和演员登记表同一张）
const FRAME_BEIGE := preload("res://assets/ui/intro/frame_beige.png")
## 四个图标的中心占条宽的比例 —— 量自 1917×107 原图：812 / 1077 / 1359 / 1633。
## 顺序 = 行动点 / 演技 / 名声 / 钱，数字挂在图标**右侧**（图标本身几乎顶满条子高，
## 下面是没地方的 —— 量过 bbox：闪电 770~860 × 1~102）。
const HUD_STAT_ANCHORS := [0.424, 0.562, 0.709, 0.852]
## 数字起点离图标中心多远：图标半宽 ≈45 + 间隙 8
const HUD_STAT_OFFSET := 53.0
const HUD_STAT_W := 110.0

## 录像机。**只有它**在被别的 App 顶开时才露自己的返回按钮 ——
## 它的按钮写着中性的「返回」（回到顶开它的那个 App，正是玩家预期）；
## 微信与简历拿来的写着「← 返回桌面」「← 返回微信」——那是它们原来那位宿主的说法，
## 在这台手机上按下去会指错地方，所以那两家的返回按钮仍然只由桌子开（`enable_back`）。
const RECORDER_SCENE := "res://scenes/minigame/recorder.tscn"

## 微信。左栏里**只有它**会有未读角标（见 `_badge_count_for`）
const WECHAT_SCENE := "res://scenes/apps/wechat.tscn"

## 上层（桌子）离开本屏
signal cancelled

## 顶栏内部现在是**绝对定位**（四个数字要正对条子上的图标，HBox 排不出来）
@onready var _hud: Control = get_node(P_HUD)
@onready var _caption: Label = get_node(P_COLUMN + "/ColumnHead/ColumnCaption")
@onready var _column_back: Button = get_node(P_COLUMN + "/ColumnHead/ColumnBack")
@onready var _column_hint: Label = get_node(P_COLUMN + "/ColumnHint")
@onready var _app_list: VBoxContainer = get_node(P_COLUMN + "/AppList")
@onready var _sidebar_host: Control = get_node(P_COLUMN + "/SidebarHost")
@onready var _content: Control = get_node(P_CONTENT)

var _day_label: Label
## 四个数值：行动点 / 演技 / 名声 / 钱（顺序与条子上的图标一致）
var _stat_labels: Array[Label] = []
var _back_button: Button
var _back_enabled := false
## scene_path -> Button（判断某个 App 开着没有、要不要标成选中）
var _app_rows: Dictionary = {}
## scene_path -> 未读角标节点。目前只有微信会亮（事件 + 未读 HR）
var _app_badges: Dictionary = {}
## 当前打开的 App（同一时刻只允许一个）
var _current: Node
var _current_path := ""
## 从 App 手里接管过来的二级列表
var _sidebar: Control
## 当前这个 App 是**被哪个 App 顶开的**（空 = 从左边列表点开的）。
## 【为什么要记】「去录像机」是整屏切走：录完之后玩家得回到微信，才接得上刚才那件事。
## 而录像机不认识微信（决策：它只发 `EventBus.recorder_finished`），
## 所以「回程去哪儿」只能由切屏的这一层记着。
## 【复位点在 `_close_app`】它是唯一的「离开当前 App」出口 —— 换 App、点「← 全部」、
## 返回桌面都会经过它。跨对象留下的成员变量必须有一个明确的复位点，否则会串场。
var _opened_from := ""
## 右栏空着时的提示（开 App 时收起来）
var _empty_hint: Label


func _ready() -> void:
	# 【HUD 先建、样式后刷】`_apply_styles()` 要给「← 桌面」那个按钮上色，
	# 而那个按钮是 `_build_hud()` 造出来的 —— 反过来就跑在 null 上。
	_build_hud()
	_apply_styles()
	_build_app_list()
	_build_empty_hint()
	_show_app_list()

	EventBus.ap_changed.connect(_on_ap_changed)
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.state_reset.connect(_on_state_reset)
	# 录像机点「确认」→ 把玩家送回顶开它的那个 App（表情包已由 `Game` 存进状态）
	EventBus.recorder_finished.connect(_on_recorder_finished)
	# 【左栏角标必须靠信号】微信活在右栏，它那边「回了件事 / 加上一个 HR」
	# 不会有任何东西自己走到左栏来 —— 这四条就是那条通路。
	# 信号带的那些参数（第几天 / 事件 id / 公司代号）这里一个也用不上，`unbind` 掉。
	EventBus.week_event_offered.connect(_on_badge_source_changed.unbind(1))
	EventBus.week_event_resolved.connect(_on_badge_source_changed.unbind(2))
	EventBus.hr_unlocked.connect(_on_badge_source_changed.unbind(1))
	EventBus.day_advanced.connect(_on_badge_source_changed.unbind(2))
	_refresh_hud()
	_refresh_app_badges()


# ============================================================
# 窄状态栏
# ============================================================
func _build_hud() -> void:
	_back_button = Button.new()
	_back_button.text = "返回桌面"
	_back_button.focus_mode = Control.FOCUS_NONE
	_back_button.visible = false
	_back_button.position = Vector2(16, 16)
	_back_button.size = Vector2(176, 74)
	_back_button.add_theme_font_override("font", UiPalette.FONT)
	_back_button.add_theme_font_size_override("font_size", 22)
	_back_button.pressed.connect(func() -> void: cancelled.emit())
	_hud.add_child(_back_button)

	_day_label = _hud_label(Vector2(214, 0), Vector2(340, 107), 23)
	_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	# 四个数字：横向跟着锚点、纵向压在图标下方那条空白带上
	for i in HUD_STAT_ANCHORS.size():
		var l := _hud_label(Vector2.ZERO, Vector2(HUD_STAT_W, 107), 24)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.set_meta("hud_anchor", HUD_STAT_ANCHORS[i])
		_stat_labels.append(l)

	# 【连 HudRow 自己的 resized】`_ready` 里 HudRow 还挂在容器里没布局完，
	# 这时它的宽度是 0；而整屏的尺寸从头到尾没变过，连 self.resized 永远不会来 ——
	# 结果就是四个数字全堆在 (0,0)。等 HudRow 自己量出宽度再摆。
	_hud.resized.connect(_layout_hud_stats)
	_layout_hud_stats()


## 顶栏上的小字：绝对定位、墨色（条子是浅灰纸，奶白字压上去看不见）
func _hud_label(pos: Vector2, box: Vector2, font_size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = box
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", UiPalette.FONT)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", UiPalette.INK)
	_hud.add_child(l)
	return l


## 条子会被横向拉伸（整屏 / 手机右栏两种宽度），数字按比例贴回图标正下方
func _layout_hud_stats() -> void:
	var w := _hud.size.x
	if w <= 1.0:
		return
	for l in _stat_labels:
		var cx: float = float(l.get_meta("hud_anchor")) * w
		l.position = Vector2(cx + HUD_STAT_OFFSET, 0.0)
		l.size = Vector2(HUD_STAT_W, 107.0)


## 窄 = 第几天 / 行动点 / 演技 / 名声 / 钱。
## 属性原来只在日历上，现在图标已经画进状态栏了，顺手一起显示。
func _refresh_hud() -> void:
	_day_label.text = "第 %d 天 · 第 %d 周" % [Game.day(), Game.week()]
	var texts := [
		str(Game.ap_left()), str(Game.acting()), str(Game.fame()), str(Game.money()),
	]
	for i in _stat_labels.size():
		_stat_labels[i].text = texts[i]


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

	# 未读角标（目前只有微信有）：**先建出来、默认隐藏** ——
	# App 行只建一次，之后靠 `_refresh_app_badges()` 开关
	var badge := _make_badge()
	hbox.add_child(badge)
	_app_badges[String(app["scene"])] = badge

	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = String(app["name"])
	UiPalette.title(name_label, 20, UiPalette.TEXT)
	UiBits.one_line(name_label, 20, 220, UiPalette.TITLE_FONT)
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


## 未读角标：红底白字的圆点，默认隐藏。
func _make_badge() -> Panel:
	var dot := Panel.new()
	dot.name = "Badge"
	dot.custom_minimum_size = Vector2(26, 26)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.add_theme_stylebox_override("panel", UiPalette.rounded(UiPalette.DANGER, 13))
	dot.visible = false

	var num := Label.new()
	num.name = "Num"
	num.set_anchors_preset(Control.PRESET_FULL_RECT)
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.add_theme_font_size_override("font_size", 14)
	num.add_theme_color_override("font_color", UiPalette.INK)
	dot.add_child(num)
	return dot


## 每个 App 该亮几个未读。**只有微信有概念** —— 别的 App 没有「等着你处理」的东西，
## 硬凑一个数字只会训练玩家忽略角标。
func _badge_count_for(scene_path: String) -> int:
	if scene_path != WECHAT_SCENE:
		return 0
	if Game.state == null:
		return 0
	return Game.wechat_badge_count()


## 刷新左栏的角标。**必须由信号驱动**：微信在右栏里活着，它那边的状态变化
## （回了件事、加了个 HR）不会自己走到左栏来。
func _refresh_app_badges() -> void:
	for path: String in _app_badges:
		var dot: Panel = _app_badges[path]
		if dot == null:
			continue
		var n := _badge_count_for(path)
		dot.visible = n > 0
		if n > 0:
			(dot.get_node("Num") as Label).text = str(n)


## 上面那四条信号只为了说一件事：「微信那边变了，重算一次角标」。
func _on_badge_source_changed() -> void:
	_refresh_app_badges()


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
		_current.cancelled.connect(_on_app_cancelled)
	# App 之间互相「顶开」：Boss聊完会说「去微信聊」，微信会说「去录像机」。
	# 【为什么由本屏接】切 App 是这一层的事，App 自己不该知道别家住在哪儿 ——
	# 它只发一个场景路径，剩下交给这里（`open_app` 会先关掉当前那个）。
	if _current.has_signal("open_app_requested"):
		_current.open_app_requested.connect(_on_app_requested)
	# 【故意不调 `enable_back()`】那是「被当成整屏打开」时的约定，各 App 的返回按钮
	# 写的是自己原来那位宿主的话（Boss 上写着「返回微信」，本屏根本没有微信那回事）。
	# 现在本屏就是宿主：顶上一条「← 桌面」、左边一列 App，两层导航都齐了 ——
	# 再放一个说不清回哪儿的按钮，只会让玩家点错。
	_empty_hint.visible = false
	_take_sidebar()
	# 周围那圈（状态栏下边线 / 左右两块面板的描边 / 左栏标题）跟着这个 App 换色
	_apply_styles()


# ============================================================
# App 之间互相顶开 / 回程
# ============================================================
## 某个 App 请求「帮我打开另一个 App」（`open_app_requested`）。
##
## 【顺带记下来路】「去录像机」是整屏切走，录完后玩家得回到微信才接得上刚才那件事。
## 录像机不认识微信，所以谁顶开的它、录完就回谁那儿。
func _on_app_requested(scene_path: String) -> void:
	var from := _current_path
	# 【先切再记】`open_app` 内部会 `_close_app()`，而复位点在那边 —— 先记就会被清掉
	open_app(scene_path)
	_opened_from = from
	if scene_path == RECORDER_SCENE and _current != null and _current.has_method("enable_back"):
		_current.enable_back()


## 某个 App 自己的返回按钮被按下（`cancelled`）。
##
## 【有来路就回那个 App】被顶开的 App 上，「上一步」就是顶开它的那个 ——
## 这也是录像机那边「返回」按钮的语义。没来路（从左边列表点开的）就是**离开这个 App**。
##
## 【与「← 全部」的区别】「← 全部」永远是回 App 列表（见 `_back_to_app_list`），
## 它是「我不玩这个了」；这里这条是「上一步」。
func _on_app_cancelled() -> void:
	if _opened_from.is_empty() or _opened_from == _current_path:
		_close_app()
		return
	open_app(_opened_from)


## 录像机录完一段。
##
## 【Clip 不归本屏管】它由核心层接住并写进状态（`Game._on_recorder_finished`）——
## 本屏只做一件界面上的事：把玩家送回顶开录像机的那个 App。
## 不做的话他会停在一个死角里（屏幕上写着「已录好，拿去微信投递」，
## 而对面那个 App 得自己从列表里找回来）。
func _on_recorder_finished(_clip: Clip) -> void:
	if _current_path != RECORDER_SCENE or _opened_from.is_empty():
		return
	open_app(_opened_from)


## 问 App 要它的二级列表，接到左栏来。
## 交给左栏之后，这个列表就归本屏管了（关闭 App 时要自己收掉）。
func _take_sidebar() -> void:
	if not _current.has_method("take_sidebar"):
		return
	var side: Variant = _current.take_sidebar()
	if not (side is Control):
		return
	_sidebar = side as Control
	# 【先把它自己声明的宽度清掉】这些 App 原先都是**各自整屏打开**的，面板上写着自己的宽度
	# （微信的联系人面板写着 `custom_minimum_size = (460, 0)`）。搬到本屏之后，
	# **宽度该由左栏说了算** —— 留着 460 就比 430 的宿主宽出 30px，
	# 那 30px 被隔壁的内容面板盖住，看着就是「左边的手机框显示不全」（提提报的）。
	_sidebar.custom_minimum_size = Vector2.ZERO
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
	if _current.has_signal("cancelled") and _current.cancelled.is_connected(_on_app_cancelled):
		_current.cancelled.disconnect(_on_app_cancelled)
	_current.queue_free()
	_current = null
	_current_path = ""
	# 【来路的唯一复位点】换 App、点「← 全部」、返回桌面都经过这里 ——
	# 漏了它，「上次是谁顶开的」会跟着活到下一次 App 里（跨对象成员变量的老坑）
	_opened_from = ""
	_empty_hint.visible = true
	_show_app_list()
	# 没 App 了 —— 周围那圈退回通用强调色
	_apply_styles()


func _show_app_list() -> void:
	# 【回到列表就算一遍】微信里「点开某个 HR」= 他的未读清掉，但 `mark_hr_read`
	# 没有对应信号（它只是状态）；玩家看得见列表的时机就是这一次，这就算最新的。
	_refresh_app_badges()
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
		# 与「App 自己的返回按钮」走同一条：有来路就回那个 App
		_on_app_cancelled()
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
## 这一屏现在该用哪个强调色：**开着哪个 App 就用那个 App 的品牌色**（微信 = 绿），
## 没开 App 时退回通用的强调色。
## 【为什么周围那圈要跟着换】以前一律用通用的黄 —— 切进微信，里面的图标、气泡都是绿的，
## 外面的框却是黄的，看着不像同一台手机（提提点名）。
## 米色通用框做按钮底：九宫格只拉中间，圆角与手绘描边原地不动
func _beige_style(tint: Color) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = FRAME_BEIGE
	sb.texture_margin_left = 40
	sb.texture_margin_right = 40
	sb.texture_margin_top = 26
	sb.texture_margin_bottom = 26
	sb.modulate_color = tint
	return sb


func _accent() -> Color:
	if _current_path.is_empty():
		return UiPalette.ACCENT
	return AppCatalog.color_of(_current_path)


func _apply_styles() -> void:
	get_node("Bg").color = UiPalette.BG
	# 【屏幕要"亮着"】手机图里那块原来是中灰（像一块没通电的板）；铺一层深色底，
	# 深色底又会被遮罩裁成圆角 + 刘海，看起来才是屏幕。
	get_node("Page/BodyWrap/Body/AppColumn/ScreenMask/ScreenBg").color = UiPalette.BG
	var accent := _accent()

	# 顶栏整条是美术给的手绘纸：两端卷角钉死、中间横向拉伸
	var hud_style := StyleBoxTexture.new()
	hud_style.texture = HUD_BAR_TEX
	hud_style.texture_margin_left = 46
	hud_style.texture_margin_right = 46
	hud_style.texture_margin_top = 10
	hud_style.texture_margin_bottom = 10
	# 内容区不缩进：里面全是绝对定位的控件（数字要正对纸上的图标）
	hud_style.content_margin_left = 0
	hud_style.content_margin_right = 0
	hud_style.content_margin_top = 0
	hud_style.content_margin_bottom = 0
	get_node("Page/HudBar").add_theme_stylebox_override("panel", hud_style)

	# 【左栏不加描边】它现在是美术图里的手机（`phone-本体.png`）—— 描边由那张图自己带。
	# 硬给它套一层圆角框只会在手机外面多出一圈线。右栏仍然跟着当前 App 的颜色。
	get_node("Page/BodyWrap/Body/ContentPanel").add_theme_stylebox_override("panel",
			UiPalette.panel(UiPalette.PANEL, 20, 2, accent))

	# 【兜住以后任何一次越界】外来列表要是还比宿主大，宁可就地裁掉，
	# 也不许它画到隔壁面板上去 —— 那看着正像「右边的把左边的遮了」
	_sidebar_host.clip_contents = true

	# 返回桌面：那张米色通用框当底。浅色系里 hover 不能再往亮里调（白底已经到顶），
	# 改成压暗一档才看得出按下去过
	_back_button.add_theme_stylebox_override("normal", _beige_style(Color(1, 1, 1)))
	_back_button.add_theme_stylebox_override("hover", _beige_style(Color(0.96, 0.95, 0.91)))
	_back_button.add_theme_stylebox_override("pressed", _beige_style(Color(0.9, 0.89, 0.85)))
	_back_button.add_theme_color_override("font_color", UiPalette.INK)
	_back_button.add_theme_color_override("font_hover_color", UiPalette.INK)
	_back_button.add_theme_color_override("font_pressed_color", UiPalette.INK)

	UiPalette.title(_caption, 26, accent)
	UiPalette.text(_column_hint, 15, UiPalette.TEXT_DIM)

	_column_back.focus_mode = Control.FOCUS_NONE
	UiPalette.text(_column_back, 17, UiPalette.TEXT)
	_column_back.add_theme_stylebox_override("normal",
			UiPalette.button(UiPalette.PANEL_SOFT, UiPalette.LINE, 2, 10, 0, 10))
	_column_back.add_theme_stylebox_override("hover",
			UiPalette.button(UiPalette.PANEL_SOFT.lightened(0.1), accent, 2, 10, 0, 10))
