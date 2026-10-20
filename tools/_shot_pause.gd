extends SceneTree
## 临时截图（跑完就删）：桌面左上角菜单键 / 游戏内菜单 / 确认框
##
##   Godot_v4.6.3-stable_mono_win64_console.exe --path <项目> --script res://tools/_shot_pause.gd
##   （不能加 --headless：headless 的渲染驱动是 dummy，截出来是全黑）
##
## 出图：tools/_shot_pause_desk.png、_shot_pause_menu.png、_shot_pause_confirm.png

const MAIN := "res://scenes/main_scene.tscn"
const SHOT_SIZE := Vector2i(1920, 1080)


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var game := root.get_node_or_null("/root/Game")
	if game != null:
		if game.get("state") == null:
			game.call("new_game")
		game.get("state").intro_done = true

	var vp := SubViewport.new()
	vp.size = SHOT_SIZE
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var main = load(MAIN).instantiate()
	vp.add_child(main)
	await _wait(0.7)

	var desk: Node = main.get_node("DeskScreen")
	_save(vp, "res://tools/_shot_pause_desk.png")

	# 悬停态：直接把 normal 换成 hover 那张（鼠标事件不好模拟）
	var menu_btn: TextureButton = desk.get_node("MenuButton")
	var normal_tex := menu_btn.texture_normal
	menu_btn.texture_normal = menu_btn.texture_hover
	await _wait(0.15)
	_save(vp, "res://tools/_shot_pause_hover.png")
	menu_btn.texture_normal = normal_tex

	desk.call("_open_pause_menu")
	await _wait(0.5)
	_save(vp, "res://tools/_shot_pause_menu.png")

	var menu: Node = desk.get("_pause_menu")
	menu.call("_on_restart_week")
	await _wait(0.4)
	_save(vp, "res://tools/_shot_pause_confirm.png")

	menu.call("_close_dialog")
	menu.call("_on_back_to_menu")
	await _wait(0.4)
	_save(vp, "res://tools/_shot_pause_back.png")
	quit(0)


func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await process_frame
		t += 1.0 / 60.0


func _save(vp: SubViewport, path: String) -> void:
	var img := vp.get_texture().get_image()
	print("截图 %s（err %d）" % [path, img.save_png(path)])
