extends SceneTree
## 临时截图（跑完就删）：微信界面的浅色版 —— 默认页 / 聊天 / 剧本页。
##
##   Godot_v4.6.3-stable_mono_win64_console.exe --path <项目> --script res://tools/_shot_wechat.gd
##   （不能加 --headless：headless 的渲染驱动是 dummy，截出来是全黑）
##
## 出图：tools/_shot_wechat.png、_shot_wechat_chat.png、_shot_wechat_script.png

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

	# 新局里一个 HR 都没解锁，联系人列表是空的、也就没有气泡可拍。
	# 先把第一家解锁掉，再重建界面。
	var app = load(WECHAT).instantiate()
	vp.add_child(app)
	var companies: Array = app._companies
	if companies.size() > 0 and game != null:
		game.call("unlock_hr", String(companies[0].code))
	app.queue_free()
	await _wait(0.2)

	app = load(WECHAT).instantiate()
	vp.add_child(app)
	await _wait(0.6)
	_save(vp, "res://tools/_shot_wechat.png")

	# 挑一个联系人，把气泡铺出来
	var code: String = app._first_contact_code()
	print("第一个联系人 = ", code)
	if code != "":
		app._select_company(code)
		await _wait(1.6)
		_save(vp, "res://tools/_shot_wechat_chat.png")

		# 让这位 HR 发一份剧本，翻开那一页看贴图对不对
		if game != null and app._current != null:
			game.call("request_script", app._current, 0)
			await _wait(0.4)
			app._open_script()
			await _wait(0.5)
			_save(vp, "res://tools/_shot_wechat_script.png")
	quit(0)


func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await process_frame
		t += 1.0 / 60.0


func _save(vp: SubViewport, path: String) -> void:
	var img := vp.get_texture().get_image()
	print("截图 %s（err %d）" % [path, img.save_png(path)])
