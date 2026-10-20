class_name TutorialLayer
extends Control
## 新手引导 —— 底部「内心独白」对话框 + 半透明遮罩把该点的东西圈出来
##
## 文案来源：`.document/文案/hr与引导文案策划部分.docx` 的「新手引导（对话框）」。
## 两大段：
##   ① 桌面 → 手机 → 简历拿来 → 小登传媒 → 立刻沟通
##   ② 去微信 → 选 HR → 选档位 → 开剧本 → 返回 → 去录像机 → 录像机五条讲解
##      → 记忆抽取（三张拍立得翻一张）→ 进拼贴
##
## 【为什么是「挖洞」而不是「蒙一层再画个框」】引导期间**只允许点目标**：
## 洞外铺四块半透明矩形（每块都吃点击），洞内什么都不放 —— 点击直接落到真正的按钮上。
## 这样既不用给每个按钮加一套「引导专用」逻辑，也不会因为给遮罩开穿透而把别处一起放开。
##
## 【目标还没出现时为什么不遮】「去微信聊」「档位按钮」都是聊到某一步才长出来的。
## 那几拍如果照样蒙一层，玩家点不了聊天里的选项，就卡死了 —— 所以
## TAP_* 步骤找不到目标时整层放行，目标一出现洞就跟着出来。
##
## 【坐标为什么每帧算】公司行 / 档位按钮 / 剧本卡都在滚动列表里，写死坐标必然错位。

signal finished

enum Step {
	# ---- ① 开场 ----
	LINE_INTRO = 0,      ## 独白：好了......接下来看看先要做什么？
	TAP_PHONE = 1,       ## 圈住桌上的手机
	TAP_APP = 2,         ## 圈住手机屏里的「简历拿来」
	LINE_COMPANIES = 3,  ## 独白：这里是目前还在短剧制造相关的五家公司……
	TAP_COMPANY = 4,     ## 圈住列表里的「小登传媒」
	LINE_COMPANY = 5,    ## 独白：看公司背景……先试试和HR沟通吧！
	TAP_CONTACT = 6,     ## 圈住详情页的「立刻沟通」
	# ---- ② 微信 → 剧本 → 录像机 ----
	TAP_WECHAT = 7,      ## 圈住聊天页的「去微信聊」
	TAP_HR_ROW = 8,      ## 圈住微信里的「王先生」
	TAP_TIER = 9,        ## 圈住档位按钮（龙套）
	TAP_SCRIPT_CARD = 10,## 圈住 HR 发来的剧本文件卡
	TAP_SCRIPT_BACK = 11,## 圈住剧本页的返回
	TAP_RECORDER = 12,   ## 圈住「去录像机」
	LINE_TABS = 13,      ## 独白：这里选五官分类
	TAP_TAB = 14,        ## 圈住一个分类页签（逼玩家点一下）
	LINE_PARTS = 15,     ## 独白：这里选具体部件
	TAP_PART = 16,       ## 圈住一张部件卡
	LINE_SLOTS = 17,     ## 独白：这里调帧数
	LINE_NEED = 18,      ## 独白：这是需要的情绪浓度
	LINE_HAVE = 19,      ## 独白：这是你脸上现有的情绪
	LINE_MEMORY = 20,    ## 独白三段（普鲁奇克 + 内存碎片）→ 弹记忆抽取
	TAP_CARD = 21,       ## 翻开一张牌
	DONE = 22,           ## 本批引导结束（进拼贴轮）
}

const DIALOGUE_SCENE := "res://scenes/ui/dialogue_box.tscn"
const MEMORY_SCENE := "res://scenes/ui/memory_draw.tscn"
const BOSS_SCENE := "res://scenes/apps/boss.tscn"
const WECHAT_SCENE := "res://scenes/apps/wechat.tscn"
const RECORDER_SCENE := "res://scenes/minigame/recorder.tscn"

const DIM_COLOR := Color(0, 0, 0, 0.55)
## 洞比目标大一圈：描边贴着按钮边缘会看起来像按钮自己多了一道边
const HOLE_PAD := 10.0
## 第一家：引导指名要聊的就是它（md 里的「小登传媒」，内部代号 A）
const FIRST_COMPANY := "A"

## 独白文案。speaker 留空 —— 内心独白没有名字牌。
## 值是**数组**：一拍可以连说好几段（记忆抽取那拍就是三段连着念）。
const LINES := {
	Step.LINE_INTRO: ["好了......接下来看看先要做什么？"],
	Step.LINE_COMPANIES: ["这里是目前还在短剧制造相关的五家公司，先问问看它们收不收演员吧！"],
	Step.LINE_COMPANY: ["看公司背景，这应该是一家制造流水线烂片的小厂。不管怎么样，先试试和HR沟通吧！"],
	Step.LINE_TABS: ["这里可以用来选择你想调动的五官"],
	Step.LINE_PARTS: ["这里可以用来选择你想让它演绎怎么样的情绪"],
	Step.LINE_SLOTS: ["这里可以用来调整你所试镜的这个剧本需要的试镜片段总数"],
	Step.LINE_NEED: ["这是这个表情需要拿到的情绪浓度"],
	Step.LINE_HAVE: ["这是你的脸上现有的情绪"],
	Step.LINE_MEMORY: [
		"进入情绪之前，你忽然想起普鲁奇克的理论：人类那些复杂的情绪，比如爱与内疚，"
		+ "拆开来看，也不过是喜悦、恐惧和悲伤这些基础情绪按比例叠加的结果。",
		"既然连情绪都能被拆解重组，那是不是……以前的那些回忆也能帮到你呢？",
		"（你从大脑的内存碎片里，勉强抽出了几个能用的表情……）",
	],
}

var _dims: Array[ColorRect] = []
var _ring: Panel
var _dialogue: Control
var _memory: Control
var _step := Step.LINE_INTRO
## 进「点分类」那拍时记下当前页签 —— 玩家切到别的页签才算点过
var _tab_at_entry := -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	# 等一帧：`DeskScreen` 下的东西（手机屏 / Boss / 微信）这时可能还没建好
	call_deferred("_start")


func _process(_dt: float) -> void:
	if _step >= Step.DONE:
		return
	# 洞每帧重算：列表滚动、App 顶开都会让目标换位置
	_update_hole()
	_check_progress()


## 状态层。**这里不写 `Game.xxx` 全局名**：本脚本带 `class_name`，会在全局类扫描
## 阶段被编译，那时 autoload 还没注册，`Game` 是一个未定义标识符。
func _state() -> GameState:
	var g := get_node_or_null("/root/Game")
	if g == null:
		return null
	return g.get("state") as GameState


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

	# 录像机五条讲解里的「点分类」：记下进来时的页签，切走才算点过
	if step == Step.LINE_TABS:
		var rec := _recorder()
		_tab_at_entry = int(rec.get("_tab")) if rec != null else -1

	# 记忆抽取：进这一拍才把三张牌摆出来（在对话框下面一层）
	if step == Step.TAP_CARD:
		_open_memory()

	var raw: Array = LINES.get(step, [])
	var lines: Array[Dictionary] = []
	for text: String in raw:
		lines.append({"speaker": "", "text": text})
	_dialogue.visible = not lines.is_empty()
	if not lines.is_empty():
		_dialogue.play_lines(lines)
	_update_hole()


func _go(step: int) -> void:
	if step >= Step.DONE:
		_finish()
		return
	_enter(step)


func _finish() -> void:
	# 【`_step` 也要拨到 DONE】否则 `step()` 还停在最后一拍，而存档里已经写完成了 ——
	# 测试与调试会看到两个自相矛盾的数
	_step = Step.DONE
	var st := _state()
	if st != null:
		st.tutorial_step = Step.DONE
	if _memory != null and is_instance_valid(_memory):
		_memory.queue_free()
		_memory = null
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
				_go(Step.TAP_WECHAT)
		Step.TAP_WECHAT:
			var phone2 := _phone()
			if phone2 != null and phone2.current_app_path() == WECHAT_SCENE:
				_go(Step.TAP_HR_ROW)
		Step.TAP_HR_ROW:
			var wx := _wechat()
			if wx != null and wx.get("_current") != null:
				_go(Step.TAP_TIER)
		Step.TAP_TIER:
			# 等 HR 把《试戏片段》那张卡发过来（选完档位要「打一会儿字」）
			var wx2 := _wechat()
			if wx2 != null and _script_card(wx2) != null:
				_go(Step.TAP_SCRIPT_CARD)
		Step.TAP_SCRIPT_CARD:
			var wx3 := _wechat()
			if wx3 != null and _visible_of(wx3, "_script_overlay"):
				_go(Step.TAP_SCRIPT_BACK)
		Step.TAP_SCRIPT_BACK:
			var wx4 := _wechat()
			if wx4 != null and not _visible_of(wx4, "_script_overlay"):
				_go(Step.TAP_RECORDER)
		Step.TAP_RECORDER:
			var phone3 := _phone()
			if phone3 != null and phone3.current_app_path() == RECORDER_SCENE:
				_go(Step.LINE_TABS)
		Step.TAP_TAB:
			var rec := _recorder()
			if rec != null and int(rec.get("_tab")) != _tab_at_entry:
				_go(Step.LINE_PARTS)
		Step.TAP_PART:
			var rec2 := _recorder()
			if rec2 != null and _has_picked_part(rec2):
				_go(Step.LINE_SLOTS)


func _on_line_finished() -> void:
	var raw: Array = LINES.get(_step, [])
	if raw.is_empty():
		return
	# 录像机五条讲解是连着念的，念完直接往下走
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


func _open_memory() -> void:
	if _memory != null and is_instance_valid(_memory):
		return
	_memory = load(MEMORY_SCENE).instantiate()
	add_child(_memory)
	# 摆在对话框下面：独白还没念完时，牌不该抢镜
	move_child(_memory, _dialogue.get_index())
	_memory.picked.connect(_on_memory_picked)
	_memory.finished.connect(_on_memory_finished)


func _on_memory_picked(set_id: String) -> void:
	var st := _state()
	if st != null:
		st.grant_expression_set(set_id)


func _on_memory_finished() -> void:
	_go(Step.DONE)


func _update_hole() -> void:
	var screen := _screen()
	var rect := _target_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		if _waits_for_target():
			# 目标还没出现（聊天还没聊到那一步 / 档位按钮还没长出来）——
			# 整层放行，否则玩家点不了聊天里的选项，直接卡死
			_hide_dims()
			_ring.visible = false
			return
		# 讲解拍：整屏都暗，点击交给对话框
		_place(0, screen)
		_place(1, Rect2())
		_place(2, Rect2())
		_place(3, Rect2())
		_ring.visible = false
		return

	rect = rect.intersection(screen)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		_hide_dims()
		_ring.visible = false
		return

	_ring.visible = true
	_ring.position = rect.position
	_ring.size = rect.size
	_place(0, Rect2(0.0, 0.0, screen.size.x, rect.position.y))                       # 上
	_place(1, Rect2(0.0, rect.end.y, screen.size.x, screen.size.y - rect.end.y))     # 下
	_place(2, Rect2(0.0, rect.position.y, rect.position.x, rect.size.y))             # 左
	_place(3, Rect2(rect.end.x, rect.position.y, screen.size.x - rect.end.x, rect.size.y))  # 右


## 这一拍是不是「等某个控件长出来才点」
func _waits_for_target() -> bool:
	return _step in [
		Step.TAP_WECHAT, Step.TAP_HR_ROW, Step.TAP_TIER, Step.TAP_SCRIPT_CARD,
		Step.TAP_SCRIPT_BACK, Step.TAP_RECORDER, Step.TAP_TAB, Step.TAP_PART,
		Step.TAP_CARD,
	]


func _hide_dims() -> void:
	for dim in _dims:
		dim.visible = false


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
# 目标控件
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
			var rows2: Dictionary = boss.get("_rows")
			return _rect_of(rows2.get(FIRST_COMPANY) as Control)
		Step.TAP_CONTACT:
			var boss2 := _boss()
			if boss2 == null:
				return Rect2()
			return _rect_of(boss2.get("_contact_button") as Control)
		Step.TAP_WECHAT:
			var boss3 := _boss()
			if boss3 == null:
				return Rect2()
			return _rect_of(boss3.get("_chat_to_wechat") as Control)
		Step.TAP_HR_ROW:
			var wx := _wechat()
			if wx == null:
				return Rect2()
			var contacts: Dictionary = wx.get("_rows")
			return _rect_of(contacts.get(FIRST_COMPANY) as Control)
		Step.TAP_TIER:
			var wx2 := _wechat()
			if wx2 == null:
				return Rect2()
			var tiers: Array = wx2.get("_tier_buttons")
			return _rect_of(tiers[0] as Control) if tiers.size() > 0 else Rect2()
		Step.TAP_SCRIPT_CARD:
			var wx3 := _wechat()
			return _rect_of(_script_card(wx3)) if wx3 != null else Rect2()
		Step.TAP_SCRIPT_BACK:
			var wx4 := _wechat()
			if wx4 == null:
				return Rect2()
			return _rect_of(wx4.get("_script_back_button") as Control)
		Step.TAP_RECORDER:
			var wx5 := _wechat()
			if wx5 == null:
				return Rect2()
			return _rect_of(wx5.get("_open_recorder_button") as Control)
		Step.LINE_TABS, Step.TAP_TAB:
			var rec := _recorder()
			if rec == null:
				return Rect2()
			var tabs: Array = rec.get("_tabs")
			var idx := 1 if _step == Step.TAP_TAB else 0
			return _rect_of(tabs[idx] as Control) if tabs.size() > idx else Rect2()
		Step.LINE_PARTS, Step.TAP_PART:
			return _rect_of(_first_part_card())
		Step.LINE_SLOTS:
			var rec2 := _recorder()
			if rec2 == null:
				return Rect2()
			var slots: Array = rec2.get("_slot_buttons")
			return _rect_of(slots[1] as Control) if slots.size() > 1 else Rect2()
		Step.LINE_NEED:
			var rec3 := _recorder()
			if rec3 == null:
				return Rect2()
			var scores: Array = rec3.get("_score_labels")
			return _rect_of(scores[0] as Control) if scores.size() > 0 else Rect2()
		Step.LINE_HAVE:
			var rec4 := _recorder()
			if rec4 == null:
				return Rect2()
			return _rect_of(rec4.get("_emotion_value") as Control)
	return Rect2()


## 当前分类页里第一张「真部件」卡（跳过留空那张）
func _first_part_card() -> Control:
	var rec := _recorder()
	if rec == null:
		return null
	var cards: Dictionary = rec.get("_cards")
	var page: Dictionary = cards.get(int(rec.get("_tab")), {})
	for key: String in page:
		if not key.is_empty():
			return page[key] as Control
	return null


## 录像机里有没有已经点上的部件（任意一张卡 pressed）
func _has_picked_part(rec: Node) -> bool:
	var cards: Dictionary = rec.get("_cards")
	for slot: int in cards:
		var page: Dictionary = cards[slot]
		for key: String in page:
			var b := page[key] as Button
			if b != null and b.button_pressed:
				return true
	return false


## 目标在引导层里的矩形（本层铺满全屏，与屏幕坐标只差一个原点）
func _rect_of(c: Control) -> Rect2:
	if c == null or not c.is_visible_in_tree():
		return Rect2()
	var g := c.get_global_rect()
	var pos := get_global_transform().affine_inverse() * g.position
	return Rect2(pos, g.size).grow(HOLE_PAD)


func _visible_of(node: Node, prop: String) -> bool:
	var c := node.get(prop) as Control
	return c != null and c.visible


func _script_card(wx: Node) -> Control:
	if wx == null:
		return null
	var log := wx.get("_chat_log") as Node
	if log == null:
		return null
	return log.find_child("ScriptCard", true, false) as Control


# ============================================================
# 三个界面的实例
# ============================================================
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


func _wechat() -> Node:
	var phone := _phone()
	if phone == null:
		return null
	var current: Node = phone.get("_current")
	if current != null and current.get("_script_overlay") != null:
		return current
	return null


func _recorder() -> Node:
	var phone := _phone()
	if phone == null:
		return null
	var current: Node = phone.get("_current")
	if current != null and current.get("_score_labels") != null:
		return current
	return null
