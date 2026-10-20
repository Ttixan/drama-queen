extends Control
## 游戏内菜单 —— 点桌面左上角那颗按钮打开
##
## 【背景为什么是「开始界面那张图」】`assets/ui/main_menu.png` 是同一张桌子的**模糊版**。
## 铺满 + 压一层暗罩，读起来就是「游戏停在这一刻，镜头失焦了」——
## 比直接给当前画面盖黑布更像一个独立页面。
##
## 【两个「重开」都要确认】它们都丢进度：重开本周退回周初，重开游戏清空整局。
## 点错一次就是一周白干，所以确认框不是可选项。
##
## 【确认框的底】`通用信息框.png`：米色纸 + 顶部青条 + 右上折角。
## 顶部那 46px 在九宫格里钉死（青条不跟着拉伸），正文区才拉伸。

signal closed

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const BG_TEX := preload("res://assets/ui/main_menu.png")
const FRAME_BEIGE := preload("res://assets/ui/intro/frame_beige.png")
const DIALOG_TEX := preload("res://assets/ui/dialog_frame.png")
const FONT_CN := preload("res://assets/fonts/main_font.tres")

const BTN_W := 380.0
const BTN_H := 46.0
const BTN_STEP := 68.0
## 四个按钮竖向居中（4×46 + 3×22 = 250，从 415 到 665）
const BTN_TOP := 415.0

var _toast: Label
var _dialog: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_backdrop()
	_build_buttons()


# ============================================================
# 外观
# ============================================================
func _build_backdrop() -> void:
	var bg := TextureRect.new()
	bg.texture = BG_TEX
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.05, 0.04, 0.38)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	# 点空白处关掉菜单（和 ESC 两条路，玩家不用猜）
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_close())
	add_child(dim)


func _build_buttons() -> void:
	var actions := [
		{"text": "存档", "cb": _on_save},
		{"text": "重开本周", "cb": _on_restart_week},
		{"text": "重开游戏", "cb": _on_restart_game},
		{"text": "返回主界面", "cb": _on_back_to_menu},
	]
	for i in actions.size():
		_menu_button(String(actions[i]["text"]), BTN_TOP + i * BTN_STEP,
				actions[i]["cb"])

	_toast = Label.new()
	_toast.position = Vector2(760, 700)
	_toast.size = Vector2(400, 40)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	_toast.add_theme_font_override("font", FONT_CN)
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_color_override("font_color", UiPalette.INK)
	add_child(_toast)


func _menu_button(text: String, y: float, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = Vector2(960.0 - BTN_W * 0.5, y)
	b.size = Vector2(BTN_W, BTN_H)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", FONT_CN)
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", UiPalette.INK)
	b.add_theme_color_override("font_hover_color", UiPalette.INK)
	b.add_theme_color_override("font_pressed_color", UiPalette.INK)
	b.add_theme_stylebox_override("normal", _beige_style(Color(1, 1, 1)))
	b.add_theme_stylebox_override("hover", _beige_style(Color(0.97, 0.96, 0.92)))
	b.add_theme_stylebox_override("pressed", _beige_style(Color(0.9, 0.89, 0.85)))
	b.pressed.connect(cb)
	add_child(b)
	return b


## 米色通用框做底：九宫格只拉中间，圆角与手绘描边原地不动
func _beige_style(tint: Color, height := 46.0) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = FRAME_BEIGE
	sb.texture_margin_left = 40
	sb.texture_margin_right = 40
	sb.texture_margin_top = 26
	sb.texture_margin_bottom = 26
	sb.modulate_color = tint
	return sb


# ============================================================
# 四个动作
# ============================================================
func _on_save() -> void:
	var err := Game.save_to()
	_show_toast("已存档" if err == OK else "存档失败：" + error_string(err))


## 存档结果用一行小字反馈 —— 存档没有界面，不给反馈玩家会连点三次
func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.4)


func _on_restart_week() -> void:
	_confirm("确认重新开始？", "重开", func() -> void:
		Game.restart_week()
		_close())


func _on_restart_game() -> void:
	_confirm("确认重新开始？", "重开", func() -> void:
		Game.new_game()
		# 【为什么整场景重载】桌子、手机、微信都还挂着上一局的数据；
		# 让 `main_scene` 按新状态重建一遍最干净（开场也会跟着回来）。
		if get_tree().current_scene != null:
			get_tree().call_deferred("reload_current_scene")
		else:
			_close())


## 「返回主界面」= 回到开始界面（那个选「继续 / 开始」的画面）。
## 它等于离开这一局，所以也要确认。
func _on_back_to_menu() -> void:
	_confirm("确认返回主界面？", "返回", func() -> void:
		var err := get_tree().change_scene_to_file(MENU_SCENE)
		if err != OK:
			push_error("[PauseMenu] 回不到开始界面：%s" % error_string(err)))


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _dialog != null:
		_close_dialog()
	else:
		_close()
	get_viewport().set_input_as_handled()


# ============================================================
# 确认框（底图：通用信息框）
# ============================================================
## 【为什么没有说明小字】确认框只回答「要不要」，一句标题 + 两个按钮就够；
## 再补一行解释反而让人先读说明再读标题。这条对以后所有弹窗都成立。
func _confirm(title: String, ok_text: String, on_ok: Callable) -> void:
	_close_dialog()
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	_dialog = layer

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_close_dialog())
	layer.add_child(dim)

	# 【为什么用 Panel 不用 PanelContainer】里面的标题/正文/按钮都按纸上位置绝对摆，
	# 容器会把它们全部铺满 —— 青条上的标题就没法只占那一条
	var card := Panel.new()
	card.position = Vector2(600, 380)
	card.size = Vector2(720, 320)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxTexture.new()
	style.texture = DIALOG_TEX
	style.texture_margin_left = 30
	style.texture_margin_right = 30
	style.texture_margin_top = 46       # 青条高度，钉死不拉伸
	style.texture_margin_bottom = 20
	card.add_theme_stylebox_override("panel", style)
	layer.add_child(card)

	# 标题压在框中央：加大加粗，一句话说清要发生什么（不写说明小字）
	var head := Label.new()
	head.position = Vector2(34, 108)
	head.size = Vector2(652, 58)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.text = title
	head.add_theme_font_override("font", UiPalette.TITLE_FONT)
	head.add_theme_font_size_override("font_size", 34)
	head.add_theme_color_override("font_color", UiPalette.INK)
	card.add_child(head)

	# 两个按钮整体居中于卡片中轴：总宽 150+20+150 = 320 → 从 200 起
	# 顺序是「确认在左、取消在右」
	var ok := _dialog_button(ok_text, true)
	ok.position = Vector2(200, 212)
	ok.pressed.connect(func() -> void:
		_close_dialog()
		on_ok.call())
	card.add_child(ok)

	var cancel := _dialog_button("取消", false)
	cancel.position = Vector2(370, 212)
	cancel.pressed.connect(_close_dialog)
	card.add_child(cancel)


func _dialog_button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.size = Vector2(150, 50)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", FONT_CN)
	b.add_theme_font_size_override("font_size", 21)
	b.add_theme_color_override("font_color", UiPalette.INK)
	b.add_theme_color_override("font_hover_color", UiPalette.INK)
	b.add_theme_color_override("font_pressed_color", UiPalette.INK)
	var normal := Color(1, 1, 1) if primary else Color(0.96, 0.95, 0.91)
	b.add_theme_stylebox_override("normal", _beige_style(normal))
	b.add_theme_stylebox_override("hover", _beige_style(Color(0.94, 0.93, 0.88)))
	b.add_theme_stylebox_override("pressed", _beige_style(Color(0.88, 0.87, 0.83)))
	return b


func _close_dialog() -> void:
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = null
