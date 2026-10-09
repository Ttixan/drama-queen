extends SceneTree
## 生成 32 张**占位**部件图 —— 目的是让录像机今天就能跑起来，不必等扉师。
##
##   godot --headless --path <项目> --script res://tools/gen_placeholder_art.gd
##   （跑完要再跑一次 --import，Godot 才会把新 PNG 登记成资源）
##
## 【图片规格 —— 这才是要「冻结」的接口，不是数量】
##   尺寸  512 × 512，PNG，透明背景
##   锚点  所有部件**共用同一张画布**：人脸中心 = 画布中心。
##         于是四个部件直接按同一坐标叠加就对齐了，不需要各自的偏移表。
##   命名  assets/parts/{slot}_{tier:02d}.png
##
## 【占位图的颜色是有意义的】色相 = 该部件的主情绪（喜黄 / 怒红 / 哀蓝 / 惊紫 / 魅粉 / 尬灰），
## 中性件用深灰。这样开发期一眼就能看出向量对不对，正片换成正常美术即可（颜色无意义）。

const Catalog := preload("res://tools/part_catalog.gd")

const OUT_DIR := "res://assets/parts"
const CANVAS := 512

const EMO_COLORS := {
	"joy": Color("ffd447"),
	"anger": Color("e5484d"),
	"sorrow": Color("4a7fe5"),
	"shock": Color("a855f7"),
	"charm": Color("ff7ab6"),
	"awkward": Color("8b8b8b"),
}
const NEUTRAL := Color("2b2b2b")
const TRANSPARENT := Color(0, 0, 0, 0)

# 五官锚点（画布 512×512，人脸中心 256,256）
const EYE_L := Vector2(176, 208)
const EYE_R := Vector2(336, 208)
const BROW_Y := 140.0
const MOUTH := Vector2(256, 352)
const EXTRA := Vector2(412, 124)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var n := 0
	for p: Dictionary in Catalog.PARTS:
		var slot: int = p["slot"]
		var tier: int = p["tier"]
		var col := _emotion_color(p["emo"])

		var img := Image.create(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
		img.fill(TRANSPARENT)

		match slot:
			Catalog.EYES:
				_draw_eyes(img, tier, col)
			Catalog.BROWS:
				_draw_brows(img, tier, col)
			Catalog.MOUTH:
				_draw_mouth(img, tier, col)
			Catalog.EXTRA:
				_draw_extra(img, tier, col)

		var path := "%s/%s.png" % [OUT_DIR, Catalog.part_id(slot, tier)]
		var err := img.save_png(path)
		if err != OK:
			push_error("保存失败 %s (err %d)" % [path, err])
		else:
			n += 1

	print("")
	print("生成 %d 张占位部件图 → %s" % [n, OUT_DIR])
	print("规格：%d×%d 透明 PNG，共用画布，人脸中心 = 画布中心" % [CANVAS, CANVAS])
	print("下一步：godot --headless --path <项目> --import")
	quit(0)


# ============================================================
# 造型 —— tier 只影响**几何变化量**，颜色才表达情绪
# ============================================================
func _draw_eyes(img: Image, tier: int, col: Color) -> void:
	var rx := 46.0 + float(tier % 4) * 6.0
	var ry := 26.0 + float(tier % 5) * 8.0
	_ellipse(img, EYE_L.x, EYE_L.y, rx, ry, col)
	_ellipse(img, EYE_R.x, EYE_R.y, rx, ry, col)


func _draw_brows(img: Image, tier: int, col: Color) -> void:
	# 角度随 tier 从「八字」扫到「上挑」，中间档接近水平
	var ang := (float(tier) - 3.5) * 0.12
	var half := 48.0
	var dx := cos(ang) * half
	var dy := sin(ang) * half
	# 左眉向右下、右眉向右上 —— 镜像后才是对称的
	_line(img, EYE_L.x - dx, BROW_Y + dy, EYE_L.x + dx, BROW_Y - dy, 15.0, col)
	_line(img, EYE_R.x - dx, BROW_Y - dy, EYE_R.x + dx, BROW_Y + dy, 15.0, col)


func _draw_mouth(img: Image, tier: int, col: Color) -> void:
	var rx := 58.0 + float(tier % 5) * 9.0
	var ry := 16.0 + float(tier % 6) * 11.0
	_ellipse(img, MOUTH.x, MOUTH.y, rx, ry, col)


func _draw_extra(img: Image, tier: int, col: Color) -> void:
	var r := 16.0 + float(tier) * 4.0
	_ellipse(img, EXTRA.x, EXTRA.y, r, r, col)
	# 挖个洞，和实心圆区分开，便于一眼认出是「其他」槽
	_ellipse(img, EXTRA.x, EXTRA.y, r * 0.45, r * 0.45, TRANSPARENT)


# ============================================================
# 只遍历形状的包围盒，不整图扫描 —— 512² 全扫 ×32 张太慢
# ============================================================
func _ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, col: Color) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	var x0 := maxi(0, int(cx - rx) - 1)
	var x1 := mini(CANVAS - 1, int(cx + rx) + 1)
	var y0 := maxi(0, int(cy - ry) - 1)
	var y1 := mini(CANVAS - 1, int(cy + ry) + 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var nx := (float(x) - cx) / rx
			var ny := (float(y) - cy) / ry
			if nx * nx + ny * ny <= 1.0:
				img.set_pixel(x, y, col)


func _line(img: Image, ax: float, ay: float, bx: float, by: float,
		w: float, col: Color) -> void:
	var hw := w * 0.5
	var x0 := maxi(0, int(minf(ax, bx) - hw) - 1)
	var x1 := mini(CANVAS - 1, int(maxf(ax, bx) + hw) + 1)
	var y0 := maxi(0, int(minf(ay, by) - hw) - 1)
	var y1 := mini(CANVAS - 1, int(maxf(ay, by) + hw) + 1)
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


## 取主情绪色。全零（中性件）用深灰。
func _emotion_color(emo: Dictionary) -> Color:
	var best := ""
	var best_val := 0.0
	for k: String in emo:
		var v: float = emo[k]
		if v > best_val:
			best_val = v
			best = k
	return EMO_COLORS.get(best, NEUTRAL)
