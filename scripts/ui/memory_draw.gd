class_name MemoryDraw
extends Control
## 「记忆抽取」—— 新手礼包的三张拍立得，翻一张拿一套
##
## 只在开场引导里出现一次（策划口径：基础 8 个表情之外 6 套复杂表情，
## 其中爆缸笑脸 / 恶俗青蛙 / 严肃给力 这三套是新手礼包，翻中哪套拿哪套；
## 另外三套走「首次成功投递对应档位」的周结算翻牌）。
##
## 【和 `expression_reward.gd` 的区别】周结算那套的三张牌**点哪张都一样**
## （结果在下一天就抽好了，存 `pending_flips`）；这里三张牌**各是一家**，
## 翻中哪张就是哪套，所以：
##   · 牌面不预先排好，点开哪张才读哪张的正面；
##   · 拿到的结果由调用方写进状态（本组件只发 `picked`，不碰存档）——
##     这样它能被独立测试，也不依赖 autoload。
##
## 【动效照旧】从中心横向缩到 0、换图、再撑回来（0.16s × 2）：
## 周结算那边已经调好的手感，不另起一套。

signal picked(set_id: String)   ## 翻开了哪一套（调用方据此解锁）
signal finished                 ## 玩家点了「收下」

const CARD_SIZE := Vector2(300, 382)
const FLIP_SEC := 0.16

const C_BG := UiPalette.BG
const C_PANEL := UiPalette.PANEL
const C_LINE := UiPalette.LINE
const C_TEXT := UiPalette.TEXT
const C_TEXT_DIM := UiPalette.TEXT_DIM
const C_ACCENT := UiPalette.ACCENT
const C_INK := UiPalette.INK

var _row: HBoxContainer
var _title: Label
var _subtitle: Label
var _result: VBoxContainer
var _result_name: Label
var _claim: Button

var _cards: Array[Button] = []
var _faces: Array[TextureRect] = []
var _glows: Array[Panel] = []
## 三张牌各自是哪一套（顺序 = `ExpressionSets.STARTER_SETS`）
var _ids: Array[String] = []
var _flipped := false
var _picked := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	var back: Texture2D = load(ExpressionSets.STARTER_BACK_FRAME)
	if back == null:
		push_warning("[记忆抽取] 缺牌背 %s —— 跑过 tools/import_reward_frames.py 了吗"
				% ExpressionSets.STARTER_BACK_FRAME)
	for i in ExpressionSets.STARTER_SETS.size():
		var spec: Dictionary = ExpressionSets.STARTER_SETS[i]
		_ids.append(String(spec["id"]))
		var card := _make_card(i, back)
		_row.add_child(card)
		_cards.append(card)
	_result.modulate.a = 0.0
	_claim.disabled = true


## 翻到了哪一套（没翻之前是空串）
func picked_id() -> String:
	return _picked


## 三张牌的三套 id（测试用）
func card_ids() -> Array[String]:
	return _ids


# ============================================================
# 界面
# ============================================================
func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(C_BG, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(box)

	_title = Label.new()
	_title.text = "记忆抽取"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiPalette.title(_title, 44, C_TEXT)
	box.add_child(_title)

	_subtitle = Label.new()
	_subtitle.text = "从大脑的内存碎片里，勉强抽出几个能用的表情"
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiPalette.text(_subtitle, 19, C_TEXT_DIM)
	box.add_child(_subtitle)

	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 24)
	box.add_child(_row)

	_result = VBoxContainer.new()
	_result.add_theme_constant_override("separation", 12)
	box.add_child(_result)

	_result_name = Label.new()
	_result_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiPalette.title(_result_name, 34, C_ACCENT)
	_result.add_child(_result_name)

	var result_caption := Label.new()
	result_caption.text = "收下之后，录像机里就能拼这一套了"
	result_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiPalette.text(result_caption, 18, C_TEXT_DIM)
	_result.add_child(result_caption)

	var claim_center := CenterContainer.new()
	_result.add_child(claim_center)
	_claim = Button.new()
	_claim.text = "收下"
	_claim.focus_mode = Control.FOCUS_NONE
	_claim.custom_minimum_size = Vector2(200, 54)
	_claim.add_theme_font_size_override("font_size", 22)
	_claim.add_theme_color_override("font_color", C_INK)
	_claim.add_theme_color_override("font_hover_color", C_INK)
	_claim.add_theme_color_override("font_pressed_color", C_INK)
	_claim.add_theme_color_override("font_disabled_color", UiPalette.TEXT_DISABLED)
	_claim.add_theme_stylebox_override("normal",
			UiPalette.button(C_ACCENT, C_ACCENT, 2, 14))
	_claim.add_theme_stylebox_override("hover",
			UiPalette.button(C_ACCENT.lightened(0.12), C_ACCENT, 3, 14))
	_claim.add_theme_stylebox_override("pressed",
			UiPalette.button(C_ACCENT.darkened(0.12), C_ACCENT, 3, 14))
	_claim.add_theme_stylebox_override("disabled",
			UiPalette.button(UiPalette.PANEL_SOFT, C_LINE, 2, 14))
	_claim.pressed.connect(_on_claim)
	claim_center.add_child(_claim)


func _make_card(index: int, back: Texture2D) -> Button:
	var card := Button.new()
	card.name = "Card%d" % (index + 1)
	card.flat = true
	card.focus_mode = Control.FOCUS_NONE
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.custom_minimum_size = CARD_SIZE
	# 默认主题会给 Button 铺一块灰底 —— 牌背自己有透明边，铺上就成了一张方块
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		card.add_theme_stylebox_override(state, StyleBoxEmpty.new())

	var face := TextureRect.new()
	face.name = "Face"
	face.texture = back
	face.set_anchors_preset(Control.PRESET_FULL_RECT)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(face)
	_faces.append(face)

	var glow := Panel.new()
	glow.name = "Glow"
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.offset_left = -12
	glow.offset_top = -12
	glow.offset_right = 12
	glow.offset_bottom = 12
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.visible = false
	glow.add_theme_stylebox_override("panel", _glow_style())
	card.add_child(glow)
	_glows.append(glow)

	card.pressed.connect(_on_card_pressed.bind(index))
	card.mouse_entered.connect(_set_glow.bind(index, true))
	card.mouse_exited.connect(_set_glow.bind(index, false))
	return card


func _glow_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_width_left = 4
	sb.border_width_top = 4
	sb.border_width_right = 4
	sb.border_width_bottom = 4
	sb.border_color = C_ACCENT
	sb.set_corner_radius_all(40)
	sb.draw_center = false
	return sb


func _set_glow(index: int, on: bool) -> void:
	if _flipped or index < 0 or index >= _glows.size():
		return
	_glows[index].visible = on


# ============================================================
# 翻牌
# ============================================================
func _on_card_pressed(index: int) -> void:
	if _flipped or index < 0 or index >= _cards.size():
		return
	# 先收描边再置 `_flipped`：`_set_glow()` 见到它就直接返回，
	# 反过来写会让"鼠标正停在牌上时点击"留下一个永远不灭的黄框
	for i in _cards.size():
		_cards[i].disabled = true
		_set_glow(i, false)
	_flipped = true
	# 新手礼包翻牌也走「开箱」那一声 —— 两处翻的是同一种仪式
	Sfx.play(&"item_unbox")

	var id := _ids[index]
	var front: Texture2D = load(ExpressionSets.frame_of(id))
	var card := _cards[index]
	# 直接从中心翻：不设 pivot 会从左上角缩，看起来像卡片被吸走
	card.pivot_offset = card.size * 0.5

	var tw := create_tween()
	tw.tween_property(card, "scale:x", 0.03, FLIP_SEC).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		if front != null:
			_faces[index].texture = front)
	tw.tween_property(card, "scale:x", 1.0, FLIP_SEC).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_show_result.bind(id))


func _show_result(id: String) -> void:
	_picked = id
	_result_name.text = "抽到了「%s」" % ExpressionSets.name_of(id)
	_claim.disabled = false
	create_tween().tween_property(_result, "modulate:a", 1.0, 0.18)
	picked.emit(id)


func _on_claim() -> void:
	_claim.disabled = true
	finished.emit()
