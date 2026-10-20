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
## 【底图】`.document/second/主界面-模糊.png` → `assets/ui/main_menu.png`（1920×1080）。
## 整张是虚焦的桌面，物件比清晰版大一圈 —— 所以按钮改摆画面中间那片木纹，
## 不再挤在左下角。
##
## 【两侧的剧照】和开场压在报纸上的是同一套卡片（`PhotoCard`），
## 摆位避开中间那一列按钮。

const MAIN_SCENE := "res://scenes/main_scene.tscn"
const FONT_CN := preload("res://assets/fonts/main_font.tres")
## 按钮底：`通用框3个.png` 里那个米色框（和演员登记表 / 手机顶栏返回键同一张）
const FRAME_BEIGE := preload("res://assets/ui/intro/frame_beige.png")

## 按钮列：画面中间偏左（手机和笔记本之间那条空木纹），红笔示意的那块
const BTN_X := 760.0
const BTN_Y := 560.0
const BTN_W := 380.0
const BTN_H := 46.0
## 步进 = 高 + 间距(22)：四条纸片各自独立，别贴成一摞
const BTN_STEP := 68.0

## 散在两侧的剧照：左上压绿笔记本、左下压在空木纹上，右侧两张压着那本书
const PHOTO_HOME := [
	{"path": "res://assets/ui/intro/card_smug.png",
			"pos": Vector2(56, 92), "height": 286.0, "angle": -8.0, "delay": 0.25},
	{"path": "res://assets/ui/intro/card_surprise.png",
			"pos": Vector2(44, 612), "height": 244.0, "angle": 7.0, "delay": 0.38},
	{"path": "res://assets/ui/intro/card_sorrow.png",
			"pos": Vector2(1492, 92), "height": 232.0, "angle": 6.0, "delay": 0.31},
	{"path": "res://assets/ui/intro/card_smug.png",
			"pos": Vector2(1476, 606), "height": 300.0, "angle": -7.0, "delay": 0.45},
]

var _dialog: Control


func _ready() -> void:
	if OS.has_feature("headless"):
		call_deferred("_enter_game")
		return
	# 照片先加：它们要压在标题和按钮**下面**（后加的节点画在上面）
	for spec: Dictionary in PHOTO_HOME:
		PhotoCard.add(self, spec)
	_build_title()
	_build_actions()


# ============================================================
# 标题
# ============================================================
## 美术给的艺术字（原图 1840×604）。宽 760 在 1920 画布上约占四成，
## 压不到按钮（标题底 521，按钮从 560 起）。
const TITLE_TEX := preload("res://assets/ui/title.png")
const TITLE_W := 760.0
const TITLE_Y := 272.0


func _build_title() -> void:
	var art := TextureRect.new()
	art.name = "TitleArt"
	art.texture = TITLE_TEX
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.size = Vector2(TITLE_W, TITLE_W * TITLE_TEX.get_height() / TITLE_TEX.get_width())
	# 水平居中于按钮列 —— 换分辨率或改按钮宽度都跟着走
	art.position = Vector2(BTN_X + BTN_W * 0.5 - TITLE_W * 0.5, TITLE_Y)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)


# ============================================================
# 按钮
# ============================================================
func _build_actions() -> void:
	# 【没有存档就不摆「继续游戏」】一个永远点不动的按钮不如不出现 ——
	# 列表里直接过滤掉，后面的按钮自己往上顶，不用留空位。
	var specs: Array[Dictionary] = []
	if Game.loaded_from_save:
		specs.append({"text": "继续游戏", "cb": _on_continue})
	specs.append({"text": "开始游戏", "cb": _on_new_game})
	specs.append({"text": "制作人员", "cb": _show_credits})
	specs.append({"text": "离开游戏", "cb": _on_quit})

	# 少一个按钮时整列往下挪半格 —— 否则 3 个按钮会贴着标题、下面空一大块
	var start_y := BTN_Y
	if specs.size() < 4:
		start_y += (4 - specs.size()) * BTN_STEP * 0.5
	for i in specs.size():
		_action_button(String(specs[i]["text"]), start_y + i * BTN_STEP,
				specs[i]["cb"])


func _action_button(text: String, y: float, cb: Callable) -> Button:
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
	# 底一律是那张米色框：菜单里不再有「主按钮」这个概念（原来给继续游戏上的黄底
	# 在浅木纹上比别的按钮跳一档，看着像两个界面拼起来的）
	b.add_theme_stylebox_override("normal", _beige_style(Color(1, 1, 1)))
	b.add_theme_stylebox_override("hover", _beige_style(Color(0.97, 0.96, 0.92)))
	b.add_theme_stylebox_override("pressed", _beige_style(Color(0.9, 0.89, 0.85)))
	b.pressed.connect(cb)
	add_child(b)
	return b


## 米色通用框做按钮底：九宫格只拉中间，圆角和手绘描边原地不动
func _beige_style(tint: Color) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = FRAME_BEIGE
	sb.texture_margin_left = 40
	sb.texture_margin_right = 40
	sb.texture_margin_top = 26
	sb.texture_margin_bottom = 26
	sb.modulate_color = tint
	return sb


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
		["企划剧本", "犬齿 · 扉三千 · 提提"],
		["程序系统", "提提"],
		["美术界面", "扉三千"],
		["音频", "犬齿"],
		["引擎", "Godot 4.6"],
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
func _label_into(parent: Node, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiPalette.text(l, size, color)
	l.add_theme_font_override("font", FONT_CN)
	parent.add_child(l)
	return l
