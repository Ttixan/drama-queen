extends Control
## 每周一的《有瓜有戏》—— **一版报纸**
##
## 【为什么从"卡片列表"改成报纸】这一版是这个游戏唯一的夸奖 / 批评出口：
## 判定公式是隐藏的，玩家只能从标题的语气里读出"这周我到底演得怎么样"。
## 卡片列表把头条和账目排成同一串行，读起来像结算单；报纸把头版、那张脸、
## 明细分成栏，才像"有人把你的表演写成了新闻"。
##
## 【报纸上为什么要有玩家自己的表情】标题说的是"这个人演得怎么样"，
## 而那张脸就是他去试镜时递出去的东西 —— 两者放在同一版上，因果关系才看得见。
## 表情来自履历里存的部件 id（见 `DailyActions.submit`），不是现拼的。
##
## 【只读 report，不重算任何东西】所有数字都来自 `WeekCycle.settle()` 的返回值。
##
## 【被当成浮层用时】由日历屏实例化（`report` 在 add_child 之前设好），
## 点「翻篇」发 `dismissed` 让调用方把自己清掉。

signal dismissed

## 由调用方在 add_child 之前赋值。**必须能在 _ready() 里读到**。
var report: Dictionary = {}

@onready var _edition: Label = get_node("Center/Paper/PaperMargin/PaperBox/Masthead/Edition")
@onready var _title: Label = get_node("Center/Paper/PaperMargin/PaperBox/Masthead/PaperName")
@onready var _day_label: Label = get_node("Center/Paper/PaperMargin/PaperBox/Masthead/DayLabel")
@onready var _face_caption: Label = get_node(
		"Center/Paper/PaperMargin/PaperBox/Body/Left/FaceCaption")
@onready var _face_frame: PanelContainer = get_node(
		"Center/Paper/PaperMargin/PaperBox/Body/Left/FaceFrame")
@onready var _face_stage: Control = get_node(
		"Center/Paper/PaperMargin/PaperBox/Body/Left/FaceFrame/FaceStage")
@onready var _face_note: Label = get_node(
		"Center/Paper/PaperMargin/PaperBox/Body/Left/FaceNote")
@onready var _headline_box: VBoxContainer = get_node(
		"Center/Paper/PaperMargin/PaperBox/Body/Right/HeadlineBox")
@onready var _scroll: ScrollContainer = get_node(
		"Center/Paper/PaperMargin/PaperBox/Body/Right/RightScroll")
@onready var _content: VBoxContainer = get_node(
		"Center/Paper/PaperMargin/PaperBox/Body/Right/RightScroll/ContentMargin/Content")
@onready var _foot_hint: Label = get_node("Center/Paper/PaperMargin/PaperBox/Footer/FootHint")
@onready var _next_button: Button = get_node("Center/Paper/PaperMargin/PaperBox/Footer/NextButton")

## 报纸红：头版标题那个色。纸面是米白的，深红压上去才像印出来的
const NEWS_RED := Color("9d2b2f")
## 账目在纸上的正 / 负色 —— 不用 UiPalette.POSITIVE / DANGER
## （那两个是给深色底调的高饱和色，压在米白纸上会发飘）
const MONEY_GOOD := Color("2f7d4f")
const MONEY_BAD := Color("b0363a")

## 脸部底图：空白脸的**轮廓 + 鼻子**。与录像机共用同一张，不是可选部件。
## 【为什么必须补它】只叠肤色 + 五官，印出来就是一块没有边、没有鼻子的色块 ——
## 玩家会在报纸上认不出那是录像机里那张脸。
const FACE_BASE := "res://assets/parts/face_base.png"

## 已经翻到结局页了没有 —— 决定底部的按钮是「看结局」还是「翻篇」
var _on_ending := false

## 底图只加载一次；`CanvasItemMaterial` 也只用一份（材质无状态）
var _base_tex: Texture2D
var _mul_material: CanvasItemMaterial


func _ready() -> void:
	_base_tex = load(FACE_BASE)
	if _base_tex == null:
		push_warning("[周报] 缺 %s —— 报纸上的脸会没有轮廓和鼻子" % FACE_BASE)
	# 【五官走正片叠底】部件图是灰线 + 白填充（眼白、牙齿），不乘的话白色会把
	# 底下的肤色和鼻子整块盖住。口径与 `recorder_app._apply_blend_modes` 一致。
	_mul_material = CanvasItemMaterial.new()
	_mul_material.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_apply_styles()
	_next_button.pressed.connect(_on_next_pressed)
	_build_week()


# ============================================================
# 头版：新闻标题 + 那张脸 + 明细与账
# ============================================================
func _build_week() -> void:
	_on_ending = false
	_clear()
	var week := int(report.get("week", 1))
	_edition.text = "第 %d 期" % week
	_title.text = "《有瓜有戏》"
	_day_label.text = "第 %d 天 · 第 %d 周结算" % [int(report.get("day", 0)), week]

	_build_face()
	_build_headlines()
	_build_plays()
	_build_ledger()
	_build_deltas()

	var ending: Dictionary = report.get("ending", {})
	if ending.is_empty():
		var next_day := mini(int(report.get("day", 0)) + 1, GameState.TOTAL_DAYS)
		_foot_hint.text = "这一版翻过去就是第 %d 天。下一期报纸在第 %d 天。" % [
			next_day,
			mini(int(report.get("day", 0)) + GameState.DAYS_PER_WEEK, GameState.TOTAL_DAYS)]
		_next_button.text = "翻篇"
	else:
		_foot_hint.text = "三周结束了 —— 你这三周的下场，就在下一页。"
		_next_button.text = "看结局"


## 左栏：本周**匹配度最高**那部戏的表情。
## 【为什么取最高分而不是最后一部】报纸要夸的是"这周你最好的一面"，
## 最后一部可能刚好是那天赶时间随手拼的。
func _build_face() -> void:
	for child in _face_stage.get_children():
		child.queue_free()

	var play := _best_play()
	if play.is_empty():
		_face_caption.text = "本周没有播出的戏"
		_face_note.text = "没有投出去的作品，也就没有脸可上报纸 —— 下周再拼一张。"
	else:
		_face_caption.text = "本周高分表情"
		var entry: Dictionary = play.get("entry", {})
		var code := String(entry.get("company_code", ""))
		var company := CompanyLibrary.by_code(code)
		_face_note.text = "《%s》· %s · 匹配 %.0f%%\n这张脸，就是它被投出去时的那张。" % [
			String(entry.get("play_title", "剧名缺失")),
			company.display_name if company != null else code,
			float(play.get("match_rate", 0.0)) * 100.0]

	# 固定六层，空槽留 null 但下标不变 —— 下标 2..4 要靠它判断走不走正片叠底
	var layers := _face_layers(play)
	for i in layers.size():
		var tex: Texture2D = layers[i]
		if tex == null:
			continue
		var layer := TextureRect.new()
		layer.texture = tex
		layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i >= 2 and i <= 4:
			layer.material = _mul_material
		layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_face_stage.add_child(layer)


func _best_play() -> Dictionary:
	var best: Dictionary = {}
	for p: Dictionary in report.get("plays", []):
		if best.is_empty() or float(p.get("match_rate", 0.0)) > float(best.get("match_rate", 0.0)):
			best = p
	return best


## 从履历里的部件 id 还原那张脸，按「肤色 → 眉 → 眼 → 嘴 → 其他」的顺序叠。
## 取**情绪最纯**的那一帧：报纸上要的是最有戏的表情，不是第一帧。
## 六层，顺序与录像机一致：肤色 → 空白脸（轮廓 + 鼻子）→ 眉 → 眼 → 嘴 → 其他。
## 空槽留 null 而不是省略 —— 调用方按**下标**决定哪几层要走正片叠底。
func _face_layers(play: Dictionary) -> Array[Texture2D]:
	var f: Clip.Frame = null
	if not play.is_empty():
		var entry: Dictionary = play.get("entry", {})
		var raw: Variant = entry.get("clip", null)
		if typeof(raw) == TYPE_DICTIONARY:
			var clip := Clip.from_save_dict(raw)
			if clip != null and clip.frame_count() > 0:
				f = clip.frames[_purest_frame(clip)]

	var skin: PartData = PartLibrary.default_skin()
	if f != null and f.skin != null:
		skin = f.skin
	var out: Array[Texture2D] = [
		null if skin == null else skin.texture,   # 0 肤色
		_base_tex,                                # 1 空白脸（轮廓 + 鼻子）
		null if f == null or f.brows == null else f.brows.texture,   # 2 眉
		null if f == null or f.eyes == null else f.eyes.texture,     # 3 眼
		null if f == null or f.mouth == null else f.mouth.texture,   # 4 嘴
		null if f == null or f.extra == null else f.extra.texture,   # 5 其他
	]
	return out


## 表情包里情绪最纯的那一帧 —— 报纸上要的是最有戏的那张脸，不是第一帧。
func _purest_frame(clip: Clip) -> int:
	var best := 0
	var best_purity := -1.0
	for i in clip.frame_count():
		var purity := clip.frame_purity(i)
		if purity > best_purity:
			best_purity = purity
			best = i
	return best


## 头版标题。第一条用报纸红加大字号 —— 报纸的头条本来就该压过其它所有字。
func _build_headlines() -> void:
	var heads: Array = report.get("headlines", [])
	if heads.is_empty():
		var none := Label.new()
		none.text = "这一期没有你的戏 —— 头版只好空着。"
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiPalette.text(none, 24, UiPalette.PAGE_INK_FAINT)
		_headline_box.add_child(none)
		return
	for i in heads.size():
		var l := Label.new()
		l.text = String(heads[i])
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiPalette.text(l, 42 if i == 0 else 23, NEWS_RED if i == 0 else UiPalette.INK)
		_headline_box.add_child(l)


## 本周每一部戏的明细。玩家要能从这一行读出「我为什么拿了低分」。
func _build_plays() -> void:
	var plays: Array = report.get("plays", [])
	_section("本周播出 %d 部" % plays.size())
	if plays.is_empty():
		_note("这周没有成功投出去的作品 —— 没有戏，也就没有播出。")
		return
	for p: Dictionary in plays:
		_play_row(p)


func _play_row(p: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
			UiPalette.panel(UiPalette.PAPER_SOFT, 3, 1, UiPalette.PAPER_LINE))
	_content.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)

	# 【剧名】与公司 / 档位来自履历；档位、片酬、各项增量来自播出结果
	var entry: Dictionary = p.get("entry", {})
	var code := String(entry.get("company_code", ""))
	var company := CompanyLibrary.by_code(code)
	var cast_name := String(RoleRequirement.TIER_NAMES.get(int(p.get("cast", 0)), "?"))
	var head := Label.new()
	head.text = "《%s》 ｜ %s · %s" % [
		String(entry.get("play_title", "剧名缺失")),
		company.display_name if company != null else code,
		cast_name]
	# 【必须折行】这行不折的话会把 `Content` 的最小宽度撑过可视区 ——
	# 右栏整片被 ScrollContainer 横向裁掉，账目那几个「元」就没了
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.text(head, 21, UiPalette.INK)
	box.add_child(head)

	var grade := int(p.get("grade", BalanceData.Grade.LOW))
	var grade_label := "匹配 %.0f%% → %s" % [
		float(p.get("match_rate", 0.0)) * 100.0, BalanceData.grade_name(grade)]
	var deltas := "片酬 +%d · 演技 +%d · 知名度 %+d · 风评 %+d · 负面 %+d" % [
		int(p.get("payout", 0)), int(p.get("acting_gain", 0)),
		int(p.get("fame", 0)), int(p.get("rep", 0)), int(p.get("neg", 0))]
	var line := Label.new()
	line.text = grade_label + " ｜ " + deltas
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.text(line, 16, _grade_color(grade))
	box.add_child(line)

	# 「低分龙套没被注意到」这一格必须解释，否则玩家会以为漏结算了
	if bool(p.get("unnoticed", false)):
		_no_margin_note(box, "观众没注意到这个龙套 —— 低分但没人在骂你，一切照旧。")

	var headline := String(p.get("headline", ""))
	if not headline.is_empty():
		_no_margin_note(box, "头条：" + headline)


func _grade_color(grade: int) -> Color:
	match grade:
		BalanceData.Grade.HIGH:
			return MONEY_GOOD
		BalanceData.Grade.NORMAL:
			return UiPalette.PAGE_INK_SOFT
	return MONEY_BAD


## 收支流水。**顺序和 `WeekCycle.settle()` 一致** —— 玩家看到的账要和结算顺序对得上，
## 否则「明明赚了钱却交不起房租」这种事没法直觉理解。
func _build_ledger() -> void:
	_section("这一周的账")
	var payout := int(report.get("payout", 0))
	_ledger_row("片酬", "+%d 元" % payout, MONEY_GOOD if payout > 0 else UiPalette.PAGE_INK_SOFT)
	_ledger_row("房租", "−%d 元" % int(report.get("rent", 0)), MONEY_BAD)

	var paid := int(report.get("ps5_paid", 0))
	if paid > 0:
		_ledger_row("PS5 分期", "−%d 元" % paid, MONEY_BAD)
	elif bool(report.get("ps5_overdue", false)):
		# 【故意不扣钱】逾期只是"这笔没交出去"，扣钱又记逾期等于一罚两遍。
		var penalty := int(report.get("ps5_penalty", 0))
		_ledger_row("PS5 分期", "付不出，这一期没交", MONEY_BAD)
		if penalty > 0:
			_ledger_row("逾期惩罚", "风评 −%d" % penalty, MONEY_BAD)

	var after := _after_state()
	_ledger_row("期末金钱", "%d 元" % int(after.get("money", 0)),
			MONEY_BAD if int(after.get("money", 0)) < 0 else UiPalette.INK)


func _build_deltas() -> void:
	var before: Dictionary = report.get("before", {})
	var after := _after_state()
	if before.is_empty():
		return
	_section("三周走到这里")
	_delta_row("演技", int(before.get("acting", 0)), int(after.get("acting", 0)))
	_delta_row("知名度", int(before.get("fame", 0)), int(after.get("fame", 0)))
	_delta_row("风评", int(before.get("reputation", 0)), int(after.get("reputation", 0)))
	# 负面曝光是隐藏属性（不上状态栏），但周报里要显示 ——
	# 它是「黑红」的唯一来源，不显示就等于让玩家看一个凭空出现的标题
	_delta_row("负面曝光（隐藏）", int(before.get("neg", 0)), int(after.get("neg", 0)))
	var paid := Game.ps5_paid()
	var total := Economy.ps5_total()
	_ledger_row("PS5 已凑", "%d / %d 元" % [paid, total],
			MONEY_GOOD if Game.ps5_paid_off() else UiPalette.PAGE_INK_SOFT)


# ============================================================
# 第二页：结局（同一张纸，换个版面）
# ============================================================
func _build_ending() -> void:
	_on_ending = true
	_clear()
	var ending: Dictionary = report.get("ending", {})
	# 【报头变成"结局 ｜ 名字"】这一页的主角不是报纸，是这三周的下场 ——
	# 名字要在最显眼的位置（原来那版也是这么排的）。
	_edition.text = "《有瓜有戏》号外"
	_title.text = "结局 ｜ " + String(ending.get("name", "?"))
	_day_label.text = "第 %d 天 · 本局终" % GameState.TOTAL_DAYS
	_build_face()

	var cond := Label.new()
	cond.text = String(ending.get("condition", ""))
	cond.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.text(cond, 20, UiPalette.PAGE_INK_SOFT)
	_headline_box.add_child(cond)

	_face_caption.text = "最后一张脸"
	var text := Label.new()
	text.text = String(ending.get("text", ""))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.text(text, 24, UiPalette.INK)
	_content.add_child(text)

	# 【占位文案要让开发者和玩家都看得见】「先做 3 个结局」是文案的工作量，
	# 判定六条都生效了。不标出来的话，读到一段「【文案待补】」会以为是 bug。
	if not bool(ending.get("implemented", false)):
		_note("这个结局的判定已经生效，但文案还是占位 —— 狗牙补完之后这里会换成正文。")

	_section("这一局的账")
	_ledger_row("累计投递", "%d 次（成功 %d）" % [
			Game.state.submissions_total, Game.state.successes_total], UiPalette.INK)
	_ledger_row("龙套档成功", "%d 次" % Game.state.count_success_by_tier(RoleRequirement.Tier.EXTRA),
			UiPalette.INK)
	_ledger_row("演过的烂片", "%d 部" % Game.state.count_bad_plays(), UiPalette.INK)
	_ledger_row("期末金钱", "%d 元" % Game.money(),
			MONEY_BAD if Game.money() < 0 else UiPalette.INK)
	_ledger_row("演技", "%d" % Game.acting(), UiPalette.INK)

	_foot_hint.text = "这一局到此为止。"
	_next_button.text = "再来一局"


func _on_next_pressed() -> void:
	var ending: Dictionary = report.get("ending", {})
	if not _on_ending and not ending.is_empty():
		_build_ending()
		return
	if _on_ending:
		# 先让调用方把本页清掉，再开新局 ——
		# 反过来的话，新局会先触发 state_reset、把我们这个正在发信号的节点一起清掉
		dismissed.emit()
		Game.new_game()
		return
	dismissed.emit()


# ============================================================
# 小工具
# ============================================================
func _after_state() -> Dictionary:
	var after: Dictionary = report.get("after", {})
	if not after.is_empty():
		return after
	# 重开看结局时读的是**存档版周报**，里面没有 before/after 快照 ——
	# 直接读当前状态，数字仍然是对的（那一局已经结束，状态不会再变）
	return {"money": Game.money(), "acting": Game.acting(),
			"fame": Game.fame(), "reputation": Game.reputation(),
			"neg": Game.state.negative_exposure}


func _clear() -> void:
	for child in _content.get_children():
		child.queue_free()
	for child in _headline_box.get_children():
		child.queue_free()


## 报纸上的小标题 —— 深色横条压纸色字，正是模板里那种"栏目条"。
func _section(title: String) -> void:
	var bar := PanelContainer.new()
	var sb := UiPalette.panel(UiPalette.PAGE_INK, 2)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	bar.add_theme_stylebox_override("panel", sb)
	_content.add_child(bar)

	var l := Label.new()
	l.text = title
	UiPalette.text(l, 16, UiPalette.PAPER)
	bar.add_child(l)


func _note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.text(l, 16, UiPalette.PAGE_INK_FAINT)
	_content.add_child(l)


func _no_margin_note(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.text(l, 15, UiPalette.PAGE_INK_SOFT)
	parent.add_child(l)


func _ledger_row(key: String, value: String, value_color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_content.add_child(row)

	var k := Label.new()
	k.text = key
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiPalette.text(k, 18, UiPalette.PAGE_INK_SOFT)
	row.add_child(k)

	var v := Label.new()
	v.text = value
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiPalette.text(v, 20, value_color)
	row.add_child(v)


func _delta_row(key: String, from_value: int, to_value: int) -> void:
	var delta := to_value - from_value
	var color := UiPalette.PAGE_INK_FAINT
	if delta > 0:
		color = MONEY_GOOD
	elif delta < 0:
		color = MONEY_BAD
	_ledger_row(key, "%d → %d（%+d）" % [from_value, to_value, delta], color)


func _apply_styles() -> void:
	# 纸面：米白底 + 深墨描边 + 几乎不收角（报纸是方的）
	get_node("Center/Paper").add_theme_stylebox_override("panel",
			UiPalette.panel(UiPalette.PAPER, 2, 3, UiPalette.INK))
	UiPalette.text(_title, 46, UiPalette.INK)
	UiPalette.text(_edition, 17, UiPalette.PAGE_INK_SOFT)
	UiPalette.text(_day_label, 17, UiPalette.PAGE_INK_SOFT)
	UiPalette.text(_face_caption, 22, UiPalette.INK)
	UiPalette.text(_face_note, 16, UiPalette.PAGE_INK_SOFT)
	UiPalette.text(_foot_hint, 16, UiPalette.PAGE_INK_SOFT)

	# 表情那一格：浅纸底 + 细线框，像报纸上留出来的一块图版
	_face_frame.add_theme_stylebox_override("panel",
			UiPalette.panel(UiPalette.PAPER_SOFT, 2, 1, UiPalette.PAPER_LINE))

	# 按钮压在纸上 → 反过来用墨色底 + 纸色字
	_next_button.focus_mode = Control.FOCUS_NONE
	_next_button.add_theme_font_size_override("font_size", 24)
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		_next_button.add_theme_color_override(key, UiPalette.PAPER)
	_next_button.add_theme_stylebox_override("normal",
			UiPalette.button(UiPalette.INK, UiPalette.INK, 2, 6, 0, 24))
	_next_button.add_theme_stylebox_override("hover",
			UiPalette.button(UiPalette.PAGE_INK, UiPalette.INK, 2, 6, 0, 24))
	_next_button.add_theme_stylebox_override("pressed",
			UiPalette.button(UiPalette.PAGE_INK_SOFT, UiPalette.INK, 2, 6, 0, 24))

	var bar: VScrollBar = _scroll.get_v_scroll_bar()
	bar.custom_minimum_size = Vector2(10, 0)
	bar.add_theme_stylebox_override("scroll",
			UiPalette.button(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0, 0))
	bar.add_theme_stylebox_override("grabber", UiPalette.rounded(UiPalette.PAPER_LINE, 5))
	bar.add_theme_stylebox_override("grabber_highlight",
			UiPalette.rounded(UiPalette.PAGE_INK_SOFT, 5))
