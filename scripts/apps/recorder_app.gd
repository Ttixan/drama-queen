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
# 配色 —— 全部来自 UiPalette，与微信 / 占位图共用同一套
# ============================================================

const EMOTION_COLORS := UiPalette.EMOTION_COLORS

const C_BG := UiPalette.BG
const C_PANEL := UiPalette.PANEL
const C_PANEL_SOFT := UiPalette.PANEL_SOFT
const C_LINE := UiPalette.LINE
const C_PAPER := UiPalette.PAPER
const C_INK := UiPalette.INK
const C_TEXT := UiPalette.TEXT
const C_TEXT_DIM := UiPalette.TEXT_DIM
const C_ACCENT := UiPalette.ACCENT
const C_POSITIVE := UiPalette.POSITIVE
const C_DANGER := UiPalette.DANGER
const NEUTRAL_COLOR := UiPalette.TEXT_DIM

## 被当成「子页面」用时（微信里点「去录像机」、以后的手机壳）才需要返回。
## 独立运行时它是主场景，没有"上一步"可返回，所以按钮默认隐藏。
signal cancelled

## 【部件卡为什么是「一行一条」】右边那栏是**单列列表**（手稿：右栏只列一行内容），
## 卡片 = 左边一块缩略图 + 右边名字与情绪标签，高度 76 就够。
## 一格放不下就滚动兜住（嘴有 14 件，一屏只装得下 6 张）—— 不再按 3 列网格摊。
const CARD_MIN_HEIGHT := 76
const ART_HEIGHT := 56

## 页签图标（由 `tools/gen_ui_icons.gd` 生成的纯白简笔图）。
## 颜色不画进图里：Button 的 `icon_normal_color / icon_pressed_color` 负责上色，
## 同一张图在「未选中（灰）」和「选中（黄）」两态都不用重画。
const TAB_ICONS := {
	PartData.Slot.EYES: "res://assets/ui/icons/tab_eyes.png",
	PartData.Slot.MOUTH: "res://assets/ui/icons/tab_mouth.png",
	PartData.Slot.BROWS: "res://assets/ui/icons/tab_brows.png",
	PartData.Slot.EXTRA: "res://assets/ui/icons/tab_extra.png",
	PartData.Slot.SKIN: "res://assets/ui/icons/tab_skin.png",
}

## 底图 —— 不是部件，玩家选不了，所以不从 PartLibrary 取。
## `face_paper.png` 是整画布的白纸（压在最底下），`face_base.png` 是空白脸的轮廓 + 鼻子。
## 两张都由 `tools/import_emoji_layers.py` 生成；缺图时 `load()` 返回 null，画面退化成
## 「只有五官浮在黑底上」，界面不崩 —— 但那就说明美术管线没跑。
const TEX_PAPER := "res://assets/parts/face_paper.png"
const TEX_BASE := "res://assets/parts/face_base.png"


## 页签键的边长，以及图标在键里的最大显示尺寸
const TAB_SIZE := 60
const TAB_ICON_MAX := 38

## 帧槽键的边长。键面上只放一个数字 —— 「帧 1」三个字要 150 宽，数字 44 就够，
## 省下来的横向空间正好给右边的 +/-（帧数最多 5 个，5×44 + 4×8 = 252，底栏放得下）
const SLOT_SIZE := 44

## 【取景器为什么是「等比缩放 + 不裁」】它原来是个 `CenterContainer` 包着 512×512 的画板 ——
## 而**容器会把子节点的最小尺寸往上带**：取景器最小 518 → 预览列 644 → 整个 Page 1001，
## 而手机右栏只有 952。差的那 49px 从底栏扣，最底下那排（帧槽 / 确认）就被切掉一截，
## 看着就是「显示不全」（提提 10-16 报的）。
## 现在 `ViewCenter` 是 `AspectRatioContainer`（ratio = 1，stretch_mode = FIT），画板只报一个
## 很小的 `custom_minimum_size`（240×240）：**往上带的最小尺寸因此可以忽略**，取景器再矮也不会
## 把底栏顶出屏幕；同时画板整体**等比缩到能放下的最大方形**，四边都不会被切。
## 代价是画板不再是规格里的 512×512，而是「放着多少就是多少」（1920 宽下量到 621×621）。
## 四层贴图都是 `anchors_preset = 15` 撑满画板，坐标随之等比例缩放，不存在错位。
## 【画板为什么能一下长这么大】人脸列里现在**只剩取景框**：情绪条搬去了部件列顶部、
## 「帧序列」搬去了顶栏 —— 那些曾和画板抢竖向空间的条带，一个都不剩了。
## （量出来的数：右栏 1372×952、Body 高 663、取景框 646×627 → 画板 621×621
## —— 见 `tools/_probe_layout.gd`。）

## 【缩略图为什么必须裁】整张 512×512 画布缩到 56px 高，五官只剩几个像素，卡片等于没图。
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
## 页签轨是 Body 的**独立一列**（人脸的右邻、部件列的左邻），不在 EditPanel 里面
const P_TABS := "Page/BodyWrap/Body/TabRail"
const P_EDIT := "Page/BodyWrap/Body/EditPanel/EditMargin/EditBox"
const P_BOTTOM := "Page/BottomBar/BottomMargin/BottomRow"
const P_TOP := "Page/TopBar"
const P_STATS := P_TOP + "/Stats"

## 顶栏四个状态图标的中心位置 —— **按条子宽度的比例**给。
## 新美术稿把图标**画进条子里**了（旧稿是空条 + 四张独立的图标贴图），
## 这里量的是 1917×107 原图上四个图标的中心：828 / 1089 / 1347 / 1603。
## 顺序 = 闪电 / 面具 / 星星 / 金币，含义照主界面便利贴：行动点 / 演技 / 知名度 / 金钱。
## 条子走九宫格横向拉伸，写死像素换个宿主宽度就错位，所以只存比例。
const STAT_ANCHORS := [0.432, 0.568, 0.703, 0.836]
## 数字起点离图标中心多远：图标半宽 ≈27 + 间隙 12
const STAT_VALUE_OFFSET := 39.0
const STAT_VALUE_SIZE := 28
## 标题左边距：返回按钮的右沿（12 + 237）之后再留一段
const TITLE_X := 272.0

@onready var _back_button: TextureButton = get_node(P_TOP + "/BackButton")
@onready var _title: Label = get_node(P_TOP + "/Title")
## 顶栏里的 Stats 容器（高度 = 顶栏高，数字的垂直居中按它算）
@onready var _stats_box: Control = get_node(P_STATS)
@onready var _stat_icons: Array[TextureRect] = [
	get_node(P_STATS + "/IconAP"),
	get_node(P_STATS + "/IconActing"),
	get_node(P_STATS + "/IconFame"),
	get_node(P_STATS + "/IconMoney"),
]
@onready var _stat_values: Array[Label] = [
	get_node(P_STATS + "/ValueAP"),
	get_node(P_STATS + "/ValueActing"),
	get_node(P_STATS + "/ValueFame"),
	get_node(P_STATS + "/ValueMoney"),
]
@onready var _frame_info: Label = get_node(P_BOTTOM + "/StatusBox/FrameInfo")
@onready var _face_canvas: Control = get_node(P_FACE)
@onready var _frame_badge: Label = get_node(P_FACE + "/FrameBadge")
## 底图三层（纸 / 肤色 / 空白脸）—— .tscn 里的节点顺序就是绘制顺序，代码只负责填图
@onready var _layer_paper: TextureRect = get_node(P_FACE + "/LayerPaper")
@onready var _layer_skin: TextureRect = get_node(P_FACE + "/LayerSkin")
@onready var _layer_base: TextureRect = get_node(P_FACE + "/LayerBase")
@onready var _layer_brows: TextureRect = get_node(P_FACE + "/LayerBrows")
@onready var _layer_eyes: TextureRect = get_node(P_FACE + "/LayerEyes")
@onready var _layer_mouth: TextureRect = get_node(P_FACE + "/LayerMouth")
@onready var _layer_extra: TextureRect = get_node(P_FACE + "/LayerExtra")
@onready var _emotion_value: Label = get_node(
		P_EDIT + "/EmotionStrip/EmotionMargin/EmotionRow/EmotionValue")
@onready var _emotion_parts: Label = get_node(
		P_EDIT + "/EmotionStrip/EmotionMargin/EmotionRow/EmotionParts")
@onready var _canvas_frame: Panel = get_node(P_FACE + "/CanvasFrame")
@onready var _face_hint: Label = get_node(P_FACE + "/FaceHint")
@onready var _list_scroll: ScrollContainer = get_node(P_EDIT + "/ListScroll")
@onready var _status_label: Label = get_node(P_BOTTOM + "/StatusBox/StatusLabel")
@onready var _status_hint: Label = get_node(P_BOTTOM + "/StatusBox/StatusHint")
@onready var _slots_row: HBoxContainer = get_node(P_BOTTOM + "/SlotsBox/SlotsRow")
@onready var _frame_add: Button = get_node(P_BOTTOM + "/SlotsBox/FrameAdd")
@onready var _frame_remove: Button = get_node(P_BOTTOM + "/SlotsBox/FrameRemove")
@onready var _clear_button: Button = get_node(P_BOTTOM + "/ActionsRow/ClearButton")
@onready var _confirm_button: Button = get_node(P_BOTTOM + "/ActionsRow/ConfirmButton")

# ============================================================
# 状态
# ============================================================

var _clip: Clip
var _frame := 0                       ## 当前编辑的帧下标
var _tab: int = PartData.Slot.EYES    ## 当前页签
var _tabs: Array[Button] = []         ## 与 PartLibrary.TAB_ORDER 一一对应
var _pages: Dictionary = {}           ## slot -> VBoxContainer（一页 = 一张单列部件列表）
var _slot_buttons: Array[Button] = []
var _cards: Dictionary = {}           ## slot -> { key -> Button }
## "slot|key" -> {"part": PartData, "title": Label, "tags": Label}
## 【为什么建卡时要记下这两个 Label】解锁周次会让**同一张卡**在两种文案间来回切
## （「喜·魅」↔「第 2 周解锁」），而按节点树找 Label 又脆又长。
var _card_meta: Dictionary = {}
var _card_group: Dictionary = {}      ## slot -> ButtonGroup（同槽位内互斥）
## 程序化改按钮状态时会触发 toggled，用这个闸门防止自己把自己绕进去
var _syncing := false


func _ready() -> void:
	_clip = Clip.new()   # 默认就是 3 帧空 Frame，不用再补

	_collect_nodes()
	_load_base_art()
	_apply_blend_modes()
	_apply_styles()
	_layout_stats()
	_rebuild_slots()
	_build_cards()
	_sync_all()
	_refresh_stats()

	# 顶栏四项状态：数值的写入口有打工 / 上课 / 结算 / 事件四五条路径，
	# 与便利贴同一条口径 —— **每次都全量重读**，增量信号漏接一条就会留个旧数字。
	EventBus.ap_changed.connect(_on_counter_changed)
	EventBus.money_changed.connect(_on_value_changed)
	EventBus.acting_changed.connect(_on_value_changed)
	EventBus.fame_changed.connect(_on_value_changed)
	EventBus.day_advanced.connect(_on_day_changed)
	EventBus.state_reset.connect(_refresh_stats)
	# 顶栏宽度由宿主（手机右栏 / 整屏）决定，第一次布局完才量得准
	resized.connect(_layout_stats)


## 纸底与空白脸是**场景资源**，不随帧变 —— 建一次就够，不用每帧重设
func _load_base_art() -> void:
	_layer_paper.texture = load(TEX_PAPER)
	_layer_base.texture = load(TEX_BASE)
	if _layer_paper.texture == null or _layer_base.texture == null:
		push_warning("[录像机] 底图缺失，是不是忘了跑 tools/import_emoji_layers.py？")


## 【五官走「正片叠底」】眉/眼/嘴的图是**灰线 + 白填充**（眼白、牙齿），
## 按普通 alpha 叠法贴到深肤色上，那几块白就是贴在脸上的一块纸 —— 违和感全来自这里。
## 正片叠底是「乘」：白 × 肤色 = 肤色（白自动消失），灰线 × 肤色 = 比肤色更深的线，
## 于是无论底下是哪种肤色，五官都像是**长在这张脸上**的。
##
## 【为什么「其他」不跟着走】眼镜 / 脸红 / 汗滴是**挂在脸前面的东西**，不是脸上的线。
## 乘上去的话，深肤色会把红色镜框压成暗红（约 = 肤色 × 红），配件就没了。
## 两者要的是不同的合成语义，所以只给三层五官上材质。
##
## 【为什么用引擎自带的 MUL，而不是自己写着色器读屏幕纹理】那一版试过，不行：
## 屏幕纹理一帧只拷一次 backbuffer，后画的层拿到的是**旧底图**，
## 整块贴上去就把前一层盖掉了 —— 表现是「点一个部件，整张脸只剩这一层」。
## 现在素材在导入时已经把 RGB 预乘成「正片叠底友好」的形态
## （见 tools/import_emoji_layers.py 的 MULTIPLY_SLOTS：c' = 1 - a·(1-c)），
## MUL 直接就是正确结果，不读屏幕、也不依赖绘制顺序。
##
## 三层共用同一个材质实例：材质无状态，没必要建三份。
func _apply_blend_modes() -> void:
	var mul := CanvasItemMaterial.new()
	mul.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	for layer: TextureRect in [_layer_brows, _layer_eyes, _layer_mouth]:
		layer.material = mul


func _collect_nodes() -> void:
	# 顺序必须与 PartLibrary.TAB_ORDER 一一对应 —— 下面按下标把页签和槽位绑在一起
	_tabs = [
		get_node(P_TABS + "/TabEyes"),
		get_node(P_TABS + "/TabMouth"),
		get_node(P_TABS + "/TabBrows"),
		get_node(P_TABS + "/TabExtra"),
		get_node(P_TABS + "/TabSkin"),
	]
	_pages = {
		PartData.Slot.EYES: get_node(P_EDIT + "/ListScroll/PageEyes"),
		PartData.Slot.MOUTH: get_node(P_EDIT + "/ListScroll/PageMouth"),
		PartData.Slot.BROWS: get_node(P_EDIT + "/ListScroll/PageBrows"),
		PartData.Slot.EXTRA: get_node(P_EDIT + "/ListScroll/PageExtra"),
		PartData.Slot.SKIN: get_node(P_EDIT + "/ListScroll/PageSkin"),
	}
	# 帧槽按钮**不在这里取** —— 帧数可以增删，它们是 _rebuild_slots() 现建的

	# 页签：一个 ButtonGroup 保证只有一个亮着；键面只放图标（名字退到 tooltip）
	var tab_group := ButtonGroup.new()
	for i in _tabs.size():
		var tab := _tabs[i]
		var slot: int = PartLibrary.TAB_ORDER[i]
		tab.button_group = tab_group
		tab.icon = load(TAB_ICONS[slot])
		tab.tooltip_text = PartData.SLOT_NAMES[slot]
		tab.toggled.connect(_on_tab_toggled.bind(slot))

	_clear_button.pressed.connect(_on_clear_pressed)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_back_button.pressed.connect(func() -> void: cancelled.emit())
	_frame_add.pressed.connect(_on_add_frame)
	_frame_remove.pressed.connect(_on_remove_frame)


## 让调用方把录像机嵌进来时打开「返回」（见 wechat_app.gd 的「去录像机」）
func enable_back() -> void:
	_back_button.visible = true


# ============================================================
# 帧槽（按帧数现建：帧数本身可增删）
# ============================================================

## 【为什么帧槽不能像页签那样摆死在 .tscn 里】帧数会变（下面那对 +/-），
## 而按钮数量、互斥组、按钮上写的数字都得跟着帧数走 —— 摆死的三个节点改到第四帧就没辙了。
func _rebuild_slots() -> void:
	for c in _slots_row.get_children():
		# 【必须 remove_child + queue_free】只 queue_free 的话节点要等这一帧结束才真的走，
		# 紧接着 add_child 会让新旧按钮在同一个 HBox 里并排站一帧 —— 屏幕上是 6 个槽
		_slots_row.remove_child(c)
		c.queue_free()
	_slot_buttons.clear()

	var group := ButtonGroup.new()
	for i in _clip.frame_count():
		var b := Button.new()
		b.name = "Slot%d" % (i + 1)
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		b.add_theme_font_size_override("font_size", 20)
		b.add_theme_stylebox_override("normal", _button_sb(UiPalette.PAPER_SOFT, UiPalette.PAPER_LINE, 2, 10, 0, 0))
		b.add_theme_stylebox_override("hover", _button_sb(UiPalette.PAPER_HOVER, C_ACCENT, 2, 10, 0, 0))
		b.add_theme_stylebox_override("pressed", _button_sb(C_INK, C_ACCENT, 3, 10, 0, 0))
		b.add_theme_stylebox_override("focus", _button_sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 10, 0, 0))
		b.add_theme_color_override("font_color", C_INK)
		b.add_theme_color_override("font_hover_color", C_INK)
		b.add_theme_color_override("font_pressed_color", C_ACCENT)
		b.toggled.connect(_on_slot_toggled.bind(i))
		_slots_row.add_child(b)
		_slot_buttons.append(b)


# ============================================================
# 部件卡（数据驱动，只能代码建）
# ============================================================

func _build_cards() -> void:
	for slot: int in PartLibrary.TAB_ORDER:
		var page: VBoxContainer = _pages[slot]
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
	# 【必须显式 EXPAND】列表只把剩余宽度分给带 SIZE_EXPAND 的子节点。
	# 少了这一行，卡片会缩到内容宽度，右边一大片点不到。
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("normal", _button_sb(C_PANEL_SOFT, Color(0, 0, 0, 0), 0, 12, 0, 10))
	card.add_theme_stylebox_override("hover", _button_sb(Color("35353f"), C_LINE, 2, 12, 0, 10))
	card.add_theme_stylebox_override("pressed", _button_sb(Color("3d3d26"), C_ACCENT, 3, 12, 0, 8))
	card.add_theme_stylebox_override("focus", _button_sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 12, 0, 10))
	# 未解锁的卡：压暗一档、去掉描边 —— 「看得见，但现在点不了」
	card.add_theme_stylebox_override("disabled", _button_sb(Color("26262c"), Color(0, 0, 0, 0), 0, 12, 0, 10))
	card.toggled.connect(_on_card_toggled.bind(slot, key))

	# 内容放在子节点里，子节点全部 MOUSE_FILTER_IGNORE —— 点击必须透给按钮本身，
	# 否则 hover / pressed 状态会失灵
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	card.add_child(margin)

	# 一行一条：缩略图钉在左边，名字与情绪标签在右边顺排
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	var art := TextureRect.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.custom_minimum_size = Vector2(ART_HEIGHT, ART_HEIGHT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture = _thumb(part)
	row.add_child(art)

	var info := VBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER   # 两行字整体贴卡片中线，别顶在上沿
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)

	var title := Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = "留空" if is_blank else part.display_name
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", C_TEXT_DIM if is_blank else C_TEXT)
	info.add_child(title)

	# 部件自身的情绪标签 —— 缩略图还是占位色块时，这行是玩家唯一能读的信息
	var tags := Label.new()
	tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tags.text = "不挂附加部件" if is_blank else part.emotion_labels()
	tags.add_theme_font_size_override("font_size", 13)
	tags.add_theme_color_override("font_color", C_TEXT_DIM)
	info.add_child(tags)

	# 解锁状态要能改文案，所以把这两行字交给 _sync_locks() 管
	_card_meta["%d|%s" % [slot, key]] = {"part": part, "title": title, "tags": tags}

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


## 末尾加一帧并跳过去 —— 「多演一帧」是这个动作的全部意义，加完还停在原地很奇怪
func _on_add_frame() -> void:
	if _clip.add_frame() < 0:
		return
	_frame = _clip.frame_count() - 1
	_after_frame_count_changed()


## 删的是**当前这一帧**，不是末尾：玩家点着第 2 帧按减号，期待消失的就是第 2 帧
func _on_remove_frame() -> void:
	if not _clip.remove_frame(_frame):
		return
	_frame = clampi(_frame, 0, _clip.frame_count() - 1)
	_after_frame_count_changed()


## 帧数变了：按钮先重建（数量变了），再整体刷一遍；换帧那一下给个闪，让眼睛跟得上
func _after_frame_count_changed() -> void:
	_rebuild_slots()
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
		PartData.Slot.SKIN:
			f.skin = part

	_bump_card(_cards[slot][key])
	_sync_all()


func _on_clear_pressed() -> void:
	var f: Clip.Frame = _clip.frames[_frame]
	f.eyes = null
	f.mouth = null
	f.brows = null
	f.extra = null
	f.skin = null      # 肤色回到默认那件，而不是「没有肤色」
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
# 顶栏状态（四项数值 + 图标布局）
# ============================================================

## 数字按**条子宽度的比例**定位到各自图标的右侧。
## 每次 resized 都重算 —— 录像机既能整屏跑，也会被塞进手机右栏（≈1372 宽）。
##
## 【图标为什么不再参与布局】新稿把四个图标画进条子里了，四张 `stat_*.png`
## 只留着不显示（见 `_apply_styles`）—— 再叠一层会和画上去的图标错开成重影。
func _layout_stats() -> void:
	var w := size.x
	# 【高度必须取顶栏、不是整个 App】原来写的是 `size.y`（1920×1080 里的 1080），
	# 数字于是垂直居中到屏幕中间去了 —— 顶栏上只剩图标，数字被下面板子盖住。
	var h := _stats_box.size.y
	if w <= 1.0 or h <= 1.0:
		return

	for i in _stat_values.size():
		var cx: float = STAT_ANCHORS[i] * w
		var value := _stat_values[i]
		value.position = Vector2(cx + STAT_VALUE_OFFSET, 0.0)
		value.size = Vector2(maxf(90.0, w - cx), h)
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


## 顶栏四项状态。单独跑录像机时 `Game.state` 可能为空
## （`godot --path . res://scenes/minigame/recorder.tscn`），那时显示 "-"，不抛空指针。
func _refresh_stats() -> void:
	if Game.state == null:
		for value in _stat_values:
			value.text = "-"
		return

	var texts := [
		str(Game.ap_left()),
		str(Game.acting()),
		str(Game.fame()),
		str(Game.money()),
	]
	for i in _stat_values.size():
		_stat_values[i].text = texts[i]


## 行动点：`ap_changed(left)` —— 只带剩余量
func _on_counter_changed(_left: int) -> void:
	_refresh_stats()


## 金钱 / 演技 / 知名度：`xxx_changed(value, delta)`
func _on_value_changed(_value: int, _delta: int) -> void:
	_refresh_stats()


func _on_day_changed(_day: int, _week: int) -> void:
	_refresh_stats()


# ============================================================
# 刷新（只在状态变化时调用，不做 _process 轮询）
# ============================================================

func _sync_all() -> void:
	_sync_preview()
	_sync_emotion()
	_sync_slots()
	_sync_locks()
	_sync_cards()
	_sync_status()
	_show_tab()


func _sync_preview() -> void:
	var f: Clip.Frame = _clip.frames[_frame]
	# 七层同坐标叠加 —— 占位图规格（512×512 共用画布、人脸中心 = 画布中心）的第一次实战检验。
	# 从下往上：纸 → 肤色 → 空白脸 → 眉 → 眼 → 嘴 → 其他。
	# 【肤色与底图永远有】空帧也是一张白纸上的人脸，不是一块黑 —— 玩家一眼就知道「脸还在，只是没拼五官」。
	_layer_skin.texture = _skin_texture(f)
	_layer_brows.texture = null if f.brows == null else f.brows.texture
	_layer_eyes.texture = null if f.eyes == null else f.eyes.texture
	_layer_mouth.texture = null if f.mouth == null else f.mouth.texture
	_layer_extra.texture = null if f.extra == null else f.extra.texture
	_frame_badge.text = "帧 %d" % (_frame + 1)
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

	# 帧号 + 帧序列总览。原先在顶栏右端（那栏现在整条让给状态图标了），
	# 落在底栏状态区 —— 它描述的是「整段表演」，和底栏的完成度提示是同一件事。
	_frame_info.text = "帧 %d / %d · %s" % [
			_frame + 1, _clip.frame_count(), " → ".join(_clip.all_labels())]


func _sync_slots() -> void:
	_syncing = true
	for i in _slot_buttons.size():
		var b := _slot_buttons[i]
		# 键面只留数字，情绪退到 tooltip —— 两行字在 44 的键上放不下，
		# 而情绪本来在右边「当前帧情绪」和顶栏「帧序列」都读得到
		b.text = str(i + 1)
		b.tooltip_text = "帧 %d · %s" % [i + 1, _clip.frame_label(i)]
		b.button_pressed = (i == _frame)
	# 到头了就置灰，别让玩家点了没反应还以为是卡了
	_frame_add.disabled = _clip.frame_count() >= Clip.MAX_FRAME_COUNT
	_frame_remove.disabled = _clip.frame_count() <= Clip.MIN_FRAME_COUNT
	_syncing = false


## 解锁状态：还没到手的部件**照常列出来，但按住不让点**。
##
## 【为什么不干脆不列】「看不见」和「还差一点才到手」是两种完全不同的信息。
## 灰着摆在那里本身就是进度条：玩家第一周就能看见后面还有什么，才会为了它继续玩。
## 【为什么每次刷新都重算】两种门都会在游戏开着的时候变：周次会推进、
## 翻牌会在结算后把一整套点亮。重算一遍只有 53 次比较，比订阅信号简单。
func _sync_locks() -> void:
	for meta_key: String in _card_meta:
		var meta: Dictionary = _card_meta[meta_key]
		var part: PartData = meta["part"]
		if part == null:
			continue   # 「留空」那张永远可用
		var hint := _lock_hint(part)
		var locked := not hint.is_empty()
		var card: Button = _cards[part.slot][String(part.id)]
		var title: Label = meta["title"]
		var tags: Label = meta["tags"]
		card.disabled = locked
		card.tooltip_text = hint
		title.add_theme_color_override("font_color", C_TEXT_DIM if locked else C_TEXT)
		tags.text = hint if locked else part.emotion_labels()
		tags.add_theme_color_override("font_color",
				UiPalette.TEXT_DISABLED if locked else C_TEXT_DIM)


## 这件为什么现在点不了（空串 = 能用）。
## 【两种门要分开写】周次门（爆缸笑脸 / 绿豆蛙）等得起，翻牌门（得意 /
## 皮笑肉不笑 / 想起已故的爱人）得先在本周的结算里赢一张牌 ——
## 都写成「未解锁」的话，玩家不知道该等还是该去演。
func _lock_hint(part: PartData) -> String:
	if Game.is_part_unlocked(part):
		return ""
	if not String(part.set_id).is_empty():
		return "翻牌获得"
	return "第 %d 周解锁" % part.unlock_week


func _locked_count() -> int:
	var n := 0
	for part: PartData in PartLibrary.all():
		if not Game.is_part_unlocked(part):
			n += 1
	return n


func _sync_cards() -> void:
	_syncing = true
	for slot: int in _cards:
		var f: Clip.Frame = _clip.frames[_frame]
		var key := _selected_key(f, slot)
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
		# 有灰着的部件就顺带解释一句，否则玩家会以为那是坏图
		var locked := _locked_count()
		_status_hint.text = "眼 / 嘴 / 眉 三件必填，其他可留空"
		if locked > 0:
			_status_hint.text = "灰着的 %d 件随周次解锁 · 眼 / 嘴 / 眉 三件必填" % locked
	_confirm_button.disabled = not _clip.is_complete()


func _show_tab() -> void:
	for slot: int in _pages:
		var page: VBoxContainer = _pages[slot]
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
		PartData.Slot.SKIN:
			return f.skin
	return null


## 当前帧在这个槽位上「亮着」的那张卡。
## 【肤色要特判】`f.skin == null` 画面上用的是默认肤色，卡片却不亮的话，
## 玩家会以为自己这张脸没有肤色、或者以为选项坏了。
func _selected_key(f: Clip.Frame, slot: int) -> String:
	var p := _part_of(f, slot)
	if p != null:
		return String(p.id)
	return PartLibrary.DEFAULT_SKIN_ID if slot == PartData.Slot.SKIN else ""


## 画面上的肤色：没选过就用默认那件
func _skin_texture(f: Clip.Frame) -> Texture2D:
	var skin: PartData = f.skin if f.skin != null else PartLibrary.default_skin()
	return null if skin == null else skin.texture


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


# ============================================================
# 样式（全部集中在代码里：静态骨架留在 .tscn，外观一处可改）
# ============================================================

func _apply_styles() -> void:
	get_node("Bg").color = C_BG

	# 顶栏整条是美术给的手绘纸（NinePatchRect 走九宫格横向拉伸，两端卷角不动）。

	_panel(get_node("Page/BodyWrap/Body/PreviewPanel"), C_PANEL, 20, 2, C_LINE)
	_panel(get_node(P_PREVIEW + "/ViewFinder"), Color("0f0f13"), 24, 3, C_LINE)
	_panel(get_node(P_EDIT + "/EmotionStrip"), C_PANEL_SOFT, 16, 0)
	_panel(get_node("Page/BodyWrap/Body/EditPanel"), C_PANEL, 20, 2, C_LINE)
	_panel(get_node("Page/BottomBar"), C_PAPER, 0, 0)

	# 列表装不下就靠滚动兜住（嘴有 14 件，一屏只放 6 张 —— 必须能滚，不能靠运气）
	var bar := _list_scroll.get_v_scroll_bar()
	bar.custom_minimum_size = Vector2(10, 0)
	bar.add_theme_stylebox_override("scroll", _button_sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0, 0))
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = C_LINE
	grabber.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("grabber", grabber)
	bar.add_theme_stylebox_override("grabber_highlight", _rounded(C_ACCENT))
	bar.add_theme_stylebox_override("grabber_pressed", _rounded(C_ACCENT))

	# 画板虚位框 + 空帧提示
	var canvas_sb := StyleBoxFlat.new()
	canvas_sb.bg_color = Color(1, 1, 1, 0.015)
	canvas_sb.set_border_width_all(2)
	canvas_sb.border_color = Color(1, 1, 1, 0.06)
	canvas_sb.set_corner_radius_all(8)
	_canvas_frame.add_theme_stylebox_override("panel", canvas_sb)
	# 【提示字改成深色 + 缩到画布底部一行小字】画板底下现在压着**白纸**（face_paper），
	# 浅色字会彻底看不见；而底图是常驻的（空帧也有一张脸），字留在正中就压在脸上。
	_face_hint.add_theme_font_size_override("font_size", 16)
	_face_hint.add_theme_color_override("font_color", Color(0.16, 0.13, 0.09, 0.38))
	_face_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_face_hint.offset_bottom = -10.0
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

	# 顶栏：条子是浅灰纸，字一律压墨色（C_TEXT 是奶白，在纸上看不见）
	UiPalette.title(_title, 34, C_INK)
	for value in _stat_values:
		UiPalette.title(value, STAT_VALUE_SIZE, C_INK)
	# 四个图标已经画在条子里了，这四张贴图全部收起 —— 留着会和画上去的重影
	for icon in _stat_icons:
		icon.visible = false

	# 帧号 + 帧序列：底栏第三行，比「还没拼完」淡一档，不抢主提示
	_txt(_frame_info, 15, UiPalette.TEXT_ON_PAPER_DIM)

	# 情绪条（现在挂在部件列顶部，紧挨着它描述的那张列表）
	_txt(_emotion_value, 30, C_TEXT)
	_txt(get_node(P_EDIT + "/EmotionStrip/EmotionMargin/EmotionRow/EmotionCaption"), 15, C_TEXT_DIM)
	_txt(_emotion_parts, 16, C_TEXT_DIM)

	# 页签：一条竖轨上的方形图标键。图形是纯白的（tools/gen_ui_icons.gd），
	# 颜色全在这里给 —— 未选中灰、选中黄，同一张图两态复用。
	for tab: Button in _tabs:
		tab.focus_mode = Control.FOCUS_NONE
		tab.custom_minimum_size = Vector2(TAB_SIZE, TAB_SIZE)
		tab.add_theme_stylebox_override("normal", _button_sb(C_PANEL_SOFT, C_LINE, 2, 14, 0, 0))
		tab.add_theme_stylebox_override("hover", _button_sb(Color("35353f"), C_LINE, 2, 14, 0, 0))
		tab.add_theme_stylebox_override("pressed", _button_sb(C_ACCENT, C_ACCENT, 2, 14, 0, 0))
		tab.add_theme_stylebox_override("focus", _button_sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 14, 0, 0))
		tab.add_theme_constant_override("icon_max_width", TAB_ICON_MAX)
		# 未选中的图标要「看得见但不出头」——直接用 TEXT_DIM 压在 PANEL_SOFT 上太灰，
		# 玩家认不出是眼还是眉；提亮一档，选中的黄底压深色（C_INK）
		tab.add_theme_color_override("icon_normal_color", C_TEXT_DIM.lightened(0.18))
		tab.add_theme_color_override("icon_hover_color", C_TEXT)
		tab.add_theme_color_override("icon_pressed_color", C_INK)

	# 帧槽的样式在 _rebuild_slots() 里 —— 那些按钮是现建的，这里的循环够不到
	# 增删帧：与帧槽同一套纸面配色，但**不铺底**（次要动作不该和帧槽一样重）
	for b: Button in [_frame_remove, _frame_add]:
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 26)
		b.add_theme_stylebox_override("normal", _button_sb(Color(0, 0, 0, 0), UiPalette.PAPER_LINE, 2, 10, 0, 0))
		b.add_theme_stylebox_override("hover", _button_sb(C_ACCENT, C_ACCENT, 2, 10, 0, 0))
		b.add_theme_stylebox_override("pressed", _button_sb(C_INK, C_ACCENT, 2, 10, 0, 0))
		b.add_theme_stylebox_override("focus", _button_sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 10, 0, 0))
		b.add_theme_stylebox_override("disabled", _button_sb(Color(0, 0, 0, 0), UiPalette.PAPER_DISABLED, 2, 10, 0, 0))
		b.add_theme_color_override("font_color", C_INK)
		b.add_theme_color_override("font_hover_color", C_INK)
		b.add_theme_color_override("font_pressed_color", C_ACCENT)
		b.add_theme_color_override("font_disabled_color", UiPalette.TEXT_DISABLED)

	# 底部按钮（纸面带上，用深色按钮压住）。两个都是文字键：
	# 「完成」是主操作，字大一号、深底黄边；「清空」是次要的，字小一号、浅底
	_style_button(_clear_button, UiPalette.PAPER_SOFT, C_INK, C_LINE, 20)
	_style_button(_confirm_button, C_INK, C_ACCENT, C_ACCENT, 24)
	_confirm_button.add_theme_stylebox_override("disabled",
			_button_sb(UiPalette.PAPER_DISABLED, Color(0, 0, 0, 0), 0, 14, 0, 14))
	_confirm_button.add_theme_color_override("font_disabled_color", UiPalette.TEXT_DISABLED)

	# 底部文字
	_txt(get_node(P_BOTTOM + "/SlotsBox/SlotsCaption"), 15, C_TEXT_DIM)
	_txt(_status_label, 20, C_ACCENT)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_txt(_status_hint, 14, UiPalette.TEXT_ON_PAPER_DIM)
	_status_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _panel(node: Node, bg: Color, radius: int, border: int, border_color: Color = C_LINE) -> void:
	node.add_theme_stylebox_override("panel", UiPalette.panel(bg, radius, border, border_color))


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
	return UiPalette.rounded(bg, radius)


func _txt(node: Node, size: int, color: Color) -> void:
	UiPalette.text(node, size, color)


func _button_sb(bg: Color, border: Color, width: int, radius: int,
		content_lift := 0, pad := 14) -> StyleBoxFlat:
	return UiPalette.button(bg, border, width, radius, content_lift, pad)
