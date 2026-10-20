extends SceneTree
## 临时截图（跑完就删）：录像机整屏 —— 顶栏新皮肤 + 返回键悬停态
##
##   Godot_v4.6.3-stable_mono_win64_console.exe --path <项目> --script res://tools/_shot_recorder.gd
##   （不能加 --headless：headless 的渲染驱动是 dummy，截出来是全黑）
##
## 出图：tools/_shot_recorder.png、_shot_recorder_hover.png

const RECORDER := "res://scenes/minigame/recorder.tscn"
const SHOT_SIZE := Vector2i(1920, 1080)


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var game := root.get_node_or_null("/root/Game")
	if game != null and game.get("state") == null:
		game.call("new_game")

	var vp := SubViewport.new()
	vp.size = SHOT_SIZE
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var app = load(RECORDER).instantiate()
	vp.add_child(app)
	await _wait(0.8)
	_save(vp, "res://tools/_shot_recorder.png")

	# 给第一帧挑一双眼，顶栏「本帧得分」才有东西可算
	app._on_card_toggled(true, PartData.Slot.EYES, "eyes_00")
	await _wait(0.3)
	_save(vp, "res://tools/_shot_recorder_score.png")

	# 返回键在「子页面」里才显示：手动亮出来 + 切成 hover 贴图
	var back: TextureButton = app.get_node("Page/TopBar/BackButton")
	back.visible = true
	back.texture_normal = back.texture_hover
	await _wait(0.2)
	_save(vp, "res://tools/_shot_recorder_hover.png")
	quit(0)


func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await process_frame
		t += 1.0 / 60.0


func _save(vp: SubViewport, path: String) -> void:
	var img := vp.get_texture().get_image()
	print("截图 %s（err %d）" % [path, img.save_png(path)])
