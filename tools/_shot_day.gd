extends SceneTree
## 临时截图（跑完就删）：过一天的过渡 —— 全黑 / 黑幕打字 / 淡出回桌面
##
##   Godot_v4.6.3-stable_mono_win64_console.exe --path <项目> --script res://tools/_shot_day.gd
##   （不能加 --headless：headless 的渲染驱动是 dummy，截出来是全黑）
##
## 出图：tools/_shot_day_black.png、_shot_day_text.png、_shot_day_after.png

const MAIN := "res://scenes/main_scene.tscn"
const SHOT_SIZE := Vector2i(1920, 1080)


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var game := root.get_node_or_null("/root/Game")
	if game != null:
		if game.get("state") == null:
			game.call("new_game")
		# 别让开场报纸挡住这一屏
		game.get("state").intro_done = true

	var vp := SubViewport.new()
	vp.size = SHOT_SIZE
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var main = load(MAIN).instantiate()
	vp.add_child(main)
	await _wait(0.5)

	var layer: Node = main.get_node_or_null("DayTransition")
	if layer == null:
		push_error("[Shot] 找不到 DayTransition")
		quit(1)
		return

	layer.call("cover")
	await _wait(0.5)
	_save(vp, "res://tools/_shot_day_black.png")

	layer.call("announce", 2)
	await _wait(1.0)
	_save(vp, "res://tools/_shot_day_text.png")

	await _wait(1.1)
	_save(vp, "res://tools/_shot_day_after.png")
	quit(0)


func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await process_frame
		t += 1.0 / 60.0


func _save(vp: SubViewport, path: String) -> void:
	var img := vp.get_texture().get_image()
	print("截图 %s（err %d）" % [path, img.save_png(path)])
