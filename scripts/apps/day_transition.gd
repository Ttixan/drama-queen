extends Control
## 过一天的过渡：渐隐到黑 → 黑幕里打字「第 X 天」→ 渐隐回桌面
##
## 【为什么它不 await 逻辑】`Game.end_day()` 必须是同步调用的：日历页、
## `test_phone_shell` 等一堆调用方按下按钮后立刻断言新状态。过渡只负责**遮挡画面**，
## 不能把「推进一天」变成协程 —— 所以 `cover()` / `announce()` 都只启动自己的 tween，
## 不进调用方的执行流。
##
## 【为什么先压到半黑】逻辑在黑幕 alpha≈0 的那一瞬间就跑完了，界面会先刷新成新一天。
## 直接把 alpha 提到 0.6 再补到 1，那一帧刷新就被压在暗处，看不出「数字先跳了」。
##
## 【挂在 MainScene 最后】在桌子（含日历页、周报浮层）之上，`announce` 淡出之前
## 周报是打不开的视觉 —— 玩家先看到「第 2 天」，再看到新一天的周报。

const INK_PAPER := Color("f4f1e8")
const TYPE_INTERVAL := 0.13
const HOLD := 0.55

@onready var _dim: ColorRect = $Dim
@onready var _label: Label = $DayLabel

## 副标题（「去演戏了，跳过此天」这种）。场景里没有，跟着主标题一起建 ——
## 只有拍戏日那一种情况会用到，写进 .tscn 会让每个场景都多一个空 Label。
var _note: Label
var _running := false


func _ready() -> void:
	add_to_group("day_transition")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style()


func _style() -> void:
	_label.add_theme_font_override("font", UiPalette.TITLE_FONT)
	_label.add_theme_font_size_override("font_size", 96)
	_label.add_theme_color_override("font_color", INK_PAPER)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_note = Label.new()
	_note.name = "DayNote"
	_note.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 压在「第 N 天」下面一行：主标题 96 号居中，副标题从中心往下挪一段
	_note.offset_top = 150.0
	_note.add_theme_font_override("font", UiPalette.FONT_CN)
	_note.add_theme_font_size_override("font_size", 30)
	_note.add_theme_color_override("font_color", Color(INK_PAPER, 0.78))
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_note)


## 渐隐到黑。**不 await** —— 调用方紧接着就要跑 `Game.end_day()`。
func cover(duration := 0.3) -> void:
	if _running:
		# 【上一次没走完就先复位】`announce()` 半路被打断（切场景 / 节点被释放）时
		# `_running` 会一直挂着，黑幕这时是「看不见但全屏 STOP」——
		# 表现就是「界面卡住，只有 ESC 有反应」。这里直接把状态推回可用再重来。
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_running = false
	_running = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_label.text = ""
	_label.modulate.a = 1.0
	_dim.color = Color(0, 0, 0, 0.6)
	var tw := create_tween()
	tw.tween_property(_dim, "color:a", 1.0, duration)


## 黑幕里打字「第 X 天」，停一拍，再淡出。异步跑完自己收尾。
## `note` 是副标题（拍戏日那种「去演戏了，跳过此天」），平时留空。
func announce(day: int, note := "") -> void:
	visible = true
	_label.modulate.a = 1.0
	_note.text = note
	_note.modulate.a = 1.0 if not note.is_empty() else 0.0
	var text := "第 %d 天" % day
	_label.text = ""
	for i in text.length():
		_label.text = text.substr(0, i + 1)
		await get_tree().create_timer(TYPE_INTERVAL).timeout
	await get_tree().create_timer(HOLD).timeout

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_dim, "color:a", 0.0, 0.5)
	tw.tween_property(_label, "modulate:a", 0.0, 0.3)
	tw.tween_property(_note, "modulate:a", 0.0, 0.3)
	await tw.finished
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_running = false
