extends SceneTree
## 新手引导验证 —— 斗到底「（指引立刻沟通）」
##
##   godot --path <项目> --script res://tools/test_tutorial.gd
##
## 【验什么】
##   1. 独白文案与策划文档逐字一致（写错一个字玩家就会看见）
##   2. 每一拍的洞正好圈在目标控件上（手机 / 简历拿来 / 小登传媒 / 立刻沟通）
##   3. 点了目标之后自动推进到下一拍；最后点「立刻沟通」= 本批引导结束
##   4. 进度进存档；老档（字段缺失）不会被拉回来重看

const TUTORIAL_SCENE := "res://scenes/ui/tutorial_layer.tscn"
const DESK_SCENE := "res://scenes/main/desk_screen.tscn"
const BOSS_SCENE := "res://scenes/apps/boss.tscn"
const WECHAT_SCENE := "res://scenes/apps/wechat.tscn"
const RECORDER_SCENE := "res://scenes/minigame/recorder.tscn"

var _failures: Array[String] = []
var _checks := 0
var _game
var _main
var _tut


func _initialize() -> void:
	_game = root.get_node_or_null("Game")
	# 【超时兜底】`_run` 是协程：中途一句脚本错误就会停在那里，
	# 而 `SceneTree` 不会自己退出 —— 表现就是「测试跑完不结束，窗口一直挂着」。
	# 卡到 3 分钟直接判失败退出，别把进程留在那儿。
	create_timer(90.0).timeout.connect(func() -> void:
		print("❌ 测试超时（3 分钟没跑完），强制退出")
		quit(1))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	print("")
	print("=== 新手引导验证 ===")
	print("")
	_check("Game autoload 可用", _game != null, true)
	if _game == null:
		print("❌ 环境没起来")
		quit(1)
		return

	print("[1] 新局：引导从第一句独白开始")
	# 引导层是 `main.gd` 挂上去的；它引用 `TutorialLayer.Step`，这里顺手确认它还能编译
	_check("主场景脚本能编译", load("res://scripts/apps/main.gd") != null, true)
	_game.new_game()
	_game.state.intro_done = true          # 开场不参与本节
	_game.state.tutorial_step = 0
	# 【为什么不直接实例化 main_scene】它的 `_ready` 会按状态**自动再挂一个引导层**
	# （`OS.has_feature("headless")` 只在 --headless 时为真，--script 跑测试时不是）。
	# 这里自己搭一个同名壳：只要有个 `DeskScreen` 兄弟，引导层就能找到目标。
	_main = Control.new()
	_main.name = "MainScene"
	root.add_child(_main)
	var desk_scene: Node = load(DESK_SCENE).instantiate()
	desk_scene.name = "DeskScreen"
	_main.add_child(desk_scene)
	await _wait(0.1)
	_tut = load(TUTORIAL_SCENE).instantiate()
	_main.add_child(_tut)
	await _wait(0.1)

	_check("引导层挂上了", is_instance_valid(_tut) and _tut.visible, true)
	_check("停在第 0 步（独白）", _tut.step(), TutorialLayer.Step.LINE_INTRO)
	_check("对话框露出来了", _tut._dialogue.visible, true)
	_check("内心独白不挂名字牌", _tut._dialogue._speaker_tag.visible, false)
	_check("独白第一句与策划文档一致",
			_tut._dialogue._lines[0]["text"],
			"好了......接下来看看先要做什么？")
	_check("独白这一拍没有洞（整屏都暗）", _tut.hole_rect(), Rect2())

	print("")
	print("[2] 点完独白 → 圈住桌上的「手机」")
	await _dismiss_dialogue()
	_check("推进到第 1 步", _tut.step(), TutorialLayer.Step.TAP_PHONE)
	_check("对话框收起来了", _tut._dialogue.visible, false)
	var phone_spot: Control = _desk().get_node("Hotspots/HotspotPhone")
	_check("洞圈在手机热点上", _same_rect(_tut.hole_rect(), phone_spot.get_global_rect().grow(10.0)), true)

	print("")
	print("[3] 点手机 → 圈住手机屏里的「简历拿来」")
	_desk()._on_activated(phone_spot)
	await _wait(0.1)
	_check("推进到第 2 步", _tut.step(), TutorialLayer.Step.TAP_APP)
	var phone: Node = _desk()._open
	_check("手机屏打开了", phone != null, true)
	var app_row: Control = phone._app_rows.get(BOSS_SCENE)
	_check("洞圈在「简历拿来」那一行", _same_rect(_tut.hole_rect(), app_row.get_global_rect().grow(10.0)), true)

	print("")
	print("[4] 点「简历拿来」→ 独白：五家公司")
	phone.open_app(BOSS_SCENE)
	await _wait(0.1)
	_check("推进到第 3 步", _tut.step(), TutorialLayer.Step.LINE_COMPANIES)
	_check("对话框又出来了", _tut._dialogue.visible, true)
	_check("第二句独白与策划文档一致",
			_tut._dialogue._lines[0]["text"],
			"这里是目前还在短剧制造相关的五家公司，先问问看它们收不收演员吧！")

	print("")
	print("[5] 点完独白 → 圈住「小登传媒」")
	await _dismiss_dialogue()
	_check("推进到第 4 步", _tut.step(), TutorialLayer.Step.TAP_COMPANY)
	var boss: Node = phone._current
	var row_a: Control = boss._rows.get("A")
	_check("洞圈在小登传媒那一行", _same_rect(_tut.hole_rect(), row_a.get_global_rect().grow(10.0)), true)

	print("")
	print("[6] 点「小登传媒」→ 独白：先试试和HR沟通")
	boss._select_company("A")
	await _wait(0.1)
	_check("推进到第 5 步", _tut.step(), TutorialLayer.Step.LINE_COMPANY)
	_check("第三句独白与策划文档一致",
			_tut._dialogue._lines[0]["text"],
			"看公司背景，这应该是一家制造流水线烂片的小厂。不管怎么样，先试试和HR沟通吧！")

	print("")
	print("[7] 点完独白 → 圈住「立刻沟通」→ 点它 → 进聊天（引导继续）")
	await _dismiss_dialogue()
	_check("推进到第 6 步", _tut.step(), TutorialLayer.Step.TAP_CONTACT)
	_check("洞圈在「立刻沟通」上",
			_same_rect(_tut.hole_rect(), boss._contact_button.get_global_rect().grow(10.0)), true)
	_check("按钮上写的确实是「立刻沟通」", boss._contact_button.text, "立刻沟通")
	boss._open_chat()
	await _wait(0.2)
	_check("聊起来之后进入「去微信聊」那一拍", _tut.step(), TutorialLayer.Step.TAP_WECHAT)

	print("")
	print("[8] 存档往返与老档")
	var d: Dictionary = _game.state.to_save_dict()
	_check("存档里有 tutorial_step", d.has("tutorial_step"), true)
	var fresh = load("res://scripts/core/game_state.gd").new()
	fresh.from_save_dict(d)
	_check("读档还原到当前这一拍", fresh.tutorial_step, TutorialLayer.Step.TAP_WECHAT)
	var old := {"money": 10}
	fresh.from_save_dict(old)
	_check("老档（没有这个字段）当作已完成", fresh.tutorial_step, -1)

	print("")
	print("[9] 第二批：去微信聊 → 选 HR → 选档位")
	_game.state.intro_done = true
	_tut._enter(TutorialLayer.Step.TAP_WECHAT)
	boss.skip_chat()                 # 把聊天播完，「去微信聊」才露出来
	await _wait(0.05)
	_check("「去微信聊」露出来了", boss._chat_to_wechat.visible, true)
	_check("洞圈在「去微信聊」",
			_same_rect(_tut.hole_rect(), boss._chat_to_wechat.get_global_rect().grow(10.0)), true)
	phone.open_app(WECHAT_SCENE)
	await _wait(0.3)
	_check("微信打开了", phone.current_app_path(), WECHAT_SCENE)
	var wx: Node = phone._current
	# 【开局可能挂着周初事件】微信会先打开那条"找上门的人"的会话（`_current` 为空）。
	# 引导这一步本来就是「点王先生」—— 直接把他按下去，走的是真实点击那条路。
	(wx._rows["A"] as Button).button_pressed = true
	await _wait(0.2)
	_check("点了王先生 → 会话切到小登传媒", wx._current.code, "A")
	_check("推进到「选档位」那一拍", _tut.step(), TutorialLayer.Step.TAP_TIER)
	# 头一回点开会先"打一会儿字"，档位按钮等那排点落地才长出来
	var guard := 0
	while wx._tier_buttons.is_empty() and guard < 60:
		await _wait(0.1)
		guard += 1
	_check("档位按钮长出来了", wx._tier_buttons.size(), 3)
	var tier_btn: Control = wx._tier_buttons[0]
	_check("洞圈在第一个档位（龙套）",
			_same_rect(_tut.hole_rect(), tier_btn.get_global_rect().grow(10.0)), true)

	print("")
	print("[10] 录像机五条讲解的洞")
	phone.open_app(RECORDER_SCENE)
	await _wait(0.25)
	_check("录像机打开了", phone.current_app_path(), RECORDER_SCENE)
	var rec: Node = phone._current
	_tut._enter(TutorialLayer.Step.LINE_TABS)
	await _wait(0.05)
	_check("分类页签的洞",
			_same_rect(_tut.hole_rect(), (rec._tabs[0] as Control).get_global_rect().grow(10.0)), true)
	_tut._enter(TutorialLayer.Step.LINE_PARTS)
	await _wait(0.05)
	var first_card: Control = _tut._first_part_card()
	_check("部件卡的洞",
			_same_rect(_tut.hole_rect(), first_card.get_global_rect().grow(10.0)), true)
	_tut._enter(TutorialLayer.Step.LINE_SLOTS)
	await _wait(0.05)
	_check("帧槽的洞",
			_same_rect(_tut.hole_rect(), (rec._slot_buttons[1] as Control).get_global_rect().grow(10.0)), true)
	_tut._enter(TutorialLayer.Step.LINE_NEED)
	await _wait(0.05)
	_check("所需分数的洞",
			_same_rect(_tut.hole_rect(), (rec._score_labels[0] as Control).get_global_rect().grow(10.0)), true)
	_tut._enter(TutorialLayer.Step.LINE_HAVE)
	await _wait(0.05)
	_check("现有分数的洞",
			_same_rect(_tut.hole_rect(), (rec._emotion_value as Control).get_global_rect().grow(10.0)), true)

	print("")
	print("[11] 记忆抽取：翻开一张就拿到那套，收下即本批结束")
	_tut._enter(TutorialLayer.Step.TAP_CARD)
	await _wait(0.15)
	_check("记忆抽取层弹出来了", _tut._memory != null, true)
	_tut._memory._cards[0].pressed.emit()
	await _wait(0.7)
	_check("翻到的是爆缸笑脸", _tut._memory.picked_id(), "blowup")
	_check("那套已经记进状态", _game.state.owned_sets.has("blowup"), true)
	# 本层正盖在录像机上：抽到的那一刻那三件就该从灰变亮，不然玩家以为没生效
	_check("录像机里的爆缸眼立刻解禁",
			(rec._cards[PartData.Slot.EYES]["eyes_10"] as Button).disabled, false)
	_tut._memory._claim.pressed.emit()
	await _wait(0.1)
	_check("收下后进入「自己拼」的放行段", _tut.step(), TutorialLayer.Step.WAIT_BUILD)
	_check("引导层还留着（没结束）", _tut.visible, true)
	# 【曾经卡在这】收下之后那块全屏的抽取层没被收走，玩家点不动录像机
	_check("收下后抽取层整个收走", _tut._memory, null)
	_check("遮罩也放行了（没有一块 dim 还挡着）",
			_tut._dims.all(func(d: ColorRect) -> bool: return not d.visible), true)

	print("")
	print("[12] 拼完回微信 → 投递 → 回桌面 → 日历 → 下一天")
	var clip := Clip.new()
	_game.set_pending_clip(clip)
	phone.open_app(WECHAT_SCENE)
	await _wait(0.3)
	_check("微信打开了", phone.current_app_path(), WECHAT_SCENE)
	var wx2: Node = phone._current
	(wx2._rows["A"] as Button).button_pressed = true
	await _wait(0.2)
	_check("回微信落在王先生", wx2._current.code, "A")
	_check("刚拼好的表情包带回来了", wx2._pending != null, true)
	_check("推进到「发送」那一拍", _tut.step(), TutorialLayer.Step.TAP_SEND)
	_check("洞圈在发送按钮",
			_same_rect(_tut.hole_rect(), (phone._current._send_button as Control).get_global_rect().grow(10.0)), true)
	# 投递成功会把手上那份清掉（真实路径在 `_on_send` 里）
	phone._current._pending = null
	await _wait(0.2)
	_check("投递后是「一整套流程做完了」的独白", _tut.step(), TutorialLayer.Step.LINE_SUBMITTED)
	await _dismiss_dialogue()
	_check("推进到「返回桌面」", _tut.step(), TutorialLayer.Step.TAP_BACK_DESK)
	_check("洞圈在「返回桌面」",
			_same_rect(_tut.hole_rect(), (phone._back_button as Control).get_global_rect().grow(10.0)), true)
	(phone._back_button as Button).pressed.emit()
	await _wait(0.2)
	_check("回到桌面了", _desk().has_open_screen(), false)
	_check("推进到「点日历」", _tut.step(), TutorialLayer.Step.TAP_CALENDAR)
	var cal_spot: Control = _desk().get_node("Hotspots/HotspotCalendar")
	_check("洞圈在日历热点",
			_same_rect(_tut.hole_rect(), cal_spot.get_global_rect().grow(10.0)), true)
	_desk()._on_activated(cal_spot)
	await _wait(0.3)
	_check("推进到晚间独白", _tut.step(), TutorialLayer.Step.LINE_EVENING)
	await _dismiss_dialogue()
	_check("推进到「确认下一天」", _tut.step(), TutorialLayer.Step.TAP_END_DAY)
	var cal: Node = _desk()._open
	var end_btn: Control = cal._cards["end"]["button"]
	_check("洞圈在「确认安排（下一天）」",
			_same_rect(_tut.hole_rect(), end_btn.get_global_rect().grow(10.0)), true)
	end_btn.pressed.emit()
	await _wait(0.5)
	_check("点完下一天 → 引导结束", _tut.step(), TutorialLayer.Step.DONE)
	_check("引导层收起来了", _tut.visible, false)
	_check("存档写明已完成", _game.state.tutorial_step, TutorialLayer.Step.DONE)

	print("")
	print("[13] 新局从 0 开始（重开会把界面一起收掉，所以放最后）")
	_game.new_game()
	_check("新局从 0 开始", _game.state.tutorial_step, 0)

	_finish()


## 把当前这句独白点掉（第一次点补全打字，第二次点进下一句/下一拍）
func _dismiss_dialogue() -> void:
	var guard := 0
	while _tut._dialogue.visible and guard < 30:
		_tut._dialogue.advance()
		await process_frame
		guard += 1


func _desk() -> Node:
	return _main.get_node("DeskScreen")


func _same_rect(a: Rect2, b: Rect2) -> bool:
	return absf(a.position.x - b.position.x) <= 1.0 \
		and absf(a.position.y - b.position.y) <= 1.0 \
		and absf(a.size.x - b.size.x) <= 1.0 \
		and absf(a.size.y - b.size.y) <= 1.0


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _check(label: String, got: Variant, want: Variant) -> void:
	_checks += 1
	if got != want:
		_failures.append("%s: 期望 %s，实际 %s" % [label, want, got])


func _finish() -> void:
	print("")
	print("共 %d 项断言" % _checks)
	if _failures.is_empty():
		print("✅ 全部通过")
		quit(0)
	else:
		print("❌ %d 项失败：" % _failures.size())
		for f: String in _failures:
			print("   - " + f)
		quit(1)
