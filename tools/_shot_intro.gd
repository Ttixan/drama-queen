extends SceneTree
## 临时截图（跑完就删）：开场 A1 报纸 / A3 演员登记表，看相框剧照摆在上面是什么样。
##
##   Godot_v4.6.3-stable_mono_win64_console.exe --path <项目> --script res://tools/_shot_intro.gd
##   （不能加 --headless：headless 的渲染驱动是 dummy，截出来是全黑）
##
## 【为什么走 SubViewport】直接拍 `root.get_texture()` 只能拿到窗口大小 ——
## 显示器装不下 1920×1080 的窗口时会被裁到 1088×612，细节全糊。SubViewport 里
## 按 1920×1080 渲染再取图，才看得清相框边缘。
##
## 出图：res://tools/_shot_intro_a1.png、res://tools/_shot_intro_a3.png

const INTRO := "res://scenes/intro/intro.tscn"
const SHOT_SIZE := Vector2i(1920, 1080)


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = SHOT_SIZE
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var intro = load(INTRO).instantiate()
	vp.add_child(intro)

	# 淡入 0.55s + 照片最晚 0.7s 出现 + 0.45s 淡入，留到 1.9s 再拍
	await _wait(1.9)
	_save(vp, "res://tools/_shot_intro_a1.png")

	# 跳过「关广告 → 独白」，直接把 A3 摆出来
	intro._paper_layer.visible = false
	intro._name_layer.visible = true
	await _wait(0.9)
	_save(vp, "res://tools/_shot_intro_a3.png")
	quit(0)


func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await process_frame
		t += 1.0 / 60.0


func _save(vp: SubViewport, path: String) -> void:
	var img := vp.get_texture().get_image()
	print("截图 %s（%s，err %d）" % [path, img.get_size(), img.save_png(path)])
