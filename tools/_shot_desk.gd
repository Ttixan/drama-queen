extends SceneTree
## 临时截图（跑完就删）：桌面 + 右上角便利贴状态栏。
##
##   Godot_v4.6.3-stable_mono_win64_console.exe --path <项目> --script res://tools/_shot_desk.gd
##   （不能加 --headless：headless 的渲染驱动是 dummy，截出来是全黑）
##
## 出图：tools/_shot_desk.png

const DESK := "res://scenes/main/desk_screen.tscn"
const SHOT_SIZE := Vector2i(1920, 1080)


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	# `--script` 模式下 autoload 的标识符编译期不可见，按路径取；
	# 且 Game 的 _ready 排在 _initialize 之后，得手动保证 state 已就位。
	var game := root.get_node_or_null("/root/Game")
	if game != null and game.get("state") == null:
		game.call("new_game")

	var vp := SubViewport.new()
	vp.size = SHOT_SIZE
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var desk = load(DESK).instantiate()
	vp.add_child(desk)
	await _wait(0.6)
	_save(vp, "res://tools/_shot_desk.png")

	# 动一下状态，确认贴纸真的跟着信号刷新，而不是只在 _ready 里读了一次
	if game != null:
		game.call("add_money", 88)
		game.call("add_fame", 3)
		game.call("end_day")
	await _wait(0.4)
	_save(vp, "res://tools/_shot_desk_after.png")

	# 把手机的悬浮提示点亮，确认它不再压到右上角那张便利贴
	var phone: Node = desk.get_node_or_null("Hotspots/HotspotPhone")
	var phone_hint: Label = phone.get("_hint_label") if phone != null else null
	if phone_hint != null:
		phone_hint.visible = true
		if phone.get("active_texture") != null:
			desk.get_node("Bg").texture = phone.get("active_texture")
		await _wait(0.3)
		_save(vp, "res://tools/_shot_desk_hint.png")
	quit(0)


func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await process_frame
		t += 1.0 / 60.0


func _save(vp: SubViewport, path: String) -> void:
	var img := vp.get_texture().get_image()
	print("截图 %s（err %d）" % [path, img.save_png(path)])
