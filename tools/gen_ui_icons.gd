extends SceneTree
## 生成 5 个**页签图标** —— 录像机右栏的「眼 / 嘴 / 眉 / 其他 / 肤色」不再写汉字，改用一个图形。
##
##   godot --headless --path <项目> --script res://tools/gen_ui_icons.gd
##   （跑完要再跑一次 --import，Godot 才会把新 PNG 登记成资源）
##
## 【规格】96 × 96，透明底，图形本身是**纯白**。
##   颜色不画进图里，留给 Button 的 `icon_normal_color / icon_pressed_color` 去上色 ——
##   同一张图在「未选中（灰）」和「选中（黄）」两种状态下都不用重画。
##
## 【为什么不直接拿部件图当图标】部件图是 512 共用画布，五官只占中心一小块，
##   缩到页签尺寸后剩下几个像素，认不出来。这里是**符号化**的简笔：只看形状。

const OUT_DIR := "res://assets/ui/icons"
const SIZE := 96

const WHITE := Color(1, 1, 1, 1)
const CLEAR := Color(0, 0, 0, 0)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var jobs := {
		"tab_eyes": _draw_eyes,
		"tab_mouth": _draw_mouth,
		"tab_brows": _draw_brows,
		"tab_extra": _draw_extra,
		"tab_skin": _draw_skin,
	}
	var n := 0
	for name: String in jobs:
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		img.fill(CLEAR)
		(jobs[name] as Callable).call(img)
		var path := "%s/%s.png" % [OUT_DIR, name]
		var err := img.save_png(path)
		if err != OK:
			push_error("保存失败 %s (err %d)" % [path, err])
		else:
			n += 1

	print("")
	print("生成 %d 个页签图标 → %s" % [n, OUT_DIR])
	print("规格：%d×%d 纯白描形、透明底（颜色由 Button 的 icon_*_color 决定）" % [SIZE, SIZE])
	print("下一步：godot --headless --path <项目> --import")
	quit(0)


# ============================================================
# 造型 —— 四个形状要能互相拉开：圆眼 / 弧嘴 / 斜眉 / 圆环
# ============================================================
func _draw_eyes(img: Image) -> void:
	# 一对横椭圆，各挖一个瞳孔 —— 「眼」一眼可辨
	_ellipse(img, 28.0, 50.0, 20.0, 14.0, WHITE)
	_ellipse(img, 68.0, 50.0, 20.0, 14.0, WHITE)
	_ellipse(img, 28.0, 50.0, 7.0, 7.0, CLEAR)
	_ellipse(img, 68.0, 50.0, 7.0, 7.0, CLEAR)


func _draw_mouth(img: Image) -> void:
	# 椭圆环的**下半段** —— 一条笑弧，和眼/眉都不撞
	_lower_arc(img, 48.0, 44.0, 32.0, 30.0, 9.0, WHITE)


func _draw_brows(img: Image) -> void:
	# 两条向上拱的粗斜线 —— 细长、有倾角，跟圆润的眼/嘴分得开
	_bar(img, 14.0, 58.0, 42.0, 36.0, 10.0, WHITE)
	_bar(img, 54.0, 36.0, 82.0, 58.0, 10.0, WHITE)


func _draw_extra(img: Image) -> void:
	# 空心环 —— 与 tools/gen_placeholder_art.gd 里 extra 槽的画法同源
	_ellipse(img, 48.0, 48.0, 30.0, 30.0, WHITE)
	_ellipse(img, 48.0, 48.0, 19.0, 19.0, CLEAR)


func _draw_skin(img: Image) -> void:
	# 环 + 实心芯 —— 「其他」只有环，肤色多一个芯，两张缩到 38px 也分得开
	_ellipse(img, 48.0, 48.0, 30.0, 30.0, WHITE)
	_ellipse(img, 48.0, 48.0, 24.0, 24.0, CLEAR)
	_ellipse(img, 48.0, 48.0, 15.0, 15.0, WHITE)


# ============================================================
# 只遍历形状的包围盒，不整图扫描
# ============================================================
func _ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, col: Color) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	var x0 := maxi(0, int(cx - rx) - 1)
	var x1 := mini(SIZE - 1, int(cx + rx) + 1)
	var y0 := maxi(0, int(cy - ry) - 1)
	var y1 := mini(SIZE - 1, int(cy + ry) + 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var nx := (float(x) - cx) / rx
			var ny := (float(y) - cy) / ry
			if nx * nx + ny * ny <= 1.0:
				img.set_pixel(x, y, col)


## 椭圆环的下半段：外椭圆实心，内椭圆挖空，再砍掉中线上方
func _lower_arc(img: Image, cx: float, cy: float, rx: float, ry: float,
		thick: float, col: Color) -> void:
	var x0 := maxi(0, int(cx - rx) - 1)
	var x1 := mini(SIZE - 1, int(cx + rx) + 1)
	var y0 := maxi(0, int(cy))
	var y1 := mini(SIZE - 1, int(cy + ry) + 1)
	var irx := maxf(rx - thick, 1.0)
	var iry := maxf(ry - thick, 1.0)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var nx := (float(x) - cx) / rx
			var ny := (float(y) - cy) / ry
			if nx * nx + ny * ny > 1.0:
				continue
			var ix := (float(x) - cx) / irx
			var iy := (float(y) - cy) / iry
			if ix * ix + iy * iy <= 1.0:
				continue
			img.set_pixel(x, y, col)


func _bar(img: Image, ax: float, ay: float, bx: float, by: float,
		w: float, col: Color) -> void:
	var hw := w * 0.5
	var x0 := maxi(0, int(minf(ax, bx) - hw) - 1)
	var x1 := mini(SIZE - 1, int(maxf(ax, bx) + hw) + 1)
	var y0 := maxi(0, int(minf(ay, by) - hw) - 1)
	var y1 := mini(SIZE - 1, int(maxf(ay, by) + hw) + 1)
	var ab := Vector2(bx - ax, by - ay)
	var len_sq := ab.length_squared()
	if len_sq <= 0.0:
		_ellipse(img, ax, ay, hw, hw, col)
		return
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var ap := Vector2(float(x) - ax, float(y) - ay)
			var t := clampf(ap.dot(ab) / len_sq, 0.0, 1.0)
			if (ap - ab * t).length() <= hw:
				img.set_pixel(x, y, col)
