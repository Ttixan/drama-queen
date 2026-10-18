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
## 提示气泡画在那四张图里，等于白送。

## 悬浮时替换上去的整张底图。留空 = 悬浮不变图（热点照样能点）
@export var active_texture: Texture2D
## 点击后打开的场景。留空 = 点了没反应（功能还没做）
@export var target_scene: PackedScene
## 给编辑器与调试那层框看的名字
@export var label: String = ""
## 运行时是否画出这块区域（平时关着；调位置时可以开）
@export var show_rect_at_runtime: bool = false

signal hovered(hotspot: Hotspot)
signal unhovered(hotspot: Hotspot)
signal activated(hotspot: Hotspot)


func _ready() -> void:
	# 鼠标必须能被这块区域接住，否则悬浮与点击都收不到
	mouse_filter = Control.MOUSE_FILTER_STOP
	if mouse_default_cursor_shape == Control.CURSOR_ARROW:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# 【桌面热点为什么不靠 Sfx 的全局挂钩】那套只认 BaseButton，而热点是
	# 为了"拖边框对齐底图"才做成 Control 的（见文件头）。所以这两下自己出声。
	mouse_entered.connect(func() -> void:
		Sfx.play(&"ui_hover")
		hovered.emit(self))
	mouse_exited.connect(func() -> void: unhovered.emit(self))
	# 拖动/改尺寸时把那层淡淡的框重画 —— 不然它停在旧位置，越调越乱
	item_rect_changed.connect(queue_redraw)
	queue_redraw()


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
		draw_string(ThemeDB.fallback_font, Vector2(10, 30), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.1, 0.1, 0.1, 0.85))
