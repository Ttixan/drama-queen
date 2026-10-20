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
	WAIT_SCRIPT_READ = 11,## 放行：让玩家先读 5 秒剧本，再圈关闭
	TAP_SCRIPT_BACK = 12,## 圈住剧本页右上角的 ×（关闭）
	TAP_RECORDER = 13,   ## 圈住「去录像机」
	TAP_LOAD_SCRIPT = 14,## 圈住底栏「加载剧本」
	TAP_PICK_SCRIPT = 15,## 圈住弹窗里第一个剧本
	LINE_TABS = 16,      ## 独白：这里选五官分类
	TAP_TAB = 17,        ## 圈住一个分类页签（逼玩家点一下）
	LINE_PARTS = 18,     ## 独白：这里选具体部件
	TAP_PART = 19,       ## 圈住一张部件卡
	LINE_SLOTS = 20,     ## 独白：这里调帧数
	LINE_NEED = 21,      ## 独白：这是需要的情绪浓度
	LINE_HAVE = 22,      ## 独白：这是你脸上现有的情绪
	LINE_MEMORY = 23,    ## 独白三段（普鲁奇克 + 内存碎片）→ 弹记忆抽取
	TAP_CARD = 24,       ## 翻开一张牌
	# ---- ③ 拼贴 → 投递 → 回桌面 → 日历 ----
	WAIT_BUILD = 25,     ## 放行：玩家自己把三帧拼完（引导不遮）
	TAP_SEND = 26,       ## 圈住微信的「发送」（投递）
	LINE_SUBMITTED = 27, ## 独白：一整套应聘流程做完了
	TAP_BACK_DESK = 28,  ## 圈住「返回桌面」
	TAP_CALENDAR = 29,   ## 圈住桌上的日历
	LINE_EVENING = 30,   ## 独白：闲暇可以做别的事 / 今天先休息 / 拿下 Pswitch
	TAP_END_DAY = 31,    ## 圈住「确认安排（下一天）」
	DONE = 32,           ## 引导全部走完
}

## 剧本页打开后先让人读几秒，再圈右上角的 ×
## 【为什么不是立刻圈】剧本是这一套流程里唯一需要"读"的东西，
## 刚弹出来就在角上画个框，玩家还没看内容就先去点叉了
const SCRIPT_READ_SEC := 5.0

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
	Step.LINE_SUBMITTED: [
		"像这样，一整套应聘的流程就做完了！不管结果好不好，事情总算是推进了，"
		+ "那么接下来的二十一天也像这样加油吧！",
	],
	Step.LINE_EVENING: [
		"除开试镜投递和演戏的时间，闲暇之余也可以做做别的事增加收入、精进演技，"
		+ "毕竟人生不能只有工作嘛。",
		"今天的试镜以及花费了你的所有精力。那么接下来的时间就好好休息，准备明天的工作好了！",
		"Pswitch box2，这次你势必拿下。",
	],
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
## 剧本页要放过的时间点（毫秒，见 `SCRIPT_READ_SEC`）
var _script_read_until := 0


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

	# 剧本页：进来先给玩家 5 秒读，时间到了才画「点这里关掉」
	if step == Step.WAIT_SCRIPT_READ:
		_script_read_until = Time.get_ticks_msec() + int(SCRIPT_READ_SEC * 1000.0)

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
				_go(Step.WAIT_SCRIPT_READ)
		Step.WAIT_SCRIPT_READ:
			# 让玩家先读几秒，时间到了才在右上角画出「点这里关掉」
			if Time.get_ticks_msec() >= _script_read_until:
				_go(Step.TAP_SCRIPT_BACK)
		Step.TAP_SCRIPT_BACK:
			var wx4 := _wechat()
			if wx4 != null and not _visible_of(wx4, "_script_overlay"):
				_go(Step.TAP_RECORDER)
		Step.TAP_RECORDER:
			var phone3 := _phone()
			if phone3 != null and phone3.current_app_path() == RECORDER_SCENE:
				_go(Step.TAP_LOAD_SCRIPT)
		Step.TAP_LOAD_SCRIPT:
			# 底栏「加载剧本」→ 弹出选择框（`_dialog_layer` 非空 = 弹窗开着）
			var rec5 := _recorder()
			if rec5 != null and rec5.get("_dialog_layer") != null:
				_go(Step.TAP_PICK_SCRIPT)
		Step.TAP_PICK_SCRIPT:
			var rec6 := _recorder()
			if rec6 != null and rec6.get("_loaded_doc") != null:
				_go(Step.LINE_TABS)
		Step.TAP_TAB:
			var rec := _recorder()
			if rec != null and int(rec.get("_tab")) != _tab_at_entry:
				_go(Step.LINE_PARTS)
		Step.TAP_PART:
			var rec2 := _recorder()
			if rec2 != null and _has_picked_part(rec2):
				_go(Step.LINE_SLOTS)
		# ---- ③ 拼完 → 投递 → 桌面 → 日历 ----
		Step.WAIT_BUILD:
			# 玩家在录像机里自己拼三帧；点「完成」后手机屏会自动切回微信
			var phone4 := _phone()
			if phone4 != null and phone4.current_app_path() == WECHAT_SCENE:
				_go(Step.TAP_SEND)
		Step.TAP_SEND:
			# 投递成功会把手上那份表情包清掉（`_on_send` 里的 `_pending = null`）
			var wx6 := _wechat()
			if wx6 != null and wx6.get("_pending") == null:
				_go(Step.LINE_SUBMITTED)
		Step.TAP_BACK_DESK:
			var desk2 := _desk()
			if desk2 != null and not desk2.has_open_screen():
				_go(Step.TAP_CALENDAR)
		Step.TAP_CALENDAR:
			if _calendar() != null:
				_go(Step.LINE_EVENING)
		Step.TAP_END_DAY:
			# `end_day()` 是同步的：点完 `Game.day()` 立刻变 2。
			# 【马上收工】推进后会开周结算翻牌层（在日历里、引导层之下），
			# 引导再挡着就点不到它了。
			var st := _state()
			if st != null and st.day >= 2:
				_finish()


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
	# 走 Game 层，不走 GameState：它顺手发 `expression_set_owned`，
	# 录像机收到会把刚抽到的那套从灰变亮（本层这时正盖在它上面）
	var game := get_node_or_null("/root/Game")
	if game != null:
		game.grant_expression_set(set_id)


func _on_memory_finished() -> void:
	# 【收下 = 把这一层整个收走】它是一整块全屏 Control（自带暗底 + STOP），
	# 留着会把录像机挡得死死的 —— 玩家看到的就是「点了收下没反应」。
	if _memory != null and is_instance_valid(_memory):
		_memory.queue_free()
		_memory = null
	# 【不是结束，是放行】收下之后轮到玩家自己拼三帧 —— 引导退到背景等着，
	# 等他从录像机点「完成」回到微信再接着指下一拍。
	_go(Step.WAIT_BUILD)


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
		Step.WAIT_SCRIPT_READ, Step.TAP_SCRIPT_BACK, Step.TAP_RECORDER,
		Step.TAP_LOAD_SCRIPT, Step.TAP_PICK_SCRIPT, Step.TAP_TAB, Step.TAP_PART,
		Step.TAP_CARD,
		# 收尾这几拍同理：拼贴期间、回微信的路上，都不能被遮罩挡住
		Step.WAIT_BUILD, Step.TAP_SEND, Step.TAP_BACK_DESK,
		Step.TAP_CALENDAR, Step.TAP_END_DAY,
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
		Step.TAP_LOAD_SCRIPT:
			var rec0 := _recorder()
			return _rect_of(rec0.get("_script_button") as Control) if rec0 != null else Rect2()
		Step.TAP_PICK_SCRIPT:
			return _rect_of(_script_row())
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
			# 剧本可能只有 1 场（龙套本常见）——那时只有第 0 个槽，别去取 [1]
			var idx: int = 1 if slots.size() > 1 else 0
			return _rect_of(slots[idx] as Control) if slots.size() > idx else Rect2()
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
		Step.TAP_SEND:
			var wx6 := _wechat()
			return _rect_of(wx6.get("_send_button") as Control) if wx6 != null else Rect2()
		Step.TAP_BACK_DESK:
			var phone4 := _phone()
			return _rect_of(phone4.get("_back_button") as Control) if phone4 != null else Rect2()
		Step.TAP_CALENDAR:
			var desk2 := _desk()
			if desk2 == null:
				return Rect2()
			return _rect_of(desk2.get_node_or_null("Hotspots/HotspotCalendar") as Control)
		Step.TAP_END_DAY:
			var cal := _calendar()
			if cal == null:
				return Rect2()
			var cards: Dictionary = cal.get("_cards")
			var end: Dictionary = cards.get("end", {})
			return _rect_of(end.get("button") as Control)
	return Rect2()


## 剧本选择弹窗里第一条（「点击第一个剧本」）——
## 弹窗是运行时现搭的，列表行没有稳定名字，只能按类型在层里找第一个 Button
func _script_row() -> Control:
	var rec := _recorder()
	if rec == null:
		return null
	var layer := rec.get("_dialog_layer") as Node
	if layer == null:
		return null
	for node: Node in layer.find_children("*", "Button", true, false):
		return node as Control
	return null


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


## 日历屏不是手机屏：它直接挂在 `DeskScreen._open` 下（`_phone()` 会把它过滤掉）。
func _calendar() -> Node:
	var desk := _desk()
	if desk == null:
		return null
	var open: Node = desk.get("_open")
	if open != null and open.get("_cards") != null:
		return open
	return null
