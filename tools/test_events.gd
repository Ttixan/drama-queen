extends SceneTree
## 周初事件链 —— 事件表 / 挑选 / 处理 / 存档可复现
##
##   godot --headless --path <项目> --script res://tools/test_events.gd
##
## 覆盖三件最容易漏的事：
##   1. **一周只演一出** —— 处理完再从通用池捞一条出来，玩家会一周遇两回事
##   2. **行动点花光之后** —— 收了行动点的选项要灰掉，但免费那条必须还能点，
##      否则这一周就被卡死了（行动点是唯一不能欠的资源）
##   3. **读档之后还是同一出** —— 事件是抽签挑的，重抽会让「上周那出戏」换一个

var _failures: Array[String] = []
var _total := 0


func _initialize() -> void:
	_test_book()
	_test_pick_by_week()
	_test_conditions_and_pool()
	_test_repeat_rule()
	_test_action_point_gate()
	_test_resolve()
	_test_clamp()
	_test_miss()
	_test_save_round_trip()
	_finish()


# ============================================================
func _test_book() -> void:
	print("[1] 事件表本身")
	_check("事件表读到了", EventLibrary.count() > 0, true)
	_check("内容自检没有报错", EventLibrary.book().validate(), [] as Array[String])
	var weeks := EventLibrary.book().scheduled_weeks()
	_check("第 1~3 周都有专属排期", Array(weeks), [1, 2, 3])
	_check("通用池非空", EventLibrary.book().any_week().size() > 0, true)
	# GDD 3.4 那四个事件都在
	for id: StringName in [&"director_audition", &"bad_film_offer", &"friend_loan", &"class_discount"]:
		_check("事件「%s」在表里" % id, EventLibrary.find(id) != null, true)
	for e: EventData in EventLibrary.all():
		_check("%s 正好两个选项" % e.id, e.options.size(), 2)
		# 【这条是硬约束】两个都收行动点的话，把当天这点花光的玩家会被卡死在这一周
		_check("%s 至少一个免费选项" % e.id, e.has_free_option(), true)
		_check("%s 有说话人" % e.id, e.speaker_name.is_empty(), false)
		_check("%s 有开场白" % e.id, e.intro.strip_edges().is_empty(), false)
	print("   %d 个事件，第 1~3 周各有专属，另有一个通用池" % EventLibrary.count())


func _test_pick_by_week() -> void:
	print("[2] 每周挑一个")
	var s := _state()
	s.event_seed = 20261013
	var w1 := EventScheduler.pick(s, 1)
	var w2 := EventScheduler.pick(s, 2)
	var w3 := EventScheduler.pick(s, 3)
	# 【这道闸门很要紧】下面每条都要读 `.id`，挑不到就会让本函数中断 ——
	# 而 GDScript 的报错**不会让测试变红**：它会安静地跳过剩下的断言，
	# 最后照样打印「全部通过」。所以先确认三条都挑到了。
	_check("第 1~3 周都挑到了事件", w1 != null and w2 != null and w3 != null, true)
	if w1 == null or w2 == null or w3 == null:
		return
	# 专属排期优先级高于通用池（见 gen_events.gd 的 WEEK_PRIORITY）
	_check("第 1 周挑到专属事件", String(w1.id), "class_discount")
	_check("第 2 周挑到专属事件", String(w2.id), "bad_film_offer")
	_check("第 3 周挑到专属事件", String(w3.id), "director_audition")
	# 【为什么连续挑两次】pick() 会被反复调用（每周初触发、界面刷新、读档重算），
	# 只要本周排好了就必须原样返回，否则会「刷新一次换一出戏」
	_check("重复挑还是同一条", String(EventScheduler.pick(s, 2).id), "bad_film_offer")
	print("   同一种子连续挑两次，结果一致（不会刷新一次换一出戏）")


func _test_conditions_and_pool() -> void:
	print("[3] 出现条件与通用池")
	var poor := _state()
	poor.money = 10
	var rich := _state()
	rich.money = 500
	var poor_pool := EventScheduler.candidates(poor, 4)
	var rich_pool := EventScheduler.candidates(rich, 4)
	# 第 4 周没有专属排期（游戏只有 3 周），所以这里挑的就是通用池
	_check("没钱时挑不出通用池的事件", EventScheduler.pick(poor, 4), null)
	_check("有钱时能挑到通用池里的事件", EventScheduler.pick(rich, 4) != null, true)
	_check("需钱 150：手里 10 块时被筛掉", poor_pool.size(), 0)
	_check("需钱 150：手里 500 块时留下", rich_pool.size(), 1)
	# 钱可以是负的（房租能扣成欠债），所以「需钱」的空档值必须是负数而不是 0
	var in_debt := _state()
	in_debt.money = -80
	_check("欠债玩家照样能看见无条件的事件", EventScheduler.candidates(in_debt, 1).size() > 0, true)
	print("   条件按「手里有多少钱」筛；无缝条件的事件对欠债玩家也开放")


func _test_repeat_rule() -> void:
	print("[4] 出现过的不再出现（可重复的除外）")
	var s := _state()
	s.money = 500
	s.seen_events.append("class_discount")
	# 第 1 周的专属已经出现过了 —— 通用池里那条可重复，所以还能顶上
	var pick := EventScheduler.pick(s, 1)
	_check("专属出现过后不再出现", String(pick.id) if pick != null else "", "friend_loan")
	# 【「可重复」就是为这种时候准备的】某几周没有专属事件时，池子里还得有东西能演
	s.seen_events.append("friend_loan")
	var repeat_pick := EventScheduler.pick(s, 1)
	# 用三元而不是直接读 .id：挑不到时读 .id 会中断整个函数，
	# 而中断是**不会让测试变红**的（见 [2] 里那道闸门的说明）
	_check("标了可重复的还能再顶上",
			repeat_pick.id if repeat_pick != null else &"（挑不到）", "friend_loan")
	# 条件不满足时才是真的没得演
	s.money = 10
	_check("候选全被筛掉时返回 null", EventScheduler.pick(s, 1), null)
	print("   缺席的周由通用池顶上；池子也用完则这一周没有事件")


func _test_action_point_gate() -> void:
	print("[5] 行动点花光之后")
	var s := _state()
	s.money = 500
	s.day = 8
	s.ap_left_today = 0
	s.pending_event = &"class_discount"
	# 选项A（买）收 1 点，选项B（不买）免费 —— GDD 的拒绝项都是免费的
	var a_reason := DailyActions.event_option_block_reason(s, 0)
	_check("收行动点的选项被拦", a_reason.is_empty(), false)
	_check("拦下时说明了原因（带数字）", a_reason.contains("行动点"), true)
	_check("免费选项仍然可以选", DailyActions.event_option_block_reason(s, 1), "")
	var r := DailyActions.resolve_event(s, 0)
	_check("硬选也拦得住（不只靠界面灰按钮）", r.get("ok", false), false)
	_check("被拦时状态没变", s.money, 500)
	_check("被拦时事件还挂着", s.has_pending_event(), true)
	print("   收点的选项被拦且写出原因；免费那条不受影响 —— 这一周不会被卡死")


func _test_resolve() -> void:
	print("[6] 处理一个事件")
	var s := _state()
	s.money = 500
	s.acting = 10
	s.day = 8
	s.ap_left_today = 1
	s.pending_event = &"class_discount"
	var r := DailyActions.resolve_event(s, 0)
	_check("处理成功", r.get("ok", false), true)
	_check("扣了 1 点行动点", s.ap_left_today, 0)
	_check("半价学费 50 扣掉", s.money, 450)
	_check("演技 +3", s.acting, 13)
	_check("事件不再挂着", s.has_pending_event(), false)
	_check("记进了「出现过」", s.has_seen_event(&"class_discount"), true)
	_check("写进了履历", s.event_history.size(), 1)
	_check("履历里是第几个选项", int(s.event_history[0]["choice"]), 0)
	_check("履历里带着周次", int(s.event_history[0]["week"]), 2)
	# 一周只演一出：处理完再挑，不应该再从通用池里捞一条出来
	_check("处理完本周不再排新事件", EventScheduler.pick(s, 2), null)
	# 免费选项也要能走通
	var s2 := _state()
	s2.money = 500
	s2.ap_left_today = 1
	s2.pending_event = &"class_discount"
	DailyActions.resolve_event(s2, 1)
	_check("选「不买」不花钱", s2.money, 500)
	_check("选「不买」不扣点", s2.ap_left_today, 1)
	print("   扣点、加减属性、进履历、清 pending；一周只演一出")


func _test_clamp() -> void:
	print("[7] 属性上下限")
	var bal := BalanceLibrary.data()
	var s := _state()
	s.acting = bal.acting_cap
	s.pending_event = &"class_discount"
	DailyActions.resolve_event(s, 0)
	_check("演技到顶后不再涨", s.acting, bal.acting_cap)
	var s2 := _state()
	s2.money = 500
	s2.fame = bal.fame_max
	s2.pending_event = &"friend_loan"
	DailyActions.resolve_event(s2, 0)
	_check("知名度到顶后不再涨", s2.fame, bal.fame_max)
	# 【为什么要单独验】DailyActions 不走 Game.add_*，夹上下限得自己来 ——
	# 少夹一次就会出现「演技刷到 30 之后接着涨」这种事
	print("   事件改属性时自己夹上下限（动作层不走 Game.add_*）")


func _test_miss() -> void:
	print("[8] 整周没理会")
	var s := _state()
	s.pending_event = &"director_audition"
	s.day = 7
	DailyActions.miss_pending_events(s)
	_check("pending 清掉了", s.has_pending_event(), false)
	_check("记了一笔「没理会」", int(s.event_history[0]["choice"]), -1)
	_check("也记进「出现过」", s.has_seen_event(&"director_audition"), true)
	# 【为什么非清不可】不清的话下一周的 pick 会因为「本周已排好」而把上一周那条端出来
	# （这里第 3 周能挑到通用池那条，但绝不能再挑到导演那条）
	var next_pick := EventScheduler.pick(s, 3)
	_check("上一周那条不会溜进下一周",
			next_pick != null and String(next_pick.id) == "director_audition", false)
	s.day = 8
	_check("第 2 周照样能排出自己的事件", EventScheduler.pick(s, 2) != null, true)
	# 没有待处理事件时调用是安全的（每周结算都会调一次）
	DailyActions.miss_pending_events(s)
	_check("没有挂起事件时调用不报错也不多记", s.event_history.size(), 1)
	print("   错过也会记一笔，并挡住下一周串台")


func _test_save_round_trip() -> void:
	print("[9] 存档往返")
	var s := _state()
	s.money = 500
	s.event_seed = 777
	s.pending_event = &"friend_loan"
	s.ap_left_today = 0
	s.seen_events.append("class_discount")
	s.event_history.append({"week": 1, "day": 3, "event": "class_discount",
			"speaker": "trainer", "choice": 0, "label": "买", "note": ""})

	# 走真实路径：to_save_dict → JSON 字符串 → 解析 → from_save_dict
	var json := JSON.stringify(s.to_save_dict())
	var parsed: Variant = JSON.parse_string(json)
	_check("存档能解析回来", typeof(parsed), TYPE_DICTIONARY)
	var back := GameState.new()
	back.from_save_dict(parsed)

	_check("种子还原", back.event_seed, 777)
	_check("挂着的事件还原", String(back.pending_event), "friend_loan")
	_check("出现过的事件还原", back.has_seen_event(&"class_discount"), true)
	_check("履历还原", back.event_history.size(), 1)
	_check("行动点还原", back.ap_left_today, 0)
	# 读档之后挑出来的必须还是同一出 —— 不然玩家会发现「上周那出戏」变了
	# 【pick 的前提是「这一周还没排过」】存档里那条 friend_loan 正挂着，
	# 不摘掉的话 `offered_count` 会把这一周算成已经排好、直接返回 null。
	# pending 本身上面验过了，这里要验的是「同种子挑出同一条」。
	s.pending_event = &""
	back.pending_event = &""
	# 【不能写 String(pick(...))】pick 的返回类型是 EventData，
	# String(EventData) 在**解析阶段**就报错（不是运行时）—— 先取出来再读 .id
	var before_pick := EventScheduler.pick(s, 3)
	var after_pick := EventScheduler.pick(back, 3)
	_check("两边都挑到了事件", before_pick != null and after_pick != null, true)
	if before_pick != null and after_pick != null:
		_check("读档后挑到的是同一条", String(after_pick.id), String(before_pick.id))
	print("   状态与「本周演哪一出」都能原样回来")


# ============================================================
func _state() -> GameState:
	var s := GameState.new()
	s.money = BalanceLibrary.data().init_money
	s.event_seed = 1234
	return s


func _check(label: String, got: Variant, want: Variant) -> void:
	_total += 1
	if got == want:
		return
	_failures.append("%s：期望 %s，实际 %s" % [label, var_to_str(want), var_to_str(got)])


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("✅ 共 %d 项断言，全部通过" % _total)
		quit(0)
	else:
		print("❌ %d 项失败：" % _failures.size())
		for f: String in _failures:
			print("   - " + f)
		quit(1)
