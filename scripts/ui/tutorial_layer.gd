class_name TutorialLayer
extends Control
## 新手引导 —— 底部「内心独白」对话框 + 半透明遮罩把该点的东西圈出来
##
## 文案来源：`.document/文案/hr与引导文案策划部分.docx` 的「新手引导（对话框）」。
## 本层只做到「（指引立刻沟通）」这一拍：
##
##   独白「好了......接下来看看先要做什么？」
##     → 圈住桌上的【手机】
##     → 圈住手机屏里的【简历拿来】
##     → 独白「这里是目前还在短剧制造相关的五家公司……」
##     → 圈住列表里的【小登传媒】
##     → 独白「看公司背景……先试试和HR沟通吧！」
##     → 圈住详情页的【立刻沟通】→ 本批引导结束
##
## 【为什么是「挖洞」而不是「蒙一层再画个框」】引导期间**只允许点目标**：
## 洞外铺四块半透明矩形（每块都吃点击），洞内什么都不放 —— 点击直接落到真正的按钮上。
## 这样既不用给四个按钮各加一套「引导专用」逻辑，也不会因为给遮罩开穿透而把别处一起放开。
##
## 【坐标为什么每帧算】「小登传媒」那一行在手机屏里、列表还会滚动 ——
## 写死坐标必然错位，所以每帧拿目标的 `get_global_rect()` 重新摆洞。
##
## 【进度为什么进存档】引导横跨三个界面（桌面 → 手机屏 → Boss），
## 中途退出/读档不该从「点手机」重新来一遍。字段见 `GameState.tutorial_step`。

signal finished

enum Step {
	LINE_INTRO = 0,      ## 独白：好了......接下来看看先要做什么？
	TAP_PHONE = 1,       ## 圈住桌上的手机
	TAP_APP = 2,         ## 圈住手机屏里的「简历拿来」
	LINE_COMPANIES = 3,  ## 独白：这里是目前还在短剧制造相关的五家公司……
	TAP_COMPANY = 4,     ## 圈住列表里的「小登传媒」
	LINE_COMPANY = 5,    ## 独白：看公司背景……先试试和HR沟通吧！
	TAP_CONTACT = 6,     ## 圈住详情页的「立刻沟通」
	DONE = 7,            ## 本批引导结束
}

const DIALOGUE_SCENE := "res://scenes/ui/dialogue_box.tscn"
const BOSS_SCENE := "res://scenes/apps/boss.tscn"
const DIM_COLOR := Color(0, 0, 0, 0.55)
## 洞比目标大一圈：描边贴着按钮边缘会看起来像按钮自己多了一道边
const HOLE_PAD := 10.0
## 第一家：引导指名要聊的就是它（md 里的「小登传媒」，内部代号 A）
const FIRST_COMPANY := "A"

## 独白文案。speaker 留空 —— 内心独白没有名字牌，也不该署名「旁白」
const LINES := {
	Step.LINE_INTRO: "好了......接下来看看先要做什么？",
	Step.LINE_COMPANIES: "这里是目前还在短剧制造相关的五家公司，先问问看它们收不收演员吧！",
	Step.LINE_COMPANY: "看公司背景，这应该是一家制造流水线烂片的小厂。不管怎么样，先试试和HR沟通吧！",
}

var _dims: Array[ColorRect] = []
var _ring: Panel
var _dialogue: Control
var _step := Step.LINE_INTRO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	# 等一帧：`DeskScreen` 下的东西（手机屏 / Boss）这时可能还没建好
	call_deferred("_start")


func _process(_dt: float) -> void:
	if _step >= Step.DONE:
		return
	# 洞每帧重算：列表滚动、App 顶开都会让目标换位置
	_update_hole()
	_check_progress()


# ============================================================
# 步骤
# ============================================================
func _start() -> void:
	var st := _state()
	var saved := st.tutorial_step if st != null else -1
	# -1 = 老档（字段缺失时 `from_save_dict` 给的默认值）→ 当作已经看过
	if saved < 0 or saved >= Step.DONE:
		_finish()
		return
	_enter(saved)


## 【为什么不直接写 `Game.state`】本脚本带 `class_name`，会在**全局类扫描**阶段被编译，
## 那时 autoload 还没注册，`Game` 是一个未定义标识符 —— 运行时报「Identifier not found」。
## 走 `get_node` 取，编译期不依赖单例表。
func _state() -> GameState:
	var g := get_node_or_null("/root/Game")
	if g == null:
		return null
	return g.get("state") as GameState


## 当前停在第几步（测试与调试用）
func step() -> int:
	return _step


## 洞的矩形（测试用）：没有洞时返回空 Rect2
func hole_rect() -> Rect2:
	var rect := _target_rect()
	return rect if rect.size.x > 0.0 and rect.size.y > 0.0 else Rect2()


func _enter(step: int) -> void:
	_step = step
	var st := _state()
	if st != null:
		st.tutorial_step = step
	_dialogue.visible = false
	if LINES.has(step):
		_dialogue.visible = true
		# 参数是 `Array[Dictionary]`，这里必须写成类型化数组 —— 传字面量会因元素类型不符而报错
		var lines: Array[Dictionary] = [{"speaker": "", "text": String(LINES[step])}]
		_dialogue.play_lines(lines)
	_update_hole()


func _go(step: int) -> void:
	if step >= Step.DONE:
		_finish()
		return
	_enter(step)


func _finish() -> void:
	_step = Step.DONE
	var st := _state()
	if st != null:
		st.tutorial_step = Step.DONE
	visible = false
	set_process(false)
	finished.emit()


## 玩家把这一步的目标点了没？**看状态，不拦点击** ——
## 拦截会让「点击落到按钮上」和「引导以为点到了」变成两件事。
func _check_progress() -> void:
	match _step:
		Step.TAP_PHONE:
			var desk := _desk()
			if desk != null and desk.has_open_screen():
				_go(Step.TAP_APP)
		Step.TAP_APP:
			var phone := _phone()
			if phone != null and phone.current_app_path() == BOSS_SCENE:
				_go(Step.LINE_COMPANIES)
		Step.TAP_COMPANY:
			var boss := _boss()
			if boss != null and boss.get("_current") != null:
				_go(Step.LINE_COMPANY)
		Step.TAP_CONTACT:
			var boss2 := _boss()
			if boss2 != null and boss2.chat_open():
				_finish()


func _on_line_finished() -> void:
	if LINES.has(_step):
		_go(_step + 1)


# ============================================================
# 界面
# ============================================================
func _build() -> void:
	for i in 4:
		var dim := ColorRect.new()
		dim.name = ["DimTop", "DimBottom", "DimLeft", "DimRight"][i]
		dim.color = DIM_COLOR
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(dim)
		_dims.append(dim)

	_ring = Panel.new()
	_ring.name = "Ring"
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.add_theme_stylebox_override("panel", _ring_style())
	add_child(_ring)

	# 对话层最后加 = 画在最上面。它自己是全屏 STOP，所以独白那几拍整屏都能点。
	_dialogue = load(DIALOGUE_SCENE).instantiate()
	add_child(_dialogue)
	_dialogue.finished.connect(_on_line_finished)


func _ring_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = UiPalette.BOSS
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(16)
	return sb


func _update_hole() -> void:
	var screen := _screen()
	var rect := _target_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		# 没有目标 = 独白那一拍：整屏都暗，点击交给对话框
		_dialogue_rects(screen)
		_ring.visible = false
		return

	rect = rect.intersection(screen)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		_dialogue_rects(screen)
		_ring.visible = false
		return

	_ring.visible = true
	_ring.position = rect.position
	_ring.size = rect.size
	_place(0, Rect2(0.0, 0.0, screen.size.x, rect.position.y))                       # 上
	_place(1, Rect2(0.0, rect.end.y, screen.size.x, screen.size.y - rect.end.y))     # 下
	_place(2, Rect2(0.0, rect.position.y, rect.position.x, rect.size.y))             # 左
	_place(3, Rect2(rect.end.x, rect.position.y, screen.size.x - rect.end.x, rect.size.y))  # 右


func _dialogue_rects(screen: Rect2) -> void:
	_place(0, screen)
	_place(1, Rect2())
	_place(2, Rect2())
	_place(3, Rect2())


func _place(i: int, rect: Rect2) -> void:
	var dim := _dims[i]
	var ok := rect.size.x > 0.0 and rect.size.y > 0.0
	dim.visible = ok
	if not ok:
		return
	dim.position = rect.position
	dim.size = rect.size


func _screen() -> Rect2:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		s = get_viewport_rect().size
	return Rect2(Vector2.ZERO, s)


# ============================================================
# 四个目标
# ============================================================
func _target_rect() -> Rect2:
	match _step:
		Step.TAP_PHONE:
			var desk := _desk()
			if desk == null:
				return Rect2()
			return _rect_of(desk.get_node_or_null("Hotspots/HotspotPhone") as Control)
		Step.TAP_APP:
			var phone := _phone()
			if phone == null:
				return Rect2()
			var rows: Dictionary = phone.get("_app_rows")
			return _rect_of(rows.get(BOSS_SCENE) as Control)
		Step.TAP_COMPANY:
			var boss := _boss()
			if boss == null:
				return Rect2()
			var rows: Dictionary = boss.get("_rows")
			return _rect_of(rows.get(FIRST_COMPANY) as Control)
		Step.TAP_CONTACT:
			var boss2 := _boss()
			if boss2 == null:
				return Rect2()
			return _rect_of(boss2.get("_contact_button") as Control)
	return Rect2()


## 目标在引导层里的矩形（本层铺满全屏，与屏幕坐标只差一个原点）
func _rect_of(c: Control) -> Rect2:
	if c == null or not c.is_visible_in_tree():
		return Rect2()
	var g := c.get_global_rect()
	var pos := get_global_transform().affine_inverse() * g.position
	return Rect2(pos, g.size).grow(HOLE_PAD)


func _desk() -> Node:
	var p := get_parent()
	return p.get_node_or_null("DeskScreen") if p != null else null


func _phone() -> Node:
	var desk := _desk()
	if desk == null:
		return null
	var open: Node = desk.get("_open")
	return open if open != null and open.has_method("current_app_path") else null


func _boss() -> Node:
	var phone := _phone()
	if phone == null:
		return null
	var current: Node = phone.get("_current")
	if current != null and current.has_method("chat_open"):
		return current
	return null
