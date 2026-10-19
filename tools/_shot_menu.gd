extends SceneTree
## 临时截图（跑完就删）：开始界面的四种状态 —— 无存档 / 有存档 / 制作人员 / 重开确认。
##
##   Godot_v4.6.3-stable_mono_win64_console.exe --path <项目> --script res://tools/_shot_menu.gd
##   （不能加 --headless：headless 的渲染驱动是 dummy，截出来是全黑）
##
## 出图：tools/_shot_menu_nosave.png / _save.png / _credits.png / _confirm.png

const MENU := "res://scenes/ui/main_menu.tscn"
const SHOT_SIZE := Vector2i(1920, 1080)


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = SHOT_SIZE
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	# 先摆「没存档」——按钮里「开始游戏」该是黄的
	_set_has_save(false)
	var menu = load(MENU).instantiate()
	vp.add_child(menu)
	await _wait(0.5)
	_save(vp, "res://tools/_shot_menu_nosave.png")

	menu._show_credits()
	await _wait(0.3)
	_save(vp, "res://tools/_shot_menu_credits.png")
	menu._close_dialog()
	menu.queue_free()
	await _wait(0.2)

	# 再摆「有存档」——「继续游戏」变成主按钮，点开始游戏会先问一句
	_set_has_save(true)
	var menu2 = load(MENU).instantiate()
	vp.add_child(menu2)
	await _wait(0.5)
	_save(vp, "res://tools/_shot_menu_save.png")

	menu2._show_confirm()
	await _wait(0.3)
	_save(vp, "res://tools/_shot_menu_confirm.png")
	quit(0)


## `--script` 模式下 autoload 的标识符在编译期不可见（`Game` 会报 Identifier not found），
## 所以这里按节点路径取，别直接写 `Game.loaded_from_save`。
func _set_has_save(value: bool) -> void:
	var game := root.get_node_or_null("/root/Game")
	if game == null:
		push_warning("[Shot] 拿不到 Game autoload，截图里的按钮状态可能与真实不符")
		return
	game.set("loaded_from_save", value)


func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await process_frame
		t += 1.0 / 60.0


func _save(vp: SubViewport, path: String) -> void:
	var img := vp.get_texture().get_image()
	print("截图 %s（err %d）" % [path, img.save_png(path)])
