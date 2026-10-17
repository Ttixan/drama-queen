extends SceneTree
## 临时截图（跑完就删）：把手机壳里的录像机拍一张，用来肉眼过一遍布局。
##
##   godot --path <项目> --script res://tools/_shot.gd
##   （不能加 --headless：headless 的渲染驱动是 dummy，截出来是全黑）
##
## 出图：res://tools/_shot_recorder.png

const PHONE := "res://scenes/main/phone_screen.tscn"
const RECORDER := "res://scenes/minigame/recorder.tscn"
const OUT := "res://tools/_shot_recorder.png"


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var phone = load(PHONE).instantiate()
	root.add_child(phone)
	await process_frame
	phone.open_app(RECORDER)
	# 多等几帧：布局收敛 + 卡片是代码建的，还要走出场动画
	for i in 12:
		await process_frame
	var img := root.get_texture().get_image()
	var err := img.save_png(OUT)
	print("")
	print("截图 %s（err %d）" % [OUT, err])
	print("窗口 = ", root.size, "  右栏 = ", phone.get_node(
			"Page/BodyWrap/Body/ContentPanel/ContentMargin/ContentHost").size)
	quit(0)
