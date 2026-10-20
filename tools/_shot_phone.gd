extends SceneTree
## 临时截图（跑完就删）：手机屏顶栏新皮肤
##
##   Godot_v4.6.3-stable_mono_win64_console.exe --path <项目> --script res://tools/_shot_phone.gd
##   （不能加 --headless：headless 的渲染驱动是 dummy，截出来是全黑）
##
## 出图：tools/_shot_phone.png、_shot_phone_wechat.png

const PHONE := "res://scenes/main/phone_screen.tscn"
const WECHAT := "res://scenes/apps/wechat.tscn"
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

	var app = load(PHONE).instantiate()
	vp.add_child(app)
	await _wait(0.8)
	_save(vp, "res://tools/_shot_phone.png")

	# 开一个 App：返回按钮这时才该亮出来
	app.enable_back()
	app.open_app(WECHAT)
	await _wait(1.4)
	_save(vp, "res://tools/_shot_phone_wechat.png")
	quit(0)


func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await process_frame
		t += 1.0 / 60.0


func _save(vp: SubViewport, path: String) -> void:
	var img := vp.get_texture().get_image()
	print("截图 %s（err %d）" % [path, img.save_png(path)])
