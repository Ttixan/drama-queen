extends Node
## Game 单例（Autoload 名：Game）
##
## 【架构约束】这是个**壳**，只做两件事：持有 GameState、把状态变更转成 EventBus 信号。
## 判定、经济、周流程的逻辑一律写在 GameState / AuditionResolver / Economy 里，
## 那些类全部是 RefCounted、不继承 Node —— 数值模拟器要能脱离场景树 headless 跑。
## **不要**往这个文件里加任何计算逻辑。

var state: GameState


func _ready() -> void:
	# 「该存档了」的广播由本单例自己接住 —— 这样结算流程（WeekCycle 的调用方）
	# 不必知道存档文件在哪，将来加「手动存档按钮」也只是再 emit 一次。
	EventBus.save_requested.connect(_on_save_requested)

	# 录像机录完那段表情包也由本单例接住（理由见 `_on_recorder_finished`）
	EventBus.recorder_finished.connect(_on_recorder_finished)

	# 【开局先试着读档】决策 1.1 只说了「每周结算自动存档」——
	# **存了却没人读，那份存档就是死的**。读不到（第一次玩 / 文件坏了 / 格式对不上）
	# 才开新局，所以这里不需要额外的"有没有存档"判断。
	#
	# 【为什么必须在 _ready 里读】手机壳会在它自己的 `_ready()` 里读 `Game.state` 建界面，
	# 而 autoload 的 `_ready()` 先跑 —— 存档必须在那之前就位，否则界面建的是空局，
	# 玩家要等下一次刷新才会看到自己的进度。
	if not load_from():
		new_game()


## 开新局。两个参数传 -1 = 用数值表里的起始值（`data/balance.tres`）。
## 【为什么保留覆盖参数】工具与测试要能造「开局就有一千块」的局面，
## 而不用先跑十二天打工把状态凑出来。
func new_game(init_money: int = -1, init_acting: int = -1) -> void:
	var bal := BalanceLibrary.data()
	state = GameState.new()
	state.money = bal.init_money if init_money < 0 else init_money
	state.acting = bal.init_acting if init_acting < 0 else init_acting
	# 【为什么随机种子在开局抽、之后再也不抽】事件每周要挑一次，而挑出来的
	# 会被玩家看到（「这周找上门的是谁」）。读档重抽就会换一出戏 ——
	# 与定角抽签同一个道理：抽一次，之后谁都读同一份，模拟器也能复现整局。
	state.event_seed = randi()
	# 第 1 天就是第 1 周的第一天，所以这里要排一次
	_roll_week_event()
	EventBus.ap_changed.emit(state.ap_left_today)
	# 放在最后：界面收到它时，新状态已经就位，可以放心照着重画
	EventBus.state_reset.emit()


# ============================================================
# 只读访问 —— 界面用这些，不要直接改 state
# ============================================================
func money() -> int:
	return state.money


func acting() -> int:
	return state.acting


func fame() -> int:
	return state.fame


func reputation() -> int:
	return state.reputation


func day() -> int:
	return state.day


func week() -> int:
	return state.week()


func ap_left() -> int:
	return state.ap_left_today


func can_submit() -> bool:
	return state.can_submit()


func submissions_left_this_week() -> int:
	return maxi(0, GameState.MAX_SUBMIT_PER_WEEK - state.submissions_this_week)


## PS5 已付累计（界面显示「进度 2/3」用）
func ps5_paid() -> int:
	return state.ps5_paid


func ps5_paid_off() -> bool:
	return Economy.ps5_paid_off(state)


# ============================================================
# 待投递的表情包 + 微信该打开哪位联系人
# ============================================================
# 【为什么这两样要放在 Game 层】它们都是**跨 App 的中间状态**：录像机录完要交给微信，
# 而录像机与微信不会同时活着（手机屏一次只开一个 App，切走就把上一个销毁）。
# 界面之间不互相递东西（决策：App 只发信号、不知道别家住在哪儿），所以得有个
# 两边都认的地方 —— 就是状态层。
func pending_clip() -> Clip:
	return state.pending_clip


func set_pending_clip(clip: Clip) -> void:
	state.pending_clip = clip


## 投出去（或重开一局）之后清掉。表情包一次性消耗，决策 1.6。
func clear_pending_clip() -> void:
	state.pending_clip = null


## 微信该打开哪位联系人。界面只读，写入口是下面这个与 `unlock_hr()`
func focus_hr() -> String:
	return state.focus_hr


func set_focus_hr(code: String) -> void:
	state.focus_hr = code


func ending_id() -> StringName:
	return state.ending_id


# ============================================================
# 属性变更 —— 改值 + 发信号，成对出现
# ============================================================
# 【为什么这里要夹取值范围】名气与风评都有上下限（数值表 5），
# 而累加发生在好几个地方（结算、事件、惩罚）。夹在唯一的写入口上，
# 就不会出现「某条路径忘了夹」的漏网之鱼。
# 【为什么夹完要发**实际**增量】界面上的 "+3" 跳字读的是 delta。
# 只差 1 点到顶时发 +3，玩家会看到数字没跟上跳字，像是卡了。
func add_money(delta: int) -> void:
	state.money += delta
	_notify_money(delta)


func add_acting(delta: int) -> void:
	var cap: int = BalanceLibrary.data().acting_cap
	var before := state.acting
	state.acting = clampi(state.acting + delta, 0, cap)
	_notify_acting(state.acting - before)


func add_fame(delta: int) -> void:
	var bal := BalanceLibrary.data()
	var before := state.fame
	state.fame = clampi(state.fame + delta, 0, bal.fame_max)
	_notify_fame(state.fame - before)


func add_reputation(delta: int) -> void:
	var bal := BalanceLibrary.data()
	var before := state.reputation
	state.reputation = clampi(state.reputation + delta, bal.rep_min, bal.rep_max)
	_notify_reputation(state.reputation - before)


## 【为什么要把「改值」和「通知」拆开】`DailyActions` 是唯一改状态的地方
## （模拟器也得走它）。所以 Game 这边只剩通知 —— 再调一次 `add_money()`
## 会把同一个增量**加两遍**，而且表面上完全看不出来。
## 这两个函数就是给那种场景用的：值已经改好了，只需要让界面知道。
func _notify_money(delta: int) -> void:
	if delta != 0:
		EventBus.money_changed.emit(state.money, delta)


func _notify_acting(delta: int) -> void:
	if delta != 0:
		EventBus.acting_changed.emit(state.acting, delta)


func _notify_fame(delta: int) -> void:
	if delta != 0:
		EventBus.fame_changed.emit(state.fame, delta)


func _notify_reputation(delta: int) -> void:
	if delta != 0:
		EventBus.reputation_changed.emit(state.reputation, delta)


# ============================================================
# HR 解锁（决策 12：先在 Boss直聘 逛过该公司，微信里才解锁它的 HR）
# ============================================================
## 返回 true 表示这次是新解锁的
func unlock_hr(code: String) -> bool:
	if not state.unlock_hr(code):
		return false
	# 【刚加上的人优先】玩家在「简历拿来」跟 HR 聊完，回来多半就是想跟他说话。
	# 原来这一步是微信自己做的（`hr_unlocked` 一响就直接打开那位）—— 但现在微信
	# 那一刻并不活着（他从微信整屏跳去了简历拿来），所以这件事得落在状态上，
	# 由微信下次建起来时读（见 `wechat_app.gd` 的 `_ready`）。
	state.focus_hr = code
	EventBus.hr_unlocked.emit(code)
	return true


func is_hr_unlocked(code: String) -> bool:
	return state.is_hr_unlocked(code)


## 打开过这位 HR 的会话 = 他的未读清掉（微信在选联系人时调）
func mark_hr_read(code: String) -> void:
	state.mark_hr_read(code)


## 手机上那个微信图标该亮什么数字：未处理事件 + 未读 HR
func wechat_badge_count() -> int:
	return state.pending_events.size() + state.unread_hrs.size()


## 玩家在「初次沟通」里挑的那句（第 `run` 组选项的第几句）。见 `GameState.hr_choice`
func set_hr_choice(code: String, run: int, index: int) -> void:
	state.set_hr_choice(code, run, index)


func hr_choice_of(code: String, run: int) -> int:
	return state.hr_choice_of(code, run)


# ============================================================
# 剧本（HR 发的那份 .docx）
# ============================================================
## 这家 HR 手上那份剧本：`{"play": 1, "tier": 0}`。**空字典 = 还没要过 / 已经拍完**
func hr_script_of(code: String) -> Dictionary:
	return state.hr_script_of(code)


## 在聊天里点一个档位 = 跟 HR 要一份剧本。返回抽中的那份；发不出来时 null。
## 【规则不在这里】校验与抽签在 `DailyActions.request_script`（纯 RefCounted，模拟器可调）
func request_script(company: CompanyData, tier: int) -> ScriptDoc:
	return DailyActions.request_script(state, company, tier)


## 这一份拍完了 —— HR 接着问下一部。由界面在投递成功后调。
func clear_hr_script(code: String) -> void:
	state.clear_hr_script(code)


# ============================================================
# 投递
# ============================================================
## 一次投递。
##
## 【规则不在这里】校验、扣行动点、判定、定角抽签、记履历全在
## `scripts/core/daily_actions.gd` —— 那里是纯 RefCounted，数值模拟器不加载场景树也能调。
## 本函数只做一件事：把结果转成信号。
func submit_audition(clip: Clip, company: CompanyData, role: RoleRequirement) -> Dictionary:
	var result := DailyActions.submit(state, clip, company, role)
	if result.get("rejected", true):
		return result

	# 表情包一次性消耗 —— 记进履历供电子报的「标题调用条件」判定过往经历
	EventBus.clip_recorded.emit(result["clip_summary"], result["labels"])
	EventBus.ap_changed.emit(state.ap_left_today)
	EventBus.audition_submitted.emit(result)
	EventBus.hr_replied.emit(company.code, result["passed"], result)

	return result


# ============================================================
# 打工 / 表演课（即时到账，不走周末结算）
# ============================================================
## 【规则同样不在这里】见 `daily_actions.gd`。这两个包装只负责把结果转成信号。
func work() -> Dictionary:
	var r := DailyActions.work(state)
	if r.get("ok", false):
		_notify_money(int(r["income"]))
		EventBus.ap_changed.emit(state.ap_left_today)
	return r


## 上一次表演课
func take_class() -> Dictionary:
	var money_before := state.money
	var acting_before := state.acting
	var r := DailyActions.take_class(state)
	if r.get("ok", false):
		# 【为什么用差值而不是再算一次】夹了演技上限之后，实际涨的不一定是 class_gain ——
		# 界面上的 "+3" 跳字必须读**真实发生**的增量
		_notify_money(state.money - money_before)
		_notify_acting(state.acting - acting_before)
		EventBus.ap_changed.emit(state.ap_left_today)
	return r


# ============================================================
# 周初事件（第四个动作）
# ============================================================
## 本周等着处理的事件（最早那一条）。没有就返回 null —— 界面拿它决定微信里显不显示。
func pending_event() -> EventData:
	return DailyActions.pending_event(state)


## 本周挂着的全部事件（1~2 条）。手机左栏的角标、微信名单都读它。
func pending_events() -> Array[EventData]:
	return DailyActions.pending_events(state)


## 某个说话人手里还等着回话的那件事（微信按说话人分会话，一周内最多一条）
func pending_event_for(speaker: StringName) -> EventData:
	return DailyActions.pending_event_for(state, speaker)


## 这个选项现在能不能选？"" = 可以。界面拿它把按钮灰掉并写明原因。
func event_option_block_reason(index: int, event_id: StringName = &"") -> String:
	return DailyActions.event_option_block_reason(state, index, event_id)


## 玩家在微信里选了第几个选项。规则在 `daily_actions.gd`，这里只把结果转成信号。
##
## 【event_id 为什么必须显式传】一周可能挂着两条，index 只说明「第几个选项」——
## 不传就是「回最早那条」，那是给旧调用方（测试、模拟器）留的默认。
func resolve_event(index: int, event_id: StringName = &"") -> Dictionary:
	# 状态快照要在调用**之前**取：DailyActions 会直接改 state
	var money_before := state.money
	var acting_before := state.acting
	var fame_before := state.fame
	var rep_before := state.reputation
	# 同理，事件 id 也要先记下来 —— 处理完它就从 pending 里被摘掉了
	var picked_id := event_id
	if picked_id == &"":
		picked_id = state.pending_event

	var r := DailyActions.resolve_event(state, index, picked_id)
	if not r.get("ok", false):
		return r

	# 【为什么全用差值】选项里的数字会被上下限夹住（演技到顶、风评触底），
	# 界面上的 "+3" 跳字必须读**真实发生**的增量（与 take_class 同一个理由）
	_notify_money(state.money - money_before)
	_notify_acting(state.acting - acting_before)
	_notify_fame(state.fame - fame_before)
	_notify_reputation(state.reputation - rep_before)
	EventBus.ap_changed.emit(state.ap_left_today)
	EventBus.week_event_resolved.emit(picked_id, index)
	return r


# ============================================================
# 时间推进 + 周末结算
# ============================================================
## 结束今天 —— 玩家在手机壳桌面上按的那个按钮。
##
## 【为什么结算不写在 advance_day 里】`GameState.advance_day()` 是纯状态推进，谁都能调；
## 它是结算的**触发器**，不是结算本身。混在一起的话，数值模拟器想「只推进不结算」
## 就做不到了。所以：结束今天 → 若今天是本周最后一天就先结算 → 再推进。
##
## 返回 {settled: bool, report: Dictionary}
func end_day() -> Dictionary:
	if state.finished:
		return {"settled": false, "report": {}}

	if state.is_week_end():
		# 【为什么要在结算前先料理事件】没处理的事件若跟着状态溜进下一周，
		# `EventScheduler.pick` 会因为它还挂着而把**上一周**那条端出来 ——
		# 玩家会觉得事件赖着不走。所以周一到头就记一笔「没理会」再清掉。
		DailyActions.miss_pending_events(state)
		var report := WeekCycle.settle(state, state.week())
		EventBus.week_settled.emit(report)
		EventBus.broadcast_published.emit(state.week(), report.get("headlines", []))
		if report.get("black_fame", false):
			EventBus.black_fame_triggered.emit()
		if state.finished:
			EventBus.game_finished.emit(state.ending_id)
		# 每周结算自动存档（决策 1.1）。发信号而不是直接写文件 ——
		# 「什么时候存档」和「存到哪个文件」是两件事，后者归 _on_save_requested。
		EventBus.save_requested.emit()
		# 【第 21 天不再推进】day 会被夹在 21 上，is_week_end() 永远为真，
		# 靠 state.finished 挡住重复结算（见 GameState.advance_day 的注释）
		if not state.finished:
			_advance()
		return {"settled": true, "report": report}

	_advance()
	return {"settled": false, "report": {}}


func _advance() -> void:
	state.advance_day()
	EventBus.ap_changed.emit(state.ap_left_today)
	EventBus.day_advanced.emit(state.day, state.week())
	_roll_week_event()


## 排事件：**每天推进后都问一次**「今天要不要出东西」。
##
## 【为什么不再写 `day_of_week() != 1` 就返回】一周 1~2 条、且第二条要落在
## 第 2~5 天（10-17 定「必须分散开」），所以「今天是哪天」这条判断下沉到
## `EventScheduler.pick` 里 —— 那里同时知道本周的计划和已经排了几条。
##
## 【为什么挂在推进之后，而不是结算之前】GDD 的阶段顺序是
## 周初事件 → 周中行动 → 周末结算。事件属于**新一周的第一天**，
## 结算是**上一周的最后一天** —— 同一次「结束今天」里，两件事分属两周。
func _roll_week_event() -> void:
	if state.finished:
		return
	var ev := EventScheduler.pick(state, state.week())
	if ev == null:
		return
	state.add_pending_event(ev.id)
	EventBus.week_event_offered.emit(ev.id)


func _on_save_requested() -> void:
	var err := save_to()
	if err != OK:
		push_error("[Game] 自动存档失败：%s" % error_string(err))


## 录像机录完一段（`EventBus.recorder_finished`）—— 接住它的是**核心层**。
##
## 【为什么不是微信接】决策写着录像机只发信号、不认识公司也不认识微信；而微信那一刻
## 可能根本不在场（他从微信整屏跳去了录像机，微信已被手机屏销毁）。
## 所以这里只做一件事：把它存进状态。微信下次建起来时自己会取（见 `_ready`）。
func _on_recorder_finished(clip: Clip) -> void:
	set_pending_clip(clip)


# ============================================================
# 存档（每周结算时调用）
# ============================================================
func save_to(path: String = "user://save.json") -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(state.to_save_dict(), "\t"))
	f.close()
	return OK


func load_from(path: String = "user://save.json") -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	# 【为什么在这里新建 GameState，而不是往已有实例里灌】
	# 1. `_ready()` 会在 `new_game()` **之前**调本函数，那一刻 `state` 还是 null ——
	#    往 null 上调 `from_save_dict()` 会报错，而**报错只会中断本函数**，
	#    于是 `load_from()` 返回 null（falsy）、`_ready()` 转身开新局：
	#    表现就是「读档静默失效」。这个坑 Day 2 真踩过一次。
	# 2. 语义上也该如此：读档是「用存档造一份状态」，不是「往旧状态里覆盖」——
	#    后者会留下没被覆盖到的字段（上一局的残留）。
	state = GameState.new()
	state.from_save_dict(parsed)
	EventBus.ap_changed.emit(state.ap_left_today)
	# 读档对界面来说和开新局一样：状态整个换了，必须照着重画
	EventBus.state_reset.emit()
	return true
