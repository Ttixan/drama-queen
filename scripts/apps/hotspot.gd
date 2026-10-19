class_name Hotspot
extends Control
## 桌面上一个「可以点的地方」—— 悬浮换整张底图，点击进某个功能
##
## 【为什么是场景里的节点，而不是一张数据表】
## 热点的矩形要和**底图上的物件对齐**，而这件事只有在编辑器里对着图拖边框才做得准
## （填数字得来回试十几次）。所以每个热点就是场景里的一个 `Control`：
## 选中它、拖四个角、在图上看效果。`_draw()` 会在编辑器里给一层淡色 +
## 名字，不然它平时是全透明的，根本没法对着底图调。
##
## 【矩形为什么能用像素】项目是 `1920×1080` + `canvas_items` / `keep` 拉伸
## （见 `project.godot`）—— 所有 UI 都在这个虚拟分辨率里，底图是 1920×1080，
## 热点也在同一套坐标里，不需要另做换算。
##
## 【悬浮换的是整张底图，不是叠一层高亮】四张图是**同一张桌子的四个状态**
## （未选择 / 日历 / 手机 / 抄录手册），尺寸都是 1920×1080、物件位置也一致，
## 所以「选中」= 把底图换掉，热点只需要按「未选择」那张摆一次。
## 提示气泡形状画在那四张图里，等于白送；气泡里的**说明文案**由 `hint` 在运行时压上去
## （见 `hint_rect` 的注释：用桌面坐标，因为气泡在热点矩形外）。

## 悬浮时替换上去的整张底图。留空 = 悬浮不变图（热点照样能点）
@export var active_texture: Texture2D
## 点击后打开的场景。留空 = 点了没反应（功能还没做）
@export var target_scene: PackedScene
## 给编辑器与调试那层框看的名字
@export var label: String = ""
## 运行时是否画出这块区域（平时关着；调位置时可以开）
@export var show_rect_at_runtime: bool = false

## 悬浮时显示在底图黄色气泡里的说明。留空 = 不显示
@export_multiline var hint: String = ""
## 说明文字在 **1920×1080 桌面坐标** 里的位置。不是热点局部坐标 ——
## 日历/手机的气泡其实画在热点矩形外面，用局部坐标会得到负数，
## 所以文案标签挂在全屏的 `Hotspots` 下，和底图共用一套坐标。
@export var hint_rect: Rect2 = Rect2(0, 0, 320, 80)
@export var hint_font_size: int = 44

signal hovered(hotspot: Hotspot)
signal unhovered(hotspot: Hotspot)
signal activated(hotspot: Hotspot)

var _hint_label: Label


func _ready() -> void:
	# 鼠标必须能被这块区域接住，否则悬浮与点击都收不到
	mouse_filter = Control.MOUSE_FILTER_STOP
	if mouse_default_cursor_shape == Control.CURSOR_ARROW:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_build_hint()
	# 【桌面热点为什么不靠 Sfx 的全局挂钩】那套只认 BaseButton，而热点是
	# 为了"拖边框对齐底图"才做成 Control 的（见文件头）。所以这两下自己出声。
	mouse_entered.connect(func() -> void:
		Sfx.play(&"ui_hover")
		show_hint()
		hovered.emit(self))
	mouse_exited.connect(func() -> void:
		hide_hint()
		unhovered.emit(self))
	# 拖动/改尺寸时把那层淡淡的框重画 —— 不然它停在旧位置，越调越乱
	item_rect_changed.connect(queue_redraw)
	queue_redraw()


## 黄色气泡里的说明文字。用标题字重 —— 它是「这个热点能干什么」的一句话标题，
## 不是正文；气泡本身只有 200 多像素高，Light 在那个尺寸下发虚。
func _build_hint() -> void:
	if hint.strip_edges().is_empty():
		return
	var host := get_parent()
	if host == null:
		return
	_hint_label = Label.new()
	_hint_label.text = hint
	_hint_label.position = hint_rect.position
	_hint_label.size = hint_rect.size
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.title(_hint_label, hint_font_size, UiPalette.INK)
	_hint_label.visible = false
	# 【为什么 deferred】热点 `_ready` 时父节点还在装子节点，立即 add_child 会被拒
	# （"Parent node is busy setting up children"）。挂到帧末，坐标仍按桌面算。
	host.add_child.call_deferred(_hint_label)


## 提示的显示 / 隐藏由桌子统一调度（见 `desk_screen._on_hovered`）：
## 鼠标从 A 滑到 B 时 entered / exited 的先后不保证，热点自己各显各的
## 会让两句话同时压在同一个气泡里。桌子收到 hovered 后先收掉其它热点，再开这一个。
func show_hint() -> void:
	if _hint_label != null:
		_hint_label.visible = true


func hide_hint() -> void:
	if _hint_label != null:
		_hint_label.visible = false


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	Sfx.play(&"ui_click")
	activated.emit(self)


func _draw() -> void:
	if not (Engine.is_editor_hint() or show_rect_at_runtime):
		return
	var rect := Rect2(Vector2.ZERO, size)
	var fill := Color(1.0, 0.84, 0.28, 0.14 if Engine.is_editor_hint() else 0.3)
	draw_rect(rect, fill, true)
	draw_rect(rect, Color(1.0, 0.84, 0.28, 0.55), false, 2.0)
	if not label.is_empty():
		# 调试标签也用全局那支字体，免得同一屏里出现两种字形
		draw_string(UiPalette.FONT, Vector2(10, 30), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.1, 0.1, 0.1, 0.85))
