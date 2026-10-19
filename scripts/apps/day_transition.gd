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


## 渐隐到黑。**不 await** —— 调用方紧接着就要跑 `Game.end_day()`。
func cover(duration := 0.3) -> void:
	if _running:
		return
	_running = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_label.text = ""
	_label.modulate.a = 1.0
	_dim.color = Color(0, 0, 0, 0.6)
	var tw := create_tween()
	tw.tween_property(_dim, "color:a", 1.0, duration)


## 黑幕里打字「第 X 天」，停一拍，再淡出。异步跑完自己收尾。
func announce(day: int) -> void:
	visible = true
	_label.modulate.a = 1.0
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
	await tw.finished
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_running = false
