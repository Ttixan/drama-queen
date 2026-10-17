extends Control
## 主界面：一张桌子，桌面上三样东西能点
##
## 【它和两屏的关系】桌子在最外层，三样东西各管一摊（改版后的分工）：
##   「日历」→ `calendar_screen`：**你的日程与进度**（状态栏 + 今日安排 + 本周进度 +
##            结算浮层 + 重开一局）—— 今天该做什么在这儿决定
##   「手机」→ `phone_screen`：那 4 个 App（左栏列表 / 右栏内容）
##   「抄录手册」→ 还没定（热点上留空，点了没反应）
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
const GM_CONSOLE := preload("res://scripts/debug/gm_console.gd")

## 未选择时的那张底图（四张里「什么都不亮」的那张）
@export var off_texture: Texture2D
## 打开的功能盖在哪个节点下。留空 = 盖在本节点下
@export var overlay_parent: Control
## 「手机」那个热点（App 都住在它里面）。留空就按场景路径去找 ——
## 日历上的「去投递」需要跨屏跳到手机的微信里，桌子是唯一知道该怎么走的一层。
@export var app_hotspot: Hotspot

@onready var _bg: TextureRect = $Bg
@onready var _hotspots: Control = $Hotspots

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
	# 【GM 控制台只活在调试构建里】它是开发期工具，不是玩法 ——
	# release 导出包里 `OS.is_debug_build()` 为假，这一段整个不存在。
	# 动态 new 而不是写进 `.tscn`：桌子场景不该为了调试多一个节点。
	if OS.is_debug_build():
		var gm: Node = GM_CONSOLE.new()
		gm.name = "GmConsole"
		add_child(gm)


func _on_hovered(h: Hotspot) -> void:
	_current = h
	if h.active_texture != null:
		_bg.texture = h.active_texture


func _on_unhovered(h: Hotspot) -> void:
	# 【为什么要判一次 _current】鼠标从一个热点直接滑到另一个上时，
	# 两个事件的先后并不保证 —— 不判的话，晚到的那次 exited 会把刚换上的
	# 「激活图」又打回未选择，表现是悬停时图闪一下就没了。
	if _current != h:
		return
	_current = null
	if off_texture != null:
		_bg.texture = off_texture


func _on_activated(h: Hotspot) -> void:
	if h.target_scene == null or _open != null:
		return
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
	_current = null
	if off_texture != null:
		_bg.texture = off_texture


## 桌面上现在有没有打开着功能（测试与调试用）
func has_open_screen() -> bool:
	return _open != null
