extends Control
## 主场景壳：桌子 + 开场盖层 + 新手引导盖层
##
## 【为什么单开一层】桌子（`desk_screen`）不该知道「还有一段开场」。它现在被
## 五条验证链直接实例化；把「未看开场就弹」写进桌子，会让每个测试都多一个全屏节点。
## 这一层只做一件事：**看状态决定要不要把开场 / 引导盖在桌子上面**。
##
## 【什么时候出现】
##   · 开场：新局 `intro_done = false`；老存档默认 true，不重看
##   · 引导：开场看完（或没有开场）且 `tutorial_step` 在 0 .. DONE-1 之间
##   · 重开一局：`new_game()` → `state_reset` → 这里再接一次
##
## 【headless 下都不挂】两者都是纯界面；headless 冒烟与 `--script` 测试不该被它们挡住。
## 各自的验证链（`tools/test_intro.gd` / `tools/test_tutorial.gd`）直接实例化场景，不依赖这里。

const INTRO_SCENE := "res://scenes/intro/intro.tscn"
const TUTORIAL_SCENE := "res://scenes/ui/tutorial_layer.tscn"

var _intro: Node
var _tutorial: Node


func _ready() -> void:
	EventBus.state_reset.connect(_on_state_reset)
	_maybe_open_intro()
	_maybe_open_tutorial()


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


## 新手引导：开场看完才轮到它（报纸广告 → 独白取名 → 上手教怎么投第一份简历）
func _maybe_open_tutorial() -> void:
	if OS.has_feature("headless"):
		return
	# 开场还在播：等它 `finished` 再来（见 `_on_intro_finished`）
	if _intro != null and is_instance_valid(_intro):
		return
	if _tutorial != null and is_instance_valid(_tutorial):
		return
	if Game.state == null:
		return
	var step: int = Game.state.tutorial_step
	# -1 = 老存档（字段缺失时的默认值）；DONE 之后也不该再弹
	if step < 0 or step >= TutorialLayer.Step.DONE:
		return

	var packed := load(TUTORIAL_SCENE) as PackedScene
	if packed == null:
		push_error("[Main] 读不到引导场景 " + TUTORIAL_SCENE)
		return

	_tutorial = packed.instantiate()
	add_child(_tutorial)
	_tutorial.finished.connect(_on_tutorial_finished)


func _on_intro_finished() -> void:
	_intro = null
	_maybe_open_tutorial()


func _on_tutorial_finished() -> void:
	_tutorial = null


# ============================================================
# 给 GM 控制台用的开关（`tutorial skip` / `tutorial reset`）
# ============================================================
## 跳过整段新手引导：进度拨到 DONE，并把当前挂着的那层当场收掉
## 【只改存档不够】引导层是**已实例化的节点**，不改它就会一直贴在屏幕上，
## 得等重进主场景才消失 —— 调 GM 的人看到的就是「命令没生效」。
func skip_tutorial() -> void:
	Game.skip_tutorial()
	_close_layer(_tutorial)
	_tutorial = null
	# 兜底：万一这层不是本脚本挂的（测试直接 add_child / 热重载），按类型再扫一遍
	for child in get_children():
		if child is TutorialLayer:
			child.queue_free()


## 把引导倒回第一拍并立刻重新挂上（用来反复验前半段）
func reset_tutorial() -> void:
	if Game.state == null:
		return
	Game.reset_tutorial()
	_close_layer(_tutorial)
	_tutorial = null
	for child in get_children():
		if child is TutorialLayer:
			child.queue_free()
	_maybe_open_tutorial()


func _on_state_reset() -> void:
	# 重开一局时把两位都收掉，再由下面的 `_maybe_*` 按新状态决定要不要重新盖上 ——
	# 不清理的话，旧的开场/引导会留在新局上继续跑（它的进度还是上一局的）
	_close_layer(_intro)
	_intro = null
	_close_layer(_tutorial)
	_tutorial = null
	_maybe_open_intro()
	_maybe_open_tutorial()


func _close_layer(n: Node) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()
