extends Control
## 抄录手册（笔记本）—— 桌上那本摊开的笔记，二级页面
##
## 【这一版的样子】模糊的桌子当底，笔记本本身是美术给的 1920×1080 插画
## （`assets/ui/notebook/page.png`）。四张贴纸分别贴在左右两页上：
##   左页上 / 左页下 · 右页上 / 右页下 —— 中间的活页圈（x≈930..995）空着
## 点一张贴纸 → 三级页面（单页笔记）显示这张的标题与正文，右上角 × 回到本子。
##
## 【坐标为什么要写死】和台历同一条约定：纸面在插画里是固定位置，整屏按
## 1920×1080 等比缩放（canvas_items + keep），所以这里用设计坐标。
## 贴纸位置、纸面范围都是量出来的（见 `STICKER_RECTS` / 文件头的纸面说明）。
##
## 【贴纸不是四张图】素材只有一张 `stickers.png`（四张横排），
## 这里用 `AtlasTexture` 切出区域 —— **不落四份 PNG**，美术改图时只换一张。
##
## 【字体】与全局一致：`assets/fonts/main_font.tres`（獅尾半月字體 tc-Light
## + 系统字体兜底）。`×` / `✕` 这类符号本体缺字时由兜底层补上，不会再出豆腐块。

## 回到桌子（上层把本场景当子页面打开时）
signal cancelled

const FONT_CN := preload("res://assets/fonts/main_font.tres")

const STICKER_SHEET := preload("res://assets/ui/notebook/stickers.png")
const NOTE_TEXTURE := preload("res://assets/ui/notebook/note.png")

# ============================================================
# 版面（设计坐标 1920×1080）
# ============================================================
## 返回按钮：屏幕左上角，**纸面之外**（纸从 x=153 开始，按钮到 144 收住）
const BACK_RECT := Rect2(24, 20, 120, 44)

## 四张贴纸在素材里的原始区域（含顶上那颗图钉，332×367）
const STICKER_SRC: Array[Rect2] = [
	Rect2(199, 50, 332, 367),
	Rect2(585, 52, 332, 367),
	Rect2(1041, 54, 332, 367),
	Rect2(1418, 57, 332, 367),
]

## 贴在纸上的位置：左页（153..930）两张、右页（995..1779）两张。
## 【为什么是竖着两张】单页宽 ~700，横排两张贴纸会顶到活页圈；
## 竖排 380×420 正好留出上下呼吸的边。
const STICKER_RECTS: Array[Rect2] = [
	Rect2(351, 150, 380, 420),
	Rect2(351, 600, 380, 420),
	Rect2(1197, 150, 380, 420),
	Rect2(1197, 600, 380, 420),
]
## 各自歪一点：手贴的东西不会四平八稳。角度小，标题仍然好读。
const STICKER_ANGLES: Array[float] = [-3.0, 2.0, -2.0, 3.0]

## 三级页面：便签图本身是整屏排好的（纸面 391,19 → 1467,1053），直接铺满
const CLOSE_RECT := Rect2(1372, 46, 62, 62)
const NOTE_TITLE_RECT := Rect2(470, 112, 920, 84)
const NOTE_BODY_RECT := Rect2(535, 250, 810, 640)

## 在纸面上读字的墨色，与台历同一套（`UiPalette.PAGE_*`）
const INK := UiPalette.PAGE_INK
const INK_SOFT := UiPalette.PAGE_INK_SOFT
const INK_FAINT := UiPalette.PAGE_INK_FAINT
const LINE := UiPalette.PAGE_LINE

@onready var _page: Control = get_node("Page")
@onready var _note_layer: Control = get_node("NoteLayer")

var _back_button: Button
var _back_enabled := false

var _note_title: Label
var _note_body: Label
var _close_button: Button
## 当前打开的是第几张（-1 = 没开）。测试与调试都要能问出这件事。
var _note_index := -1


func _ready() -> void:
	_build_back()
	_build_stickers()
	_build_note_layer()
	_note_layer.visible = false


# ============================================================
# 小工具
# ============================================================
func _label(parent: Node, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiPalette.text(l, size, color)
	l.add_theme_font_override("font", FONT_CN)
	parent.add_child(l)
	return l


## 返回桌面：只有被桌子打开时才露（独立运行时它是死路）
func _build_back() -> void:
	_back_button = Button.new()
	_back_button.text = "返回桌面"
	_back_button.focus_mode = Control.FOCUS_NONE
	_back_button.visible = false
	_back_button.pressed.connect(func() -> void: cancelled.emit())
	_back_button.position = BACK_RECT.position
	_back_button.size = BACK_RECT.size
	_back_button.add_theme_font_override("font", FONT_CN)
	_back_button.add_theme_font_size_override("font_size", 16)
	_back_button.add_theme_color_override("font_color", INK_SOFT)
	_back_button.add_theme_color_override("font_hover_color", INK)
	_back_button.add_theme_color_override("font_pressed_color", INK)
	_back_button.add_theme_stylebox_override("normal",
			UiPalette.button(Color(1, 1, 1, 0.4), LINE, 2, 12))
	_back_button.add_theme_stylebox_override("hover",
			UiPalette.button(Color(1, 1, 1, 0.85), INK, 2, 12))
	_back_button.add_theme_stylebox_override("pressed",
			UiPalette.button(Color(1, 1, 1, 0.95), Color("1f7a4d"), 2, 12))
	_page.add_child(_back_button)


func enable_back() -> void:
	_back_enabled = true
	if _back_button != null:
		_back_button.visible = true


# ============================================================
# 二级页：四张贴纸
# ============================================================
func _build_stickers() -> void:
	for i in NoteLibrary.count():
		var note := NoteLibrary.note_at(i)
		var rect: Rect2 = STICKER_RECTS[i]
		var b := Button.new()
		b.name = "Sticker_%d" % i
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.position = rect.position
		b.size = rect.size
		# 绕中心转：`pivot_offset` 不设的话会绕左上角，四张会各歪各的
		b.pivot_offset = rect.size * 0.5
		b.rotation = deg_to_rad(STICKER_ANGLES[i])
		b.tooltip_text = String(note["title"])
		_page.add_child(b)

		# 按钮皮全空：视觉完全交给贴纸图，只用 hover 改亮度给一点反馈
		var empty := StyleBoxEmpty.new()
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(state, empty)

		var tex := TextureRect.new()
		tex.texture = _sticker_atlas(i)
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_SCALE
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tex)

		# 标题写在卡片上（图钉下面那块空白）：380×420 的纸片只放得下标题，
		# 正文进三级页面 —— 挤在一起就没人读了
		var title := _label(b, String(note["title"]), 26, INK)
		title.position = Vector2(28, 96)
		title.size = Vector2(rect.size.x - 56, 140)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

		# 【贴纸上为什么要写"点开看全文"】手机上既没有 hover 也没有光标，
		# 一张只有标题的纸片看起来就是"画"，不像是能点的
		var hint := _label(b, "点开看全文", 15, INK_FAINT)
		hint.position = Vector2(28, 318)
		hint.size = Vector2(rect.size.x - 56, 40)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		b.pressed.connect(_open_note.bind(i))
		b.mouse_entered.connect(func() -> void: tex.modulate = Color(1.06, 1.06, 1.06))
		b.mouse_exited.connect(func() -> void: tex.modulate = Color.WHITE)


func _sticker_atlas(index: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = STICKER_SHEET
	atlas.region = STICKER_SRC[index]
	return atlas


# ============================================================
# 三级页：单独一张笔记
# ============================================================
func _build_note_layer() -> void:
	# 压暗一层：便签纸很大，但底下的贴纸还在，不压暗会互相抢注意力
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_note_layer.add_child(dim)

	var paper := TextureRect.new()
	paper.texture = NOTE_TEXTURE
	paper.set_anchors_preset(Control.PRESET_FULL_RECT)
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.stretch_mode = TextureRect.STRETCH_SCALE
	# 纸本身也要挡点击：否则点在纸上会穿透到下面的贴纸，开着笔记又开另一张
	paper.mouse_filter = Control.MOUSE_FILTER_STOP
	_note_layer.add_child(paper)

	_note_title = _label(_note_layer, "", 44, INK)
	_note_title.position = NOTE_TITLE_RECT.position
	_note_title.size = NOTE_TITLE_RECT.size
	_note_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_note_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_note_body = _label(_note_layer, "", 30, INK)
	_note_body.position = NOTE_BODY_RECT.position
	_note_body.size = NOTE_BODY_RECT.size
	# 【正文从标题下面开始】手写的笔记是从上往下写的；垂直居中会让正文和标题
	# 之间空出小半张纸，看着像两块不相干的东西
	_note_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_note_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 八行要能一眼扫完：行距比正文大一点，不是"挤在纸上"
	_note_body.add_theme_constant_override("line_spacing", 22)

	# 右上角的 ×：**这是三级页唯一的出口**（手机上没有 Esc）
	_close_button = Button.new()
	_close_button.text = "×"
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_close_button.position = CLOSE_RECT.position
	_close_button.size = CLOSE_RECT.size
	_close_button.add_theme_font_override("font", FONT_CN)
	_close_button.add_theme_font_size_override("font_size", 38)
	_close_button.add_theme_color_override("font_color", INK_SOFT)
	_close_button.add_theme_color_override("font_hover_color", INK)
	_close_button.add_theme_color_override("font_pressed_color", INK)
	# 【常态也要有个圈】只有 hover 才出现圆底的话，手机玩家看到的就只是一个
	# 浮在纸上的「×」—— 不知道那是按钮，也不知道点哪儿
	_close_button.add_theme_stylebox_override("normal",
			UiPalette.button(Color(0.11, 0.2, 0.27, 0.04), Color(0.11, 0.2, 0.27, 0.22), 1, 31))
	_close_button.add_theme_stylebox_override("hover",
			UiPalette.button(Color(1, 1, 1, 0.8), INK, 2, 31))
	_close_button.add_theme_stylebox_override("pressed",
			UiPalette.button(Color(1, 1, 1, 0.95), INK, 2, 31))
	_close_button.pressed.connect(_close_note)
	_note_layer.add_child(_close_button)


## 打开第 index 张笔记。**内容全从 `NoteLibrary` 来** —— 这一层只管显示。
func _open_note(index: int) -> void:
	var note := NoteLibrary.note_at(index)
	if note.is_empty():
		return
	_note_index = index
	_note_title.text = String(note["title"])
	_note_body.text = NoteLibrary.body_text(index)
	_note_layer.visible = true


func _close_note() -> void:
	_note_layer.visible = false
	_note_index = -1


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# 开着笔记时，返回键只收笔记（安卓的返回惯例：先关弹层，再退页面）
	if _note_layer.visible:
		get_viewport().set_input_as_handled()
		_close_note()
		return
	if not _back_enabled:
		return
	get_viewport().set_input_as_handled()
	cancelled.emit()
