class_name PhotoCard
extends RefCounted
## 桌上的「剧照」：录像机那套五官合成出来的相框卡片。
##
## 【为什么要抽出来】开场时它们压在报纸角上，开始界面里散在桌面上 ——
## 摆位不同，做法完全一样（淡入 + 极慢的上下浮动）。两处各抄一份的话，
## 以后调浮动幅度就得记着改两遍。
##
## 【尺寸按高度给】四张卡片比例各不相同（木框 480×680、欧式 474×680、
## 拍立得 451×680），按宽定会把欧式框压扁。

## 加一张照片。`spec` = {path, pos, height, angle, delay}
static func add(parent: Node, spec: Dictionary) -> TextureRect:
	var tex := load(spec["path"]) as Texture2D
	if tex == null:
		push_warning("[PhotoCard] 缺剧照 %s —— 先跑合成脚本" % spec["path"])
		return null

	var h: float = spec["height"]
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size = Vector2(h * tex.get_width() / tex.get_height(), h)
	r.position = spec["pos"]
	r.pivot_offset = r.size * 0.5
	r.rotation = deg_to_rad(spec["angle"])
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.modulate.a = 0.0
	parent.add_child(r)

	var fade := r.create_tween()
	fade.tween_property(r, "modulate:a", 1.0, 0.45).set_delay(spec["delay"])

	# 落下之后还会晃一下：幅度压到 4px、周期 2.2s，只当呼吸，不抢正文
	var bob := r.create_tween().set_loops()
	bob.tween_property(r, "position:y", r.position.y - 4.0, 2.2) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(r, "position:y", r.position.y, 2.2) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return r
