extends Control
## 开场导入 —— A1 报纸广告 → A2/A3 AVG 独白 → 取名
##
## 【为什么不是一整段黑底文字流】A1 是「广告」、A2 是「回到现实」、A3 是「决定」
## 三种语气。用一张报纸 + 一个对话框分开，玩家一眼能看出「现在在读什么」；
## 全程黑底文字流更像在读开发文档。
##
## 【为什么背景是模糊桌面】A2 原文是「你关掉广告」。广告关掉之后必须有一个
## 「现实」的落点；模糊的书桌压暗之后，既接得住 A1 的报纸，也接得住 A3 结束后
## 真正进入的桌面 —— 玩家不会经历一次「黑屏 → 突然出现桌子」的跳变。
##
## 【它盖在谁上面】`scenes/main_scene.tscn` 的 `main.gd` 在检测到
## `Game.state.intro_done == false` 时把本场景加到桌子上面。开场本身不改主场景、
## 不改桌子脚本 —— 桌子不需要知道「还有一段开场」这件事。
##
## 【文案从哪来】`data/intro/intro.md` → `tools/gen_intro.gd` → `data/intro/intro.tres`。
## 本文件只负责摆位置和推进，一个字都不写死。

signal finished

const INTRO_PATH := "res://data/intro/intro.tres"
const DIALOGUE_SCENE := preload("res://scenes/ui/dialogue_box.tscn")
const FONT_CN := preload("res://assets/fonts/main_font.tres")

## 报纸纸面在 1920×1080 画布上的位置（模板实测：180,47 → 1733,1019）
const PAPER_RECT := Rect2(180, 47, 1553, 972)
## 左侧深灰大图块：放广告主视觉
const LEFT_BLOCK := Rect2(249, 305, 575, 672)
## 右侧浅色区：放正文。模板自带的分栏线在它下面，仍然露在边缘
const RIGHT_PANEL := Rect2(874, 305, 740, 670)

## 名字卡：纸张浮在压暗的桌面上
const CARD_RECT := Rect2(550, 285, 820, 510)
const NAME_MAX_LEN := 6

## 「剧照」：录像机那套五官合成出来的相框卡片，压在报纸角上 / 摆在登记表两侧。
## 位置按 1920×1080 绝对坐标摆 —— 报纸右下的 × 按钮（1622,915）必须留空，
## 否则玩家会觉得按钮被照片挡住了（虽然照片不吃点击）。
const PHOTO_NEWS := [
	{"path": "res://assets/ui/intro/card_smug.png",
			"pos": Vector2(24, 100), "height": 262.0, "angle": -8.0, "delay": 0.55},
	{"path": "res://assets/ui/intro/card_sorrow.png",
			"pos": Vector2(1622, 512), "height": 300.0, "angle": 7.0, "delay": 0.7},
]
const PHOTO_NAME := [
	{"path": "res://assets/ui/intro/card_surprise.png",
			"pos": Vector2(248, 320), "height": 306.0, "angle": -8.0, "delay": 0.0},
	{"path": "res://assets/ui/intro/card_smug.png",
			"pos": Vector2(1412, 348), "height": 300.0, "angle": 6.0, "delay": 0.12},
]

@onready var _paper_layer: Control = $PaperLayer
@onready var _paper_text: Control = $PaperLayer/PaperText
@onready var _fade: ColorRect = $Fade
@onready var _dialogue_host: Control = $DialogueHost
@onready var _name_layer: Control = $NameLayer

var data: IntroData
var _dialogue
var _close_button: Button
var _name_edit: LineEdit
var _confirm_button: Button
var _name_hint: Label

var _closing := false
var _finished := false


func _ready() -> void:
	data = load(INTRO_PATH) as IntroData
	if data == null:
		push_error("[Intro] 读不到 %s —— 先跑 tools/gen_intro.gd" % INTRO_PATH)
		_abort()
		return

	var errs: Array = data.validate()
	for e: String in errs:
		push_warning("[Intro] " + e)

	_build_paper()
	_build_dialogue()
	_build_name_layer()

	# 从黑场淡入。开场第一帧不该是「啪」一下出现一张报纸
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 0.55)
	tw.finished.connect(_on_fade_in_done)


# ============================================================
# A1 · 报纸
# ============================================================
func _build_paper() -> void:
	# 报头 / 版次
	_label(_paper_text, data.masthead, 46, UiPalette.INK,
			Rect2(240, 70, 700, 64), HORIZONTAL_ALIGNMENT_LEFT, false,
			UiPalette.TITLE_FONT)
	# 版次放在报头右侧的空白纸面上 —— 模板右上角有灰条，小字压上去读不清
	_label(_paper_text, data.edition, 22, UiPalette.PAGE_INK_SOFT,
			Rect2(560, 76, 620, 44))

	# 右上角的「广告」小标签：告诉玩家这不是新闻，是整版广告
	var tag := PanelContainer.new()
	tag.position = Vector2(1560, 60)
	tag.size = Vector2(112, 42)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag_style := UiPalette.panel(UiPalette.DANGER, 4)
	tag_style.content_margin_left = 12
	tag_style.content_margin_right = 12
	tag_style.content_margin_top = 4
	tag_style.content_margin_bottom = 4
	tag.add_theme_stylebox_override("panel", tag_style)
	_paper_text.add_child(tag)
	_vlabel(tag, "广告", 20, UiPalette.PAPER, false, UiPalette.TITLE_FONT)

	# 两条深色栏目条（模板里本来就是深灰，只往上压白字）
	_label(_paper_text, "整版广告", 24, UiPalette.PAPER,
			Rect2(270, 250, 520, 40), HORIZONTAL_ALIGNMENT_LEFT, false,
			UiPalette.TITLE_FONT)
	_label(_paper_text, "%s · 首发预热" % data.product, 24, UiPalette.PAPER,
			Rect2(895, 250, 700, 40), HORIZONTAL_ALIGNMENT_LEFT, false,
			UiPalette.TITLE_FONT)

	# 左栏主视觉
	_label(_paper_text, data.title, 70, UiPalette.PAPER,
			Rect2(285, 350, 510, 170), HORIZONTAL_ALIGNMENT_LEFT, true,
			UiPalette.TITLE_FONT)
	var rule := ColorRect.new()
	rule.position = Vector2(287, 540)
	rule.size = Vector2(120, 8)
	rule.color = UiPalette.ACCENT
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper_text.add_child(rule)

	_label(_paper_text, data.product, 52, UiPalette.ACCENT,
			Rect2(285, 570, 520, 80), HORIZONTAL_ALIGNMENT_LEFT, true,
			UiPalette.TITLE_FONT)
	var subtitle := _label(_paper_text, data.subtitle, 26, UiPalette.PAPER,
			Rect2(285, 665, 500, 130), HORIZONTAL_ALIGNMENT_LEFT, true)
	subtitle.add_theme_constant_override("line_spacing", 8)

	# 倒计时：约定格式「距离发售：21天」——冒号前是标签、后是数字
	var parts := data.countdown.split("：")
	if parts.size() >= 2:
		_label(_paper_text, parts[0], 22, UiPalette.PAPER,
				Rect2(287, 838, 500, 36))
		_label(_paper_text, parts[1], 64, UiPalette.DANGER,
				Rect2(285, 872, 500, 96), HORIZONTAL_ALIGNMENT_LEFT, false,
				UiPalette.TITLE_FONT)
	else:
		_label(_paper_text, data.countdown, 44, UiPalette.DANGER,
				Rect2(287, 860, 500, 90))

	# 右栏正文：模板的分栏线在下面，正文块压上去之后仍然露着纸边和栏线
	var panel := PanelContainer.new()
	panel.position = RIGHT_PANEL.position
	panel.size = RIGHT_PANEL.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel",
			UiPalette.panel(Color(0.957, 0.945, 0.91, 0.96), 4, 2, UiPalette.INK))
	_paper_text.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_bottom", 22)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	_vlabel(box, "为什么是 %s" % data.product, 20, UiPalette.DANGER, false)

	var body := _vlabel(box, data.body, 22, UiPalette.INK, true)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("line_spacing", 10)

	_vlabel(box, data.footer, 17, UiPalette.PAGE_INK_FAINT, false)

	# 关掉广告：**等整页淡入之后才出现**（见 `_on_fade_in_done`）
	_close_button = Button.new()
	_close_button.text = "×"
	_close_button.visible = false
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_close_button.position = Vector2(1622, 915)
	_close_button.size = Vector2(82, 82)
	_close_button.pivot_offset = _close_button.size * 0.5
	_close_button.add_theme_font_override("font", FONT_CN)
	_close_button.add_theme_font_size_override("font_size", 42)
	_close_button.add_theme_color_override("font_color", UiPalette.PAPER)
	_close_button.add_theme_color_override("font_hover_color", UiPalette.PAPER)
	_close_button.add_theme_color_override("font_pressed_color", UiPalette.PAPER)
	_close_button.add_theme_stylebox_override("normal",
			UiPalette.button(UiPalette.DANGER, UiPalette.INK, 2, 41))
	_close_button.add_theme_stylebox_override("hover",
			UiPalette.button(Color("f26468"), UiPalette.INK, 2, 41))
	_close_button.add_theme_stylebox_override("pressed",
			UiPalette.button(Color("c23a3f"), UiPalette.INK, 2, 41))
	_close_button.pressed.connect(_on_close_ad)
	_paper_layer.add_child(_close_button)

	# 照片最后加，压在报纸上；层序在 Fade 之下，淡入时会跟着一起亮起来
	for spec: Dictionary in PHOTO_NEWS:
		_add_photo(_paper_layer, spec)


func _on_fade_in_done() -> void:
	if _finished:
		return
	_close_button.visible = true
	_close_button.scale = Vector2(0.7, 0.7)
	var tw := create_tween()
	tw.tween_property(_close_button, "scale", Vector2.ONE, 0.18) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ============================================================
# A2 / A3 · 独白
# ============================================================
func _build_dialogue() -> void:
	_dialogue = DIALOGUE_SCENE.instantiate()
	_dialogue.visible = false
	_dialogue_host.add_child(_dialogue)
	_dialogue.finished.connect(_on_dialogue_finished)


func _on_close_ad() -> void:
	if _closing or _finished:
		return
	_closing = true
	_close_button.disabled = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.35)
	await tw.finished
	if _finished:
		return
	_paper_layer.visible = false
	_dialogue_host.visible = true
	_dialogue.play_lines(data.narration())
	var tw2 := create_tween()
	tw2.tween_property(_fade, "color:a", 0.0, 0.35)


func _on_dialogue_finished() -> void:
	_dialogue_host.visible = false
	_name_layer.visible = true
	_name_edit.grab_focus()


# ============================================================
# 取名
# ============================================================
func _build_name_layer() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.58)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_name_layer.add_child(dim)

	# 照片挂在压暗层之上、登记表之下：不遮输入框，也不被暗罩压灰
	for spec: Dictionary in PHOTO_NAME:
		_add_photo(_name_layer, spec)

	var card := PanelContainer.new()
	card.position = CARD_RECT.position
	card.size = CARD_RECT.size
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var card_style := UiPalette.panel(UiPalette.PAPER, 6, 3, UiPalette.INK)
	card_style.shadow_color = Color(0, 0, 0, 0.6)
	card_style.shadow_size = 18
	card_style.shadow_offset = Vector2(0, 8)
	card.add_theme_stylebox_override("panel", card_style)
	_name_layer.add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 52)
	margin.add_theme_constant_override("margin_top", 38)
	margin.add_theme_constant_override("margin_right", 52)
	margin.add_theme_constant_override("margin_bottom", 34)
	card.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)

	_vlabel(box, "演员登记表", 42, UiPalette.INK, false, UiPalette.TITLE_FONT)
	_vlabel(box, "签下名字，明天开机。", 20, UiPalette.PAGE_INK_SOFT, false)

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 3)
	rule.color = Color(UiPalette.INK, 0.75)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)

	_vlabel(box, "%d 个字以内，首尾空格会去掉。" % NAME_MAX_LEN,
			17, UiPalette.PAGE_INK_FAINT, false)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "你的名字"
	_name_edit.max_length = NAME_MAX_LEN
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.custom_minimum_size = Vector2(0, 64)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.add_theme_font_override("font", FONT_CN)
	_name_edit.add_theme_font_size_override("font_size", 28)
	_name_edit.add_theme_color_override("font_color", UiPalette.INK)
	_name_edit.add_theme_color_override("font_placeholder_color", UiPalette.TEXT_DISABLED)
	_name_edit.add_theme_color_override("caret_color", UiPalette.INK)
	_name_edit.add_theme_stylebox_override("normal",
			UiPalette.button(UiPalette.PAPER_SOFT, UiPalette.PAGE_LINE, 2, 4, 0, 16))
	_name_edit.add_theme_stylebox_override("focus",
			UiPalette.button(UiPalette.PAPER, UiPalette.INK, 2, 4, 0, 16))
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.text_submitted.connect(_on_name_submitted)
	box.add_child(_name_edit)

	_name_hint = _vlabel(box, "", 17, UiPalette.PAGE_INK_FAINT, false)

	_confirm_button = Button.new()
	_confirm_button.text = "开工"
	_confirm_button.disabled = true
	_confirm_button.focus_mode = Control.FOCUS_NONE
	_confirm_button.custom_minimum_size = Vector2(0, 64)
	_confirm_button.add_theme_font_override("font", FONT_CN)
	_confirm_button.add_theme_font_size_override("font_size", 28)
	_confirm_button.add_theme_color_override("font_color", UiPalette.INK)
	_confirm_button.add_theme_color_override("font_hover_color", UiPalette.INK)
	_confirm_button.add_theme_color_override("font_pressed_color", UiPalette.INK)
	_confirm_button.add_theme_color_override("font_disabled_color", UiPalette.TEXT_DISABLED)
	_confirm_button.add_theme_stylebox_override("normal",
			UiPalette.button(UiPalette.ACCENT, UiPalette.INK, 2, 6))
	_confirm_button.add_theme_stylebox_override("hover",
			UiPalette.button(Color("ffe071"), UiPalette.INK, 2, 6))
	_confirm_button.add_theme_stylebox_override("pressed",
			UiPalette.button(Color("e6bd35"), UiPalette.INK, 2, 6))
	_confirm_button.add_theme_stylebox_override("disabled",
			UiPalette.button(UiPalette.PAPER_DISABLED, UiPalette.PAPER_LINE, 2, 6))
	_confirm_button.pressed.connect(_on_confirm_pressed)
	box.add_child(_confirm_button)

	# 让 hint 在空名时也能换色，而不是被一次性的 _vlabel 颜色锁死
	_name_hint.add_theme_color_override("font_color", UiPalette.PAGE_INK_FAINT)


func _on_name_changed(new_text: String) -> void:
	var ok := not new_text.strip_edges().is_empty()
	_confirm_button.disabled = not ok
	if ok:
		_name_hint.text = ""
		_name_hint.add_theme_color_override("font_color", UiPalette.PAGE_INK_FAINT)


func _on_name_submitted(_text: String) -> void:
	_on_confirm_pressed()


func _on_confirm_pressed() -> void:
	if _finished:
		return
	var who := _name_edit.text.strip_edges()
	if who.is_empty():
		_name_hint.text = "总得有个名字"
		_name_hint.add_theme_color_override("font_color", UiPalette.DANGER)
		return

	Game.set_player_name(who)
	if Game.state != null:
		Game.state.intro_done = true
	_finish()


# ============================================================
# 收尾
# ============================================================
func _finish() -> void:
	if _finished:
		return
	_finished = true
	# 【先存再淡出】存档是产品行为：哪怕玩家在淡出途中把游戏切到后台，
	# 下次进来也不该再看一遍开场。
	EventBus.save_requested.emit()
	finished.emit()
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.4)
	await tw.finished
	queue_free()


## 数据缺失时的退路：把开场让开，但不写 `intro_done` ——
## 这样下次启动还会再试一次，问题不会被「跳过一次」掩盖。
func _abort() -> void:
	if _finished:
		return
	_finished = true
	finished.emit()
	queue_free()


# ============================================================
# 剧照
# ============================================================
## 按高度定尺寸（卡片比例各不相同，按宽定会把欧式框压扁）。
## 锚点给中心：rotation 绕中心转，不然会绕着左上角甩出去。
func _add_photo(parent: Node, spec: Dictionary) -> void:
	var tex := load(spec["path"]) as Texture2D
	if tex == null:
		push_warning("[Intro] 缺剧照 %s —— 先跑合成脚本" % spec["path"])
		return

	var h: float = spec["height"]
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size = Vector2(h * tex.get_width() / tex.get_height(), h)
	r.position = spec["pos"]
	r.pivot_offset = r.size * 0.5
	r.rotation = deg_to_rad(spec["angle"])
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.modulate.a = 0.0
	parent.add_child(r)

	var fade := create_tween()
	fade.tween_property(r, "modulate:a", 1.0, 0.45).set_delay(spec["delay"])

	# 照片落桌后还会晃一下：幅度压到 4px、周期 2.2s，只当呼吸，不抢正文
	var bob := create_tween().set_loops()
	bob.tween_property(r, "position:y", r.position.y - 4.0, 2.2) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(r, "position:y", r.position.y, 2.2) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# ============================================================
# 排版小工具
# ============================================================
## 绝对定位的 Label（报纸纸面上的元素都按模板坐标摆）
func _label(parent: Node, text: String, font_size: int, color: Color,
		rect: Rect2, align := HORIZONTAL_ALIGNMENT_LEFT, wrap := false,
		font: Font = FONT_CN) -> Label:
	var l := Label.new()
	l.text = text
	l.position = rect.position
	l.size = rect.size
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	UiPalette.text(l, font_size, color)
	l.add_theme_font_override("font", font)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


## 容器里的 Label（宽度由父容器给，必须开自动换行）
func _vlabel(parent: Node, text: String, font_size: int, color: Color,
		wrap := true, font: Font = FONT_CN) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiPalette.text(l, font_size, color)
	l.add_theme_font_override("font", font)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l
