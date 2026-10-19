extends Control
## 通用 AVG 对话框 —— 一次一句，点击推进
##
## 【它只负责线性台词】选项、分支、数值结算都不在这里。随机事件将来要复用，
## 也应当是「事件先用它播完开场白，再交回事件自己的二选一界面」——
## 把选择塞进对话框，会让两套交互互相抢点击。
##
## 【用法】
##   var dlg := DIALOGUE_SCENE.instantiate()
##   add_child(dlg)
##   dlg.finished.connect(_on_done)
##   dlg.play_lines([{"speaker": "旁白", "text": "……"}])
##
## 【为什么整屏都能点】手机上没有「下一句」按钮，玩家会习惯性地点文字/空白。
## 根节点铺满全屏并吃掉点击，只有 `advance()` 一处推进 ——
## 这样「点哪里」不会变成三种不同的行为。
##
## 【打字机为什么用 Tween】不用 `_process` 每帧累加：项目里所有动效都走 Tween，
## 停下来的时候是真的停，不会留一个每帧跑的脚本。

signal finished

const FONT_CN := preload("res://assets/fonts/main_font.tres")

## 每秒吐几个字。30 左右是「能读、但不催」的速度；
## 玩家不耐烦时点一下就会补全，不会真的等。
const CHARS_PER_SEC := 30.0

@onready var _box: PanelContainer = $Box
@onready var _speaker_tag: PanelContainer = $SpeakerTag
@onready var _speaker: Label = $SpeakerTag/Speaker
@onready var _text: Label = $Box/Margin/VBox/Text
@onready var _indicator: Label = $Indicator

var _lines: Array[Dictionary] = []
var _index := -1
var _typing := false
var _typing_tween: Tween
var _blink_tween: Tween


func _ready() -> void:
	_apply_styles()
	visible = false


# ============================================================
# 对外接口
# ============================================================
## 播一段台词。每项 `{speaker: String, text: String}`；speaker 为空则不显示名字牌。
func play_lines(lines: Array[Dictionary]) -> void:
	_kill_tweens()
	_lines = lines
	_index = -1
	visible = true
	_next()


## 玩家点了一下（点击 / 回车 / 安卓返回都走这里）
func advance() -> void:
	if not visible:
		return
	# 正在打字：第一次点只补全，不跳到下一句 ——
	# 否则手快的玩家会整段跳过，看到的只有每句的最后几个字
	if _typing:
		_finish_typing()
		return
	_next()


## 测试与调试用：这段台词一共几句、现在停在第几句
func line_count() -> int:
	return _lines.size()


func current_index() -> int:
	return _index


func is_typing() -> bool:
	return _typing


# ============================================================
# 逐句推进
# ============================================================
func _next() -> void:
	_index += 1
	if _index >= _lines.size():
		_typing = false
		_indicator.visible = false
		_kill_blink()
		finished.emit()
		return

	var line: Dictionary = _lines[_index]
	var who := String(line.get("speaker", "")).strip_edges()
	_speaker_tag.visible = not who.is_empty()
	_speaker.text = who
	_text.text = String(line.get("text", ""))
	_text.visible_characters = 0
	_typing = true
	_indicator.visible = false
	_kill_blink()

	var n := _text.text.length()
	if n <= 0:
		_finish_typing()
		return
	_typing_tween = create_tween()
	_typing_tween.tween_method(_set_visible_chars, 0.0, float(n), float(n) / CHARS_PER_SEC)
	_typing_tween.finished.connect(_on_typed)


func _set_visible_chars(v: float) -> void:
	_text.visible_characters = int(v)


func _on_typed() -> void:
	_typing_tween = null
	_finish_typing()


func _finish_typing() -> void:
	if _typing_tween != null and _typing_tween.is_valid():
		_typing_tween.kill()
	_typing_tween = null
	_typing = false
	_text.visible_characters = -1
	_indicator.visible = true
	_start_blink()


func _start_blink() -> void:
	_kill_blink()
	_indicator.modulate.a = 1.0
	_blink_tween = create_tween().set_loops()
	_blink_tween.tween_property(_indicator, "modulate:a", 0.15, 0.55)
	_blink_tween.tween_property(_indicator, "modulate:a", 1.0, 0.55)


func _kill_blink() -> void:
	if _blink_tween != null and _blink_tween.is_valid():
		_blink_tween.kill()
	_blink_tween = null


func _kill_tweens() -> void:
	if _typing_tween != null and _typing_tween.is_valid():
		_typing_tween.kill()
	_typing_tween = null
	_kill_blink()


# ============================================================
# 输入
# ============================================================
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		advance()
		accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		advance()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		advance()
		get_viewport().set_input_as_handled()


# ============================================================
# 样式（纸面 + 墨字，与台历 / 笔记本同一套）
# ============================================================
func _apply_styles() -> void:
	var box_style := UiPalette.panel(UiPalette.PAPER, 6, 3, UiPalette.INK)
	box_style.shadow_color = Color(0, 0, 0, 0.55)
	box_style.shadow_size = 12
	box_style.shadow_offset = Vector2(0, 6)
	_box.add_theme_stylebox_override("panel", box_style)

	var tag_style := UiPalette.panel(UiPalette.ACCENT, 6, 2, UiPalette.INK)
	tag_style.content_margin_left = 16
	tag_style.content_margin_right = 16
	tag_style.content_margin_top = 6
	tag_style.content_margin_bottom = 6
	_speaker_tag.add_theme_stylebox_override("panel", tag_style)

	_speaker.add_theme_font_override("font", FONT_CN)
	UiPalette.text(_speaker, 24, UiPalette.INK)

	_text.add_theme_font_override("font", FONT_CN)
	UiPalette.text(_text, 30, UiPalette.INK)
	_text.add_theme_constant_override("line_spacing", 12)

	_indicator.add_theme_font_override("font", FONT_CN)
	UiPalette.text(_indicator, 26, UiPalette.INK)
	_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
