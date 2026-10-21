extends Control
## 主界面：一张桌子，桌面上三样东西能点
##
## 【它和两屏的关系】桌子在最外层，三样东西各管一摊（改版后的分工）：
##   「日历」→ `calendar_screen`：**你的日程与进度**（状态栏 + 今日安排 + 本周进度 +
##            结算浮层 + 重开一局）—— 今天该做什么在这儿决定
##   「手机」→ `phone_screen`：那 4 个 App（左栏列表 / 右栏内容）
##   「抄录手册」→ `notebook_screen`：检阅重要的笔记（贴纸笔记 / 单页全文）
## 两屏都支持「返回桌面」（`cancelled` + `enable_back()`），与录像机 / 微信 /
## Boss直聘 被嵌进手机时用的是同一套约定。
##
## 【底图怎么换】四张图是同一张桌子的四个状态（`assets/ui/desk/desk_*.jpg`），
## 尺寸都是 1920×1080、物件位置也一致 ——
## 鼠标停到哪个热点上就把底图换成它的 `active_texture`，离开换回 `off_texture`。
## 「未选择」与三张激活图都是整张的，不做局部叠图。
## 【热点的像素值跟着图走】换底图时若物件挪了位，`scenes/main/desk_screen.tscn`
## 里三个 `Hotspots/*` 的 offset 要跟着改，否则悬停/点击会落在空处。
##
## 【怎么加热点】在 `scenes/main/desk_screen.tscn` 里选中 `Hotspots` 下的节点，
## 拖边框对齐手绘图，然后填 `激活图` / `目标场景` 两个属性 —— 不用改代码。

const PHONE_SCENE := "res://scenes/main/phone_screen.tscn"

## GM 控制台脚本。**用 `preload` 而不是 `class_name`** —— 那个脚本满篇 `Game.state`，
## 一旦它有了全局类名，`tools/*.gd`（`--script` 跑的，编译早于 autoload 注册）
## 一引用这个类型就会把连带编译搞崩。preload 在这里是运行时才展开的。
## 【不 preload，只记路径】`scripts/debug/*` 在导出预设的 `exclude_filter` 里 ——
## release 包里这个文件**根本不存在**。写成 `preload` 的话，导出阶段就会因为
## 「资源找不到」直接构建失败；字符串 + 运行时 `load()` 才能让它在包里彻底消失。
const GM_CONSOLE_PATH := "res://scripts/debug/gm_console.gd"

## 未选择时的那张底图（四张里「什么都不亮」的那张）
@export var off_texture: Texture2D
## 打开的功能盖在哪个节点下。留空 = 盖在本节点下
@export var overlay_parent: Control
## 「手机」那个热点（App 都住在它里面）。留空就按场景路径去找 ——
## 日历上的「去投递」需要跨屏跳到手机的微信里，桌子是唯一知道该怎么走的一层。
@export var app_hotspot: Hotspot

const PAUSE_SCENE := preload("res://scenes/ui/pause_menu.tscn")
## 左上角那颗「菜单」图标：普通 / 悬停 两态（美术给的是竖排合并图，已拆开）
const ICON_MENU := preload("res://assets/ui/icon_menu.png")
const ICON_MENU_HOVER := preload("res://assets/ui/icon_menu_hover.png")

@onready var _bg: TextureRect = $Bg
@onready var _hotspots: Control = $Hotspots

## 左上角那颗「菜单」按钮（点开游戏内菜单）
var _menu_button: TextureButton
var _pause_menu: Control

## 当前打开的功能（点手机进来的手机壳）
var _open: Node
## 鼠标此刻停着的热点
var _current: Hotspot


func _ready() -> void:
	if off_texture != null:
		_bg.texture = off_texture
	for node: Node in _hotspots.get_children():
		var h := node as Hotspot
		if h == null:
			continue
		h.hovered.connect(_on_hovered)
		h.unhovered.connect(_on_unhovered)
		h.activated.connect(_on_activated)
	# 【GM 控制台只活在调试构建里】两道锁：
	#   1. release 导出包里 `OS.is_debug_build()` 为假；
	#   2. 更硬的一层：`scripts/debug/*` 被 `exclude_filter` 排除，包里**没有这个文件**，
	#      `ResourceLoader.exists()` 直接为假 —— 就算有人改了判断条件也无从加载。
	# 动态 new 而不是写进 `.tscn`：桌子场景不该为了调试多一个节点。
	if OS.is_debug_build() and ResourceLoader.exists(GM_CONSOLE_PATH):
		var script: GDScript = load(GM_CONSOLE_PATH)
		if script != null:
			var gm: Node = script.new()
			gm.name = "GmConsole"
			add_child(gm)

	_build_menu_button()


# ============================================================
# 游戏内菜单
# ============================================================
## 左上角那颗图标。压在日历热点左上角一点点 —— 桌面最左边只有 89px 宽，
## 再往右就会盖住日历本体。
## 两态各自居中：hover 那张比普通那张大一圈（橙框撑着），居中摆放就不会「跳」。
func _build_menu_button() -> void:
	_menu_button = TextureButton.new()
	_menu_button.name = "MenuButton"
	_menu_button.texture_normal = ICON_MENU
	_menu_button.texture_hover = ICON_MENU_HOVER
	_menu_button.texture_pressed = ICON_MENU_HOVER
	_menu_button.ignore_texture_size = true
	_menu_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_menu_button.position = Vector2(12, 8)
	_menu_button.size = Vector2(100, 100)
	_menu_button.focus_mode = Control.FOCUS_NONE
	_menu_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_menu_button.pressed.connect(_open_pause_menu)
	add_child(_menu_button)


func _open_pause_menu() -> void:
	if _pause_menu != null and is_instance_valid(_pause_menu):
		return
	_pause_menu = PAUSE_SCENE.instantiate()
	# 菜单自己 queue_free，这里只把引用放掉，免得下一次判断还认着旧节点
	_pause_menu.closed.connect(func() -> void: _pause_menu = null)
	add_child(_pause_menu)


func _on_hovered(h: Hotspot) -> void:
	_current = h
	# 【提示文字也只能留一条】鼠标从 A 滑到 B 时 entered / exited 的先后不保证；
	# 不先收掉其它热点的话，两句话会同时压进同一个气泡。
	for node: Node in _hotspots.get_children():
		var other := node as Hotspot
		if other != null and other != h:
			other.hide_hint()
	h.show_hint()
	if h.active_texture != null:
		_bg.texture = h.active_texture


func _on_unhovered(h: Hotspot) -> void:
	# 【为什么要判一次 _current】鼠标从一个热点直接滑到另一个上时，
	# 两个事件的先后并不保证 —— 不判的话，晚到的那次 exited 会把刚换上的
	# 「激活图」又打回未选择，表现是悬停时图闪一下就没了。
	if _current != h:
		return
	_current = null
	h.hide_hint()
	if off_texture != null:
		_bg.texture = off_texture


func _on_activated(h: Hotspot) -> void:
	if h.target_scene == null or _open != null:
		return
	# 功能盖上来之后气泡会被挡住；先把提示收掉，回来后不会留一条悬空文案
	h.hide_hint()
	_open = h.target_scene.instantiate()
	var host: Node = overlay_parent if overlay_parent != null else self
	host.add_child(_open)
	# 打开的功能要是支持「返回」，让它自己发 cancelled 回来；
	# 不支持的（还没有返回入口的）就暂时只能靠重开场景
	if _open.has_signal("cancelled"):
		_open.cancelled.connect(_close_open)
	# 日历上「去投递」那张卡要把玩家送进手机的微信 —— 跨屏的跳转只有桌子知道怎么走
	if _open.has_signal("open_app_requested"):
		_open.open_app_requested.connect(_on_open_app_requested)
	if _open.has_method("enable_back"):
		_open.enable_back()


## 某个屏请求「帮我打开这个 App」：关掉当前屏，打开手机屏，再让它开那个 App
func _on_open_app_requested(scene_path: String) -> void:
	var phone := _phone_hotspot()
	if phone == null:
		push_error("[DeskScreen] 找不到「手机」热点，没法把玩家送过去")
		return
	_close_open()
	_on_activated(phone)
	if _open != null and _open.has_method("open_app"):
		_open.open_app(scene_path)


## 哪个热点是手机。优先用编辑器里指定的，没指定就按目标场景路径认 ——
## 【为什么不写死节点名】改版时挪动热点不该连累这里。
func _phone_hotspot() -> Hotspot:
	if app_hotspot != null:
		return app_hotspot
	for node: Node in _hotspots.get_children():
		var h := node as Hotspot
		if h != null and h.target_scene != null \
				and h.target_scene.resource_path == PHONE_SCENE:
			return h
	return null


## 关掉当前功能，回到桌面（底图顺手复位）
func _close_open() -> void:
	if _open == null:
		return
	_open.queue_free()
	_open = null
	if _current != null:
		_current.hide_hint()
	_current = null
	if off_texture != null:
		_bg.texture = off_texture


## 桌面上现在有没有打开着功能（测试与调试用）
func has_open_screen() -> bool:
	return _open != null
