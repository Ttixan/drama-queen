extends Control
## 周结算翻牌 —— 「首次演成龙套 / 配角 / 主角」的奖励仪式
##
## 【为什么是翻牌，不是直接发】三套复杂表情是这个游戏里最"贪"的表演素材
## （得意 / 皮笑肉不笑 / 想起已故的爱人）。直接塞进背包，玩家只会觉得部件多了；
## 让他从三张一模一样的牌背里挑一张、再看着它翻过来，这件东西才变成"我赢来的"。
##
## 【为什么点哪张都一样】牌面在**推进到下一天时**就抽好了（`GameState.roll_reward_set`），
## 存进 `GameState.pending_flips`。点击只决定"翻哪一张"，不决定结果 ——
## 这样读档重放不会换一张脸，也不必在点击那一刻再摇一次随机数。
## 三张牌背因此可以长得完全一样，玩家看到的是自己的选择，拿到的是这一周的运气。
##
## 【它怎么被用】由日历屏当浮层实例化：玩家按下「下一天」之后立刻出现；
## 若那天正好跨周末，则先看报纸、关掉报纸再翻牌。
## 点「收下」→ `finished` → 调用方清掉自己，若还有待翻的牌就再开一张。
##
## 【和录像机的关系】收下的那套进 `GameState.owned_sets`，
## 录像机按 `Game.is_part_unlocked()` 把那三件从灰变亮。这里不碰部件本身。

signal finished

## 牌面尺寸：原图 597×760（见 tools/import_reward_frames.py），
## 三张并排时每张压到 300 宽 —— 1080p 下三张 + 两道缝正好占满中间那头。
const CARD_SIZE := Vector2(300, 382)
## 翻面时长的一半：0.16 秒缩到 0，换图，再 0.16 秒撑回来
const FLIP_SEC := 0.16

const C_BG := UiPalette.BG
const C_PANEL := UiPalette.PANEL
const C_LINE := UiPalette.LINE
const C_TEXT := UiPalette.TEXT
const C_TEXT_DIM := UiPalette.TEXT_DIM
const C_ACCENT := UiPalette.ACCENT
const C_INK := UiPalette.INK

@onready var _title: Label = get_node("Center/Box/Title")
@onready var _subtitle: Label = get_node("Center/Box/Subtitle")
@onready var _row: HBoxContainer = get_node("Center/Box/CardsRow")
@onready var _result: PanelContainer = get_node("Center/Box/ResultPanel")
@onready var _result_caption: Label = get_node(
		"Center/Box/ResultPanel/ResultMargin/ResultBox/ResultCaption")
@onready var _result_name: Label = get_node(
		"Center/Box/ResultPanel/ResultMargin/ResultBox/ResultName")
@onready var _claim_button: Button = get_node(
		"Center/Box/ResultPanel/ResultMargin/ResultBox/ClaimButton")

## 这一张牌：`{tier, set}`（见 `GameState.peek_flip`）。空字典 = 没有待翻的牌
var _entry: Dictionary = {}
## 三张牌按钮 / 牌面上的贴图 / 悬停描边
var _cards: Array[Button] = []
var _faces: Array[TextureRect] = []
var _glows: Array[Panel] = []
## 翻过了没有（翻过之后三张牌都不再响应）
var _flipped := false
## 已经收下（防连点导致消费两张牌）
var _claimed := false
## 牌背只加载一次；三个按钮共用同一张图
var _back_tex: Texture2D
## 正面按需加载
var _front_tex: Texture2D


func _ready() -> void:
	_entry = Game.peek_pending_flip()
	if _entry.is_empty():
		# 没有牌还开这一屏，说明调用方判错了。安静收工，别留一块黑屏挡路。
		call_deferred("_abort")
		return

	_back_tex = load(ExpressionSets.BACK_FRAME)
	if _back_tex == null:
		push_warning("[翻牌] 缺牌背 %s，是不是忘了跑 tools/import_reward_frames.py？"
				% ExpressionSets.BACK_FRAME)

	_apply_styles()
	_build_cards()
	_fill_headline()
	_claim_button.pressed.connect(_on_claim_pressed)
	# 【结果框一开始就占着位子】翻完才 visible 的话，牌会突然往上跳一格；
	# 让它一直参与布局、只是透明，翻面后只改透明度就稳了。
	_result.modulate.a = 0.0
	_claim_button.disabled = true


func _abort() -> void:
	finished.emit()


# ============================================================
# 牌
# ============================================================
func _build_cards() -> void:
	for i in ExpressionSets.SETS.size():
		var card := _make_card(i)
		_row.add_child(card)
		_cards.append(card)


func _make_card(index: int) -> Button:
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
	face.texture = _back_tex
	face.set_anchors_preset(Control.PRESET_FULL_RECT)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(face)
	_faces.append(face)

	# 悬停描边：盖在牌面上的一圈黄框（鼠标事件穿透给按钮）
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


func _set_glow(index: int, on: bool) -> void:
	if _flipped or index < 0 or index >= _glows.size():
		return
	_glows[index].visible = on


func _on_card_pressed(index: int) -> void:
	if _flipped or index < 0 or index >= _cards.size():
		return
	# 【先收描边，再置 _flipped】`_set_glow()` 见到 `_flipped` 就直接返回，
	# 反过来写会让"鼠标正停在牌上时点击"留下一个永远不灭的黄框
	for i in _cards.size():
		_cards[i].disabled = true
		_set_glow(i, false)
	_flipped = true

	_front_tex = load(ExpressionSets.frame_of(String(_entry.get("set", ""))))
	var card := _cards[index]
	# 直接从中心翻：不设 pivot 会从左上角缩，看起来像卡片被吸走
	card.pivot_offset = card.size * 0.5

	var tw := create_tween()
	tw.tween_property(card, "scale:x", 0.03, FLIP_SEC).set_trans(Tween.TRANS_SINE)
	# 缩到最窄的那一瞬间换图 —— 正面从一开始就存在，只是还没转过来
	tw.tween_callback(func() -> void:
		if _front_tex != null:
			_faces[index].texture = _front_tex)
	tw.tween_property(card, "scale:x", 1.0, FLIP_SEC).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_show_result)


func _show_result() -> void:
	var set_id := String(_entry.get("set", ""))
	_result_name.text = ExpressionSets.name_of(set_id)
	_subtitle.text = "收下之后，录像机里就能用这三件了"
	_claim_button.disabled = false
	var tw := create_tween()
	tw.tween_property(_result, "modulate:a", 1.0, 0.18)


func _on_claim_pressed() -> void:
	if not _flipped or _claimed:
		return
	_claimed = true
	_claim_button.disabled = true
	Game.claim_pending_flip()
	finished.emit()


# ============================================================
# 文案 / 样式
# ============================================================
## 顶部那两行：这一张牌是哪个档位换来的
func _fill_headline() -> void:
	var tier := int(_entry.get("tier", RoleRequirement.Tier.EXTRA))
	_title.text = "首次当上%s" % ExpressionSets.tier_name(tier)
	_subtitle.text = "翻一张牌，收下一套复杂表情"


func _apply_styles() -> void:
	get_node("Dim").color = Color(C_BG, 0.86)
	UiPalette.text(_title, 44, C_TEXT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiPalette.text(_subtitle, 19, C_TEXT_DIM)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_result.add_theme_stylebox_override("panel",
			UiPalette.panel(C_PANEL, 18, 3, C_ACCENT))
	UiPalette.text(_result_caption, 18, C_TEXT_DIM)
	_result_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiPalette.text(_result_name, 34, C_ACCENT)
	_result_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_claim_button.focus_mode = Control.FOCUS_NONE
	_claim_button.custom_minimum_size = Vector2(200, 54)
	_claim_button.add_theme_font_size_override("font_size", 22)
	_claim_button.add_theme_color_override("font_color", C_INK)
	_claim_button.add_theme_color_override("font_hover_color", C_INK)
	_claim_button.add_theme_color_override("font_pressed_color", C_INK)
	_claim_button.add_theme_color_override("font_disabled_color", UiPalette.TEXT_DISABLED)
	_claim_button.add_theme_stylebox_override("normal",
			UiPalette.button(C_ACCENT, C_ACCENT, 2, 14))
	_claim_button.add_theme_stylebox_override("hover",
			UiPalette.button(C_ACCENT.lightened(0.12), C_ACCENT, 3, 14))
	_claim_button.add_theme_stylebox_override("pressed",
			UiPalette.button(C_ACCENT.darkened(0.12), C_ACCENT, 3, 14))
	_claim_button.add_theme_stylebox_override("disabled",
			UiPalette.button(UiPalette.PANEL_SOFT, C_LINE, 2, 14))


## 悬停的那圈黄描边。**圆角给大**：牌面是椭圆的相框，
## 直角框会把四个角挑出来，看着像贴了一张错误提示。
func _glow_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_width_left = 4
	sb.border_width_top = 4
	sb.border_width_right = 4
	sb.border_width_bottom = 4
	sb.border_color = C_ACCENT
	sb.set_corner_radius_all(40)
	# 【不加 shadow】StyleBoxFlat 的阴影是画在**整个框下面**的：面板底色透明时，
	# 那层黄会从中间透出来，把整张牌染成米黄。悬停只要一圈线就够。
	sb.draw_center = false
	return sb
