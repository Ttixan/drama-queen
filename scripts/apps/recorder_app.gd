extends Control
## 录像机 App —— 玩家「表演」的唯一场所
##
## 【职责边界】只做三件事：从 PartLibrary 取部件、把状态画出来、把点击转成对 Clip 的写入。
## 这个文件里**不允许**出现任何判定 / 数值逻辑 —— 一旦有，零件就没法被数值模拟器复用了。
##
## 【为什么先做成独立场景】它是 M1 风险最高的一环（拼装交互 + 3 帧状态 + 实时反馈
## 三个难点叠在一起）。先让它能单独跑、能单独看，再接进手机壳才不会把两处的问题搅在一起。
##
## 运行：godot --path <项目> res://scenes/minigame/recorder.tscn

# ============================================================
# 配色 —— 与占位图同源（tools/gen_placeholder_art.gd），开发期一眼能对上向量
# ============================================================

const EMOTION_COLORS := {
	Emotion.Kind.JOY: Color("ffd447"),
	Emotion.Kind.ANGER: Color("e5484d"),
	Emotion.Kind.SORROW: Color("4a7fe5"),
	Emotion.Kind.SHOCK: Color("a855f7"),
	Emotion.Kind.CHARM: Color("ff7ab6"),
	Emotion.Kind.AWKWARD: Color("8b8b8b"),
}

const C_BG := Color("16161a")
const C_PANEL := Color("232329")
const C_PANEL_SOFT := Color("2b2b33")
const C_LINE := Color("3a3a45")
const C_PAPER := Color("f5f1e8")
const C_INK := Color("16161a")
const C_TEXT := Color("f5f1e8")
const C_TEXT_DIM := Color("a0a0aa")
const C_ACCENT := Color("ffd447")
const C_POSITIVE := Color("4caf6e")
const C_DANGER := Color("e5484d")
const NEUTRAL_COLOR := Color("a0a0aa")

## 卡高受「4 行必须放得下」约束：嘴有 10 件 = 4 行，EditPanel 里留给网格的高度约 670。
## 4 × 154 + 3 × 6 = 634，留出余量，免得无谓地弹出滚动条。
const CARD_MIN_HEIGHT := 154
const ART_HEIGHT := 74

## 【缩略图为什么必须裁】整张 512×512 画布缩到 74px 高，五官只剩几个像素，卡片等于没图。
## 五官按规格都长在画布中心附近（人脸中心 = 画布中心），所以眼/嘴/眉统一裁中心的 288×288；
## 「其他」是挂在脸侧脸角的附属件（占位图放在右上 412,124），单独走整图。
## ⚠️ 这两个矩形是**唯一**与美术摆位耦合的地方：扉师若把部件挪出中心区，改这里即可。
const THUMB_CENTER := Rect2(112, 112, 288, 288)
const THUMB_FULL := Rect2(0, 0, 512, 512)

# ============================================================
# 节点路径（节点树见 scenes/minigame/recorder.tscn）
# ============================================================

## 【注意】这些是给 get_node() 用的相对路径，**不能带 `$`** ——
## `$Page/Foo` 只是 GDScript 的语法糖，get_node("$Page/Foo") 会去找一个名叫 `$Page` 的节点。
const P_PREVIEW := "Page/BodyWrap/Body/PreviewPanel/PreviewMargin/PreviewBox"
const P_FACE := P_PREVIEW + "/ViewFinder/ViewCenter/FaceCanvas"
const P_EDIT := "Page/BodyWrap/Body/EditPanel/EditMargin/EditBox"
const P_BOTTOM := "Page/BottomBar/BottomMargin/BottomRow"
const P_TOP := "Page/TopBar/TopMargin/TopRow"

@onready var _rec_dot: Panel = get_node(P_TOP + "/RecGroup/RecDot")
@onready var _frame_indicator: Label = get_node(P_TOP + "/InfoBox/FrameIndicator")
@onready var _face_canvas: Control = get_node(P_FACE)
@onready var _frame_badge: Label = get_node(P_FACE + "/FrameBadge")
@onready var _layer_brows: TextureRect = get_node(P_FACE + "/LayerBrows")
@onready var _layer_eyes: TextureRect = get_node(P_FACE + "/LayerEyes")
@onready var _layer_mouth: TextureRect = get_node(P_FACE + "/LayerMouth")
@onready var _layer_extra: TextureRect = get_node(P_FACE + "/LayerExtra")
@onready var _emotion_value: Label = get_node(
		P_PREVIEW + "/EmotionStrip/EmotionMargin/EmotionRow/EmotionValue")
@onready var _emotion_parts: Label = get_node(
		P_PREVIEW + "/EmotionStrip/EmotionMargin/EmotionRow/EmotionParts")
@onready var _sequence_label: Label = get_node(P_PREVIEW + "/SequenceLabel")
@onready var _canvas_frame: Panel = get_node(P_FACE + "/CanvasFrame")
@onready var _face_hint: Label = get_node(P_FACE + "/FaceHint")
@onready var _grid_scroll: ScrollContainer = get_node(P_EDIT + "/GridScroll")
@onready var _status_label: Label = get_node(P_BOTTOM + "/StatusBox/StatusLabel")
@onready var _status_hint: Label = get_node(P_BOTTOM + "/StatusBox/StatusHint")
@onready var _clear_button: Button = get_node(P_BOTTOM + "/ActionsRow/ClearButton")
@onready var _confirm_button: Button = get_node(P_BOTTOM + "/ActionsRow/ConfirmButton")

# ============================================================
# 状态
# ============================================================

var _clip: Clip
var _frame := 0                       ## 当前编辑的帧下标
var _tab: int = PartData.Slot.EYES    ## 当前页签
var _tabs: Array[Button] = []         ## 与 PartLibrary.TAB_ORDER 一一对应
var _pages: Dictionary = {}           ## slot -> GridContainer
var _slot_buttons: Array[Button] = []
var _cards: Dictionary = {}           ## slot -> { key -> Button }
var _card_group: Dictionary = {}      ## slot -> ButtonGroup（同槽位内互斥）
## 程序化改按钮状态时会触发 toggled，用这个闸门防止自己把自己绕进去
var _syncing := false


func _ready() -> void:
	_clip = Clip.new()   # 默认就是 3 帧空 Frame，不用再补

	_collect_nodes()
	_apply_styles()
	_build_cards()
	_sync_all()
	_pulse_rec_dot()


func _collect_nodes() -> void:
	_tabs = [
		get_node(P_EDIT + "/TabsRow/TabEyes"),
		get_node(P_EDIT + "/TabsRow/TabMouth"),
		get_node(P_EDIT + "/TabsRow/TabBrows"),
		get_node(P_EDIT + "/TabsRow/TabExtra"),
	]
	_pages = {
		PartData.Slot.EYES: get_node(P_EDIT + "/GridScroll/PageEyes"),
		PartData.Slot.MOUTH: get_node(P_EDIT + "/GridScroll/PageMouth"),
		PartData.Slot.BROWS: get_node(P_EDIT + "/GridScroll/PageBrows"),
		PartData.Slot.EXTRA: get_node(P_EDIT + "/GridScroll/PageExtra"),
	}
	_slot_buttons = [
		get_node(P_BOTTOM + "/SlotsBox/SlotsRow/Slot1"),
		get_node(P_BOTTOM + "/SlotsBox/SlotsRow/Slot2"),
		get_node(P_BOTTOM + "/SlotsBox/SlotsRow/Slot3"),
	]

	# 页签：一个 ButtonGroup 保证只有一个亮着
	var tab_group := ButtonGroup.new()
	for i in _tabs.size():
		var tab := _tabs[i]
		var slot: int = PartLibrary.TAB_ORDER[i]
		tab.button_group = tab_group
		tab.text = PartData.SLOT_NAMES[slot]
		tab.toggled.connect(_on_tab_toggled.bind(slot))

	# 帧槽：同样只亮一个
	var slot_group := ButtonGroup.new()
	for i in _slot_buttons.size():
		var b := _slot_buttons[i]
		b.button_group = slot_group
		b.toggled.connect(_on_slot_toggled.bind(i))

	_clear_button.pressed.connect(_on_clear_pressed)
	_confirm_button.pressed.connect(_on_confirm_pressed)


# ============================================================
# 部件卡（数据驱动，只能代码建）
# ============================================================

func _build_cards() -> void:
	for slot: int in PartLibrary.TAB_ORDER:
		var page: GridContainer = _pages[slot]
		var map: Dictionary = {}
		# slot_options 对「其他」会多给一个 null（留空）—— 组合数里的那个 7
		for opt: Variant in PartLibrary.slot_options(slot):
			var part: PartData = opt
			var key := "" if part == null else String(part.id)
			var card := _make_card(slot, part)
			page.add_child(card)
			map[key] = card
		_cards[slot] = map


func _make_card(slot: int, part: PartData) -> Button:
	var is_blank := part == null
	var key := "" if is_blank else String(part.id)

	var card := Button.new()
	card.name = "Card_" + ("blank" if is_blank else key)
	card.toggle_mode = true
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = Vector2(0, CARD_MIN_HEIGHT)
	# 【必须显式 EXPAND】GridContainer 只把剩余宽度分给带 SIZE_EXPAND 的子节点。
	# 少了这一行，三列各自缩到内容最小宽度、挤在左边，中文名会叠在一起。
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("normal", _button_sb(C_PANEL_SOFT, Color(0, 0, 0, 0), 0, 14))
	card.add_theme_stylebox_override("hover", _button_sb(Color("35353f"), C_LINE, 2, 14))
	card.add_theme_stylebox_override("pressed", _button_sb(Color("3d3d26"), C_ACCENT, 3, 14, 3))
	card.add_theme_stylebox_override("focus", _button_sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 14))
	card.toggled.connect(_on_card_toggled.bind(slot, key))

	# 内容放在子节点里，子节点全部 MOUSE_FILTER_IGNORE —— 点击必须透给按钮本身，
	# 否则 hover / pressed 状态会失灵
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	card.add_child(margin)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)

	var art := TextureRect.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.custom_minimum_size = Vector2(0, ART_HEIGHT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture = _thumb(part)
	box.add_child(art)

	var title := Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = "留空" if is_blank else part.display_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", C_TEXT_DIM if is_blank else C_TEXT)
	box.add_child(title)

	# 部件自身的情绪标签 —— 缩略图还是占位色块时，这行是玩家唯一能读的信息
	var tags := Label.new()
	tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tags.text = "不挂附加部件" if is_blank else part.emotion_labels()
	tags.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tags.add_theme_font_size_override("font_size", 13)
	tags.add_theme_color_override("font_color", C_TEXT_DIM)
	box.add_child(tags)

	return card


# ============================================================
# 交互
# ============================================================

func _on_tab_toggled(on: bool, slot: int) -> void:
	if _syncing or not on:
		return
	_tab = slot
	_show_tab()


func _on_slot_toggled(on: bool, index: int) -> void:
	if _syncing or not on:
		return
	_frame = index
	_sync_all()
	_flash_face()


func _on_card_toggled(on: bool, slot: int, key: String) -> void:
	if _syncing or not on:
		return

	var part: PartData = null
	if key != "":
		part = PartLibrary.by_id(key)
		if part == null:
			push_error("[录像机] 找不到部件 " + key)
			return

	# 写入的永远是已有的 Clip.Frame —— 录像机不维护自己的草稿结构
	var f: Clip.Frame = _clip.frames[_frame]
	match slot:
		PartData.Slot.EYES:
			f.eyes = part
		PartData.Slot.MOUTH:
			f.mouth = part
		PartData.Slot.BROWS:
			f.brows = part
		PartData.Slot.EXTRA:
			f.extra = part

	_bump_card(_cards[slot][key])
	_sync_all()


func _on_clear_pressed() -> void:
	var f: Clip.Frame = _clip.frames[_frame]
	f.eyes = null
	f.mouth = null
	f.brows = null
	f.extra = null
	_sync_all()
	_flash_face()


func _on_confirm_pressed() -> void:
	if not _clip.is_complete():
		_status_label.text = "还没拼完 —— " + _describe_missing()
		_status_label.add_theme_color_override("font_color", C_DANGER)
		return

	print("[录像机] 录好一段 3 帧表情包：%s" % _clip.summarize())
	print("[录像机] 帧序列：%s" % " → ".join(_clip.all_labels()))
	# 只发信号，不做任何投递动作 —— 录像机不认识公司，也不知道怎么投递
	EventBus.recorder_finished.emit(_clip)

	_bump_card(_confirm_button)
	_status_label.text = "已录好 —— 拿去微信私聊 HR 投递（下一轮接）"
	_status_label.add_theme_color_override("font_color", C_POSITIVE)


# ============================================================
# 刷新（只在状态变化时调用，不做 _process 轮询）
# ============================================================

func _sync_all() -> void:
	_sync_preview()
	_sync_emotion()
	_sync_slots()
	_sync_cards()
	_sync_status()
	_show_tab()


func _sync_preview() -> void:
	var f: Clip.Frame = _clip.frames[_frame]
	# 四层同坐标叠加 —— 占位图规格（512×512 共用画布、人脸中心 = 画布中心）的第一次实战检验
	_layer_brows.texture = null if f.brows == null else f.brows.texture
	_layer_eyes.texture = null if f.eyes == null else f.eyes.texture
	_layer_mouth.texture = null if f.mouth == null else f.mouth.texture
	_layer_extra.texture = null if f.extra == null else f.extra.texture
	_frame_badge.text = "帧 %d" % (_frame + 1)
	_frame_indicator.text = "正在编辑：帧 %d / %d" % [_frame + 1, _clip.frame_count()]
	# 空帧时给一句提示，否则取景框是一整块黑，看起来像坏了
	_face_hint.visible = f.parts().is_empty()


func _sync_emotion() -> void:
	var v := _clip.frame_vector(_frame)
	# 【必须走 Clip.frame_label】空帧要显示「平静」而不是「喜」（Emotion.dominant 在全零
	# 向量上返回 JOY，自己判就会重现那个 bug）
	_emotion_value.text = _clip.frame_label(_frame)
	_emotion_value.add_theme_color_override("font_color",
			NEUTRAL_COLOR if Emotion.is_empty(v) else EMOTION_COLORS[Emotion.dominant(v)])

	var names: Array[String] = []
	for part: PartData in _clip.frames[_frame].parts():
		names.append(part.display_name)
	_emotion_parts.text = "—" if names.is_empty() else " · ".join(names)

	_sequence_label.text = "帧序列：%s" % " → ".join(_clip.all_labels())


func _sync_slots() -> void:
	_syncing = true
	for i in _slot_buttons.size():
		var b := _slot_buttons[i]
		b.text = "帧 %d\n%s" % [i + 1, _clip.frame_label(i)]
		b.button_pressed = (i == _frame)
	_syncing = false


func _sync_cards() -> void:
	_syncing = true
	for slot: int in _cards:
		var f: Clip.Frame = _clip.frames[_frame]
		var selected: PartData = _part_of(f, slot)
		var key := "" if selected == null else String(selected.id)
		for k: String in _cards[slot]:
			var card: Button = _cards[slot][k]
			card.button_pressed = (k == key)
	_syncing = false


func _sync_status() -> void:
	var missing := _describe_missing()
	if missing.is_empty():
		_status_label.text = "3 帧都拼齐了 —— 可以录好"
		_status_label.add_theme_color_override("font_color", C_POSITIVE)
		_status_hint.text = "录好后表情包会被消耗，下一次要重新拼"
	else:
		_status_label.text = "还没拼完 —— " + missing
		_status_label.add_theme_color_override("font_color", C_ACCENT)
		_status_hint.text = "眼 / 嘴 / 眉 三件必填，其他可留空"
	_confirm_button.disabled = not _clip.is_complete()


func _show_tab() -> void:
	for slot: int in _pages:
		var page: GridContainer = _pages[slot]
		var want := slot == _tab
		if page.visible != want:
			page.visible = want
			if want:
				_fade_in(page)
	_syncing = true
	for i in _tabs.size():
		_tabs[i].button_pressed = (PartLibrary.TAB_ORDER[i] == _tab)
	_syncing = false


# ============================================================
# 工具
# ============================================================

## 缩略图 = 从 512 画布上裁一块，避免五官缩成几个像素（见 THUMB_CENTER 的说明）
func _thumb(part: PartData) -> Texture2D:
	if part == null or part.texture == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = part.texture
	atlas.region = THUMB_FULL if part.slot == PartData.Slot.EXTRA else THUMB_CENTER
	return atlas


func _part_of(f: Clip.Frame, slot: int) -> PartData:
	match slot:
		PartData.Slot.EYES:
			return f.eyes
		PartData.Slot.MOUTH:
			return f.mouth
		PartData.Slot.BROWS:
			return f.brows
		PartData.Slot.EXTRA:
			return f.extra
	return null


## 缺什么 —— 先说当前帧，当前帧齐了再说别的帧，避免玩家来回翻帧找问题
func _describe_missing() -> String:
	var here := _missing_in(_frame)
	if not here.is_empty():
		return "本帧还差 " + "、".join(here)
	for i in _clip.frame_count():
		var there := _missing_in(i)
		if not there.is_empty():
			return "帧 %d 还差 %s" % [i + 1, "、".join(there)]
	return ""


func _missing_in(index: int) -> Array[String]:
	var f: Clip.Frame = _clip.frames[index]
	var out: Array[String] = []
	if f.eyes == null:
		out.append("眼")
	if f.mouth == null:
		out.append("嘴")
	if f.brows == null:
		out.append("眉")
	return out


func _bump_card(node: Control) -> void:
	if node.size.x <= 0.0:
		return   # 还没排版，缩放没有支点，宁可不做动画
	node.pivot_offset = node.size * 0.5
	var tw := create_tween()
	node.scale = Vector2(0.94, 0.94)
	tw.tween_property(node, "scale", Vector2(1.06, 1.06), 0.07)
	tw.tween_property(node, "scale", Vector2.ONE, 0.07)


func _flash_face() -> void:
	_face_canvas.modulate.a = 0.2
	var tw := create_tween()
	tw.tween_property(_face_canvas, "modulate:a", 1.0, 0.13)


func _fade_in(node: Control) -> void:
	node.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(node, "modulate:a", 1.0, 0.12)


## 走带指示灯呼吸 —— 廉价器械感全靠这种小动静
func _pulse_rec_dot() -> void:
	var tw := create_tween().set_loops()
	tw.tween_property(_rec_dot, "modulate:a", 0.25, 0.9)
	tw.tween_property(_rec_dot, "modulate:a", 1.0, 0.9)


# ============================================================
# 样式（全部集中在代码里：静态骨架留在 .tscn，外观一处可改）
# ============================================================

func _apply_styles() -> void:
	get_node("Bg").color = C_BG

	# 顶栏只留一条亮色下边线 —— 整圈黄框太吵，机器丝印感来自「一条线」
	var top_sb := StyleBoxFlat.new()
	top_sb.bg_color = C_PANEL
	top_sb.border_width_bottom = 3
	top_sb.border_color = C_ACCENT
	get_node("Page/TopBar").add_theme_stylebox_override("panel", top_sb)

	_panel(get_node("Page/BodyWrap/Body/PreviewPanel"), C_PANEL, 20, 2, C_LINE)
	_panel(get_node(P_PREVIEW + "/ViewFinder"), Color("0f0f13"), 24, 3, C_LINE)
	_panel(get_node(P_PREVIEW + "/EmotionStrip"), C_PANEL_SOFT, 16, 0)
	_panel(get_node("Page/BodyWrap/Body/EditPanel"), C_PANEL, 20, 2, C_LINE)
	_panel(get_node("Page/BottomBar"), C_PAPER, 0, 0)

	# 部件多于四行时靠滚动兜住（现在的池子最多 10 件 = 4 行，正好不溢，但不能靠运气）
	var bar := _grid_scroll.get_v_scroll_bar()
	bar.custom_minimum_size = Vector2(10, 0)
	bar.add_theme_stylebox_override("scroll", _button_sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0, 0))
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = C_LINE
	grabber.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("grabber", grabber)
	bar.add_theme_stylebox_override("grabber_highlight", _rounded(C_ACCENT))
	bar.add_theme_stylebox_override("grabber_pressed", _rounded(C_ACCENT))

	# REC 红点
	var dot := StyleBoxFlat.new()
	dot.bg_color = C_DANGER
	dot.set_corner_radius_all(9)
	_rec_dot.add_theme_stylebox_override("panel", dot)

	# 画板虚位框 + 空帧提示
	var canvas_sb := StyleBoxFlat.new()
	canvas_sb.bg_color = Color(1, 1, 1, 0.015)
	canvas_sb.set_border_width_all(2)
	canvas_sb.border_color = Color(1, 1, 1, 0.06)
	canvas_sb.set_corner_radius_all(8)
	_canvas_frame.add_theme_stylebox_override("panel", canvas_sb)
	_face_hint.add_theme_font_size_override("font_size", 22)
	_face_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.16))
	_face_hint.add_theme_constant_override("line_spacing", 10)

	# 帧角标（在取景框左上角，像机器丝印）
	var badge := StyleBoxFlat.new()
	badge.bg_color = Color(0, 0, 0, 0.55)
	badge.set_corner_radius_all(8)
	badge.content_margin_left = 12
	badge.content_margin_right = 12
	badge.content_margin_top = 4
	badge.content_margin_bottom = 4
	_frame_badge.add_theme_stylebox_override("normal", badge)
	_frame_badge.add_theme_font_size_override("font_size", 18)
	_frame_badge.add_theme_color_override("font_color", C_ACCENT)

	# 顶栏文字
	_txt(get_node(P_TOP + "/RecGroup/RecText"), 18, C_DANGER)
	_txt(get_node(P_TOP + "/TitleBox/Title"), 40, C_TEXT)
	_txt(get_node(P_TOP + "/TitleBox/Subtitle"), 15, C_TEXT_DIM)
	_txt(_frame_indicator, 20, C_ACCENT)
	_txt(get_node(P_TOP + "/InfoBox/RuleHint"), 15, C_TEXT_DIM)

	# 取景框
	_txt(_emotion_value, 30, C_TEXT)
	_txt(get_node(P_PREVIEW + "/EmotionStrip/EmotionMargin/EmotionRow/EmotionCaption"), 15, C_TEXT_DIM)
	_txt(_emotion_parts, 16, C_TEXT_DIM)
	_txt(_sequence_label, 20, C_TEXT)
	_sequence_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# 页签
	for tab: Button in _tabs:
		tab.focus_mode = Control.FOCUS_NONE
		tab.custom_minimum_size = Vector2(0, 56)
		tab.add_theme_font_size_override("font_size", 20)
		tab.add_theme_stylebox_override("normal", _button_sb(C_PANEL_SOFT, C_LINE, 2, 12))
		tab.add_theme_stylebox_override("hover", _button_sb(Color("35353f"), C_LINE, 2, 12))
		tab.add_theme_stylebox_override("pressed", _button_sb(C_ACCENT, C_ACCENT, 2, 12))
		tab.add_theme_stylebox_override("focus", _button_sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 12))
		tab.add_theme_color_override("font_color", C_TEXT_DIM)
		tab.add_theme_color_override("font_hover_color", C_TEXT)
		tab.add_theme_color_override("font_pressed_color", C_INK)

	# 帧槽（选中态靠 content_margin 少 4px 实现「上浮」—— 容器会覆盖 position，动不了）
	for b: Button in _slot_buttons:
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 74)
		b.add_theme_font_size_override("font_size", 16)
		b.add_theme_stylebox_override("normal", _button_sb(Color("e3ddd0"), Color("cfc8b8"), 2, 12, 0, 12))
		b.add_theme_stylebox_override("hover", _button_sb(Color("efeadf"), C_ACCENT, 2, 12, 0, 12))
		b.add_theme_stylebox_override("pressed", _button_sb(C_INK, C_ACCENT, 3, 12, 4, 8))
		b.add_theme_stylebox_override("focus", _button_sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 12))
		b.add_theme_color_override("font_color", C_INK)
		b.add_theme_color_override("font_hover_color", C_INK)
		b.add_theme_color_override("font_pressed_color", C_ACCENT)

	# 底部按钮（纸面带上，用深色按钮压住）
	_style_button(_clear_button, Color("e3ddd0"), C_INK, C_LINE, 20)
	_style_button(_confirm_button, C_INK, C_ACCENT, C_ACCENT, 24)
	_confirm_button.add_theme_stylebox_override("disabled",
			_button_sb(Color("ddd6c8"), Color(0, 0, 0, 0), 0, 14, 0, 14))
	_confirm_button.add_theme_color_override("font_disabled_color", Color("9a948a"))

	# 底部文字
	_txt(get_node(P_BOTTOM + "/SlotsBox/SlotsCaption"), 15, C_TEXT_DIM)
	_txt(_status_label, 20, C_ACCENT)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_txt(_status_hint, 14, Color("8a8478"))
	_status_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _panel(node: Node, bg: Color, radius: int, border: int, border_color: Color = C_LINE) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border > 0:
		sb.set_border_width_all(border)
		sb.border_color = border_color
	node.add_theme_stylebox_override("panel", sb)


func _style_button(b: Button, bg: Color, fg: Color, border: Color, font_size: int) -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_stylebox_override("normal", _button_sb(bg, border, 2, 14))
	b.add_theme_stylebox_override("hover", _button_sb(bg.lightened(0.08), border, 3, 14))
	b.add_theme_stylebox_override("pressed", _button_sb(bg.darkened(0.1), border, 3, 14))


func _rounded(bg: Color, radius := 5) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	return sb


func _txt(node: Node, size: int, color: Color) -> void:
	var l := node as Control
	if l == null:
		return
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)


func _button_sb(bg: Color, border: Color, width: int, radius: int,
		content_lift := 0, pad := 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(width)
	sb.border_color = border
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = max(pad - content_lift, 2)
	sb.content_margin_bottom = pad + content_lift
	return sb
