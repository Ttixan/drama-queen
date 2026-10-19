extends Control
## 开始界面 —— 每次启动的第一屏
##
## 【为什么它是 main_scene，而不是盖在桌子上的又一层】
## 「继续 / 新游戏」必须在**桌面建起来之前**决定：`desk_screen` 在 `_ready()` 里照着
## `Game.state` 建界面，先建再换状态会闪一帧旧数据。换场景也更干净 —— 菜单里那些
## 全屏遮罩、弹窗不会跟着进游戏。
##
## 【headless 直接进游戏】冒烟测试与导出校验不该卡在菜单上等点击。
## 与 `main.gd` 里「headless 不挂开场」是同一条口径。
##
## 【底图】`.document/second/主界面-清晰.png` → `assets/ui/main_menu.png`（1920×1080）。
## 素材在左边留了一大片空木纹，按钮就摆在那儿，不遮笔记本、手机和右侧那本。

const MAIN_SCENE := "res://scenes/main_scene.tscn"
const FONT_CN := preload("res://assets/fonts/main_font.tres")
const TITLE_FONT := preload("res://assets/fonts/title_font.tres")

## 按钮列（1920×1080 绝对坐标，压在左下角那块空木纹上）
const BTN_X := 132.0
const BTN_Y := 796.0
const BTN_W := 380.0
const BTN_H := 54.0
## 步进 = 高 + 间距(16)。原来间距只有 8，四个按钮叠成一根柱子；
## 阴影又往下压 4px，视觉上几乎连在一起。
const BTN_STEP := 70.0

var _dialog: Control


func _ready() -> void:
	if OS.has_feature("headless"):
		call_deferred("_enter_game")
		return
	_build_title()
	_build_actions()


# ============================================================
# 标题
# ============================================================
func _build_title() -> void:
	# 【为什么压在 700 以下】底图左上那本绿笔记本一直画到 y≈690，
	# 标题落在它上面会被绿色吃掉一半，字读不清
	var title_label := _label("有瓜有戏", 44, UiPalette.INK,
			Rect2(BTN_X, 700, 560, 58), TITLE_FONT)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 英文放在中文右侧做 lockup：竖排两行时 18 号字夹在标题和按钮之间，
	# 缩到 1080p 以下就会糊成一团
	_label("DRAMA QUEEN", 19, Color(UiPalette.INK, 0.62),
			Rect2(BTN_X + 210, 718, 300, 26))


# ============================================================
# 按钮
# ============================================================
func _build_actions() -> void:
	var has_save: bool = Game.loaded_from_save
	var specs: Array[Dictionary] = [
		{"text": "继续游戏", "primary": has_save, "enabled": has_save,
				"cb": _on_continue},
		{"text": "开始游戏", "primary": not has_save, "enabled": true,
				"cb": _on_new_game},
		{"text": "制作人员", "primary": false, "enabled": true,
				"cb": _show_credits},
		{"text": "离开游戏", "primary": false, "enabled": true,
				"cb": _on_quit},
	]
	for i in specs.size():
		var spec: Dictionary = specs[i]
		_action_button(String(spec["text"]), BTN_Y + i * BTN_STEP,
				bool(spec["primary"]), bool(spec["enabled"]), spec["cb"])


func _action_button(text: String, y: float, primary: bool, enabled: bool,
		cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = Vector2(BTN_X, y)
	b.size = Vector2(BTN_W, BTN_H)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", FONT_CN)
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", UiPalette.INK)
	b.add_theme_color_override("font_hover_color", UiPalette.INK)
	b.add_theme_color_override("font_pressed_color", UiPalette.INK)
	b.add_theme_color_override("font_disabled_color", UiPalette.TEXT_DISABLED)

	var normal := UiPalette.ACCENT if primary else UiPalette.PAPER
	var hover := Color("ffe071") if primary else UiPalette.PAPER_HOVER
	var pressed := Color("e6bd35") if primary else UiPalette.PAPER_SOFT
	b.add_theme_stylebox_override("normal", _btn_style(normal))
	b.add_theme_stylebox_override("hover", _btn_style(hover))
	b.add_theme_stylebox_override("pressed", _btn_style(pressed))
	b.add_theme_stylebox_override("disabled",
			_btn_style(UiPalette.PAPER_DISABLED, UiPalette.PAPER_LINE, false))
	b.disabled = not enabled
	b.pressed.connect(cb)
	add_child(b)
	return b


## 纸片按钮：2px 墨线 + 往右下一点的投影，压在木桌上才有实物感
func _btn_style(bg: Color, border := UiPalette.INK, shadow := true) -> StyleBoxFlat:
	var sb := UiPalette.button(bg, border, 2, 12)
	if shadow:
		sb.shadow_color = Color(0, 0, 0, 0.22)
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(0, 4)
	return sb


# ============================================================
# 按钮行为
# ============================================================
func _on_continue() -> void:
	_enter_game()


func _on_new_game() -> void:
	# 有存档时先问一句：重开意味着那份进度不再往下走（虽然文件还在，
	# 但下一次周结算就会把它覆盖）。不弹窗的话，手滑点一下就是一周白干。
	if Game.loaded_from_save:
		_show_confirm()
		return
	_start_new_game()


func _start_new_game() -> void:
	Game.new_game()
	_enter_game()


func _on_quit() -> void:
	get_tree().quit()


func _enter_game() -> void:
	var err := get_tree().change_scene_to_file(MAIN_SCENE)
	if err != OK:
		push_error("[Menu] 进不去主场景：%s" % error_string(err))


# ============================================================
# 弹窗（确认重开 / 制作人员）
# ============================================================
func _show_confirm() -> void:
	_show_dialog("开始新游戏？", "当前进度会在下一次周结算时被覆盖。",
			"重开一局", _start_new_game)


func _show_credits() -> void:
	_dialog = _dialog_layer(Vector2(580, 292), Vector2(760, 496))
	var box := _dialog_body(_dialog, "制作人员")

	for row: Array in [
		["企划 / 剧本", "待填"],
		["程序 / 系统", "待填"],
		["美术 / 界面", "待填"],
		["音频", "待填"],
		["引擎", "Godot 4.6"],
		["字体", "獅尾半月字體 · SIL OFL 1.1"],
	]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 24)
		box.add_child(line)
		var key := Label.new()
		key.text = String(row[0])
		key.custom_minimum_size = Vector2(200, 0)
		UiPalette.text(key, 21, UiPalette.PAGE_INK_SOFT)
		key.add_theme_font_override("font", FONT_CN)
		line.add_child(key)
		var value := Label.new()
		value.text = String(row[1])
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiPalette.text(value, 21, UiPalette.INK)
		value.add_theme_font_override("font", FONT_CN)
		line.add_child(value)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	_label_into(box, "点击卡片外返回", 17, UiPalette.PAGE_INK_FAINT)


func _show_dialog(title_text: String, body: String, ok_text: String,
		on_ok: Callable) -> void:
	_dialog = _dialog_layer(Vector2(640, 352), Vector2(640, 320))
	var box := _dialog_body(_dialog, title_text)

	var text := Label.new()
	text.text = body
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiPalette.text(text, 21, UiPalette.PAGE_INK_SOFT)
	text.add_theme_font_override("font", FONT_CN)
	box.add_child(text)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)

	var cancel := _dialog_button("取消", false)
	cancel.pressed.connect(_close_dialog)
	row.add_child(cancel)

	var ok := _dialog_button(ok_text, true)
	ok.pressed.connect(func() -> void:
		_close_dialog()
		on_ok.call())
	row.add_child(ok)


## 全屏暗罩 + 居中纸片。点暗罩关闭（弹窗没有「叉」，标准做法是点外面走人）
func _dialog_layer(pos: Vector2, size: Vector2) -> Control:
	_close_dialog()

	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_close_dialog())
	layer.add_child(dim)

	var card := PanelContainer.new()
	card.position = pos
	card.size = size
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := UiPalette.panel(UiPalette.PAPER, 8, 3, UiPalette.INK)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 20
	style.shadow_offset = Vector2(0, 10)
	card.add_theme_stylebox_override("panel", style)
	layer.add_child(card)
	return layer


## 卡片内边距 + 标题 + 返回的 VBox，调用方往里加正文
func _dialog_body(layer: Control, title_text: String) -> VBoxContainer:
	var card := layer.get_child(layer.get_child_count() - 1) as PanelContainer
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 46)
	margin.add_theme_constant_override("margin_right", 46)
	margin.add_theme_constant_override("margin_top", 38)
	margin.add_theme_constant_override("margin_bottom", 34)
	card.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)

	var head := Label.new()
	head.text = title_text
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiPalette.title(head, 32, UiPalette.INK)
	box.add_child(head)

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 3)
	rule.color = Color(UiPalette.INK, 0.8)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	return box


func _dialog_button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(160, 54)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", FONT_CN)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", UiPalette.INK)
	b.add_theme_color_override("font_hover_color", UiPalette.INK)
	b.add_theme_color_override("font_pressed_color", UiPalette.INK)
	var bg := UiPalette.ACCENT if primary else UiPalette.PAPER_SOFT
	b.add_theme_stylebox_override("normal", _btn_style(bg))
	b.add_theme_stylebox_override("hover",
			_btn_style(Color("ffe071") if primary else UiPalette.PAPER))
	b.add_theme_stylebox_override("pressed",
			_btn_style(Color("e6bd35") if primary else UiPalette.PAPER_HOVER))
	return b


func _close_dialog() -> void:
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = null


func _unhandled_key_input(ev: InputEvent) -> void:
	if _dialog != null and ev.is_action_pressed("ui_cancel"):
		_close_dialog()
		get_viewport().set_input_as_handled()


# ============================================================
# 排版小工具
# ============================================================
func _label(text: String, size: int, color: Color, rect: Rect2,
		font: Font = FONT_CN) -> Label:
	var l := Label.new()
	l.text = text
	l.position = rect.position
	l.size = rect.size
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiPalette.text(l, size, color)
	l.add_theme_font_override("font", font)
	add_child(l)
	return l


func _label_into(parent: Node, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiPalette.text(l, size, color)
	l.add_theme_font_override("font", FONT_CN)
	parent.add_child(l)
	return l
