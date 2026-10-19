extends Control
## 主场景壳：桌子 + 开场盖层
##
## 【为什么单开一层】桌子（`desk_screen`）不该知道「还有一段开场」。它现在被
## 五条验证链直接实例化；把「未看开场就弹」写进桌子，会让每个测试都多一个全屏节点。
## 这一层只做一件事：**看状态决定要不要把开场盖在桌子上面**。
##
## 【什么时候出现】
##   · 新局：`Game.new_game()` 造的 GameState 里 `intro_done = false`
##   · 老存档：`GameState.from_save_dict` 把缺失字段当 true —— 老玩家不重看
##   · 重开一局：`new_game()` → `state_reset` → 这里再接一次
##
## 【headless 下不挂】开场是纯界面；headless 冒烟与 `--script` 测试不该被它挡住。
## 开场自己的验证链（`tools/test_intro.gd`）直接实例化 `intro.tscn`，不依赖这里。

const INTRO_SCENE := "res://scenes/intro/intro.tscn"

var _intro: Node


func _ready() -> void:
	EventBus.state_reset.connect(_on_state_reset)
	_maybe_open_intro()


func _maybe_open_intro() -> void:
	if OS.has_feature("headless"):
		return
	if _intro != null and is_instance_valid(_intro):
		return
	if Game.state == null or Game.state.intro_done:
		return

	var packed := load(INTRO_SCENE) as PackedScene
	if packed == null:
		push_error("[Main] 读不到开场场景 " + INTRO_SCENE)
		return

	_intro = packed.instantiate()
	add_child(_intro)
	_intro.finished.connect(_on_intro_finished)


func _on_intro_finished() -> void:
	_intro = null


func _on_state_reset() -> void:
	_maybe_open_intro()
