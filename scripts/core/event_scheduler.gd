class_name EventScheduler
extends RefCounted
## 周初事件的挑选规则 —— 回答「这一周该上演哪一出」
##
## 【对应 GDD 3.5「阶段1：周初（事件推送）」】
## 每周 **1~2 条**（10-17 定）：第 1 条在周一，第 2 条按计划落在第 2~5 天，
## 数量与日期都由种子派生。玩家在微信里读、可能做出选择。
##
## 【为什么抽签要可复现】与定角抽签同一个道理：读档回来如果重抽，
## 玩家会看到「上周那出戏」变成了另一出。所以种子取自 `state.event_seed`（开局抽一次），
## 按周派生 —— 同一局、同一周，任何时候抽到的都是同一条。
## 副作用是模拟器能复现整局，不用为此再加一层快照。
##
## 【这里只管「挑」，不管「收」】玩家选了之后的状态变更在 `DailyActions.resolve_event`，
## 数据长什么样在 `EventData`。三件事分开，改一个不用动另外两个。

## 派生种子用的乘数。取个质数，让相邻两周的种子不会撞在同一批候选上。
const WEEK_STRIDE := 7919

## 一周最多排几条。**1~2 之间由种子决定**（10-17 定），不是恒定两条。
const MAX_EVENTS_PER_WEEK := 2

## 第二条落在第 2~5 天（第 7 天是结算日，排在第 7 天等于没机会处理）。
const SECOND_DAY_MIN := 2
const SECOND_DAY_MAX := 5


## 这一周的计划：排几条、第二条落在第几天。
##
## 【只依赖种子和周次】读档、重进界面、模拟器复跑都必须得到同一份计划 ——
## 计划里一旦掺进「玩家处理没处理」，同一天读两次档就会看到两条变成一条。
static func week_plan(state: GameState, week: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = state.event_seed + week * WEEK_STRIDE
	var count := 1 + rng.randi_range(0, 1)
	var second_day := rng.randi_range(SECOND_DAY_MIN, SECOND_DAY_MAX)
	return {"count": count, "second_day": second_day}


## 本周已经排进来几条（挂着的 + 已处理/错过的都算）。
##
## 【为什么历史也要数】不然「处理掉第一条」会被当成「这周还没排过」，
## 于是第二天又从通用池里捞一条 —— 一周变成三条。
static func offered_count(state: GameState, week: int) -> int:
	var n := state.pending_events.size()
	for h: Dictionary in state.event_history:
		if int(h.get("week", -1)) == week:
			n += 1
	return n


## 这一周是否已经演过一出（处理掉的、错过的都算）。
static func had_event_in(state: GameState, week: int) -> bool:
	return offered_count(state, week) > 0


## **今天**该不该再排一条；该排就返回那件事，否则 null。
##
## 调用点在 `Game._roll_week_event()`（每天推进后都会调一次），所以这里
## 只回答「今天这一下要不要出东西」—— 不再是「本周那出戏是什么」。
##
## 两条的节奏（10-17 定「必须分散开」）：
##   · 第 1 条固定在周一（GDD 3.5 阶段 1：周初事件推送）
##   · 第 2 条按计划落在第 2~5 天的某一天，**不管第 1 条处理没处理都会来**
static func pick(state: GameState, week: int) -> EventData:
	if state.finished:
		return null
	var plan := week_plan(state, week)
	var offered := offered_count(state, week)
	if offered >= int(plan["count"]):
		return null
	var dod := state.day_of_week()
	if offered == 0:
		if dod != 1:
			return null
	elif dod < int(plan["second_day"]):
		return null

	var pool := candidates(state, week)
	if pool.is_empty():
		return null
	var top := _top_priority(pool)
	if top.size() == 1:
		return top[0]
	var rng := RandomNumberGenerator.new()
	# 第二条用不同的派生值，免得同一周两条抽到同一个"随机"结果
	rng.seed = state.event_seed + week * WEEK_STRIDE * 31 + offered
	return top[rng.randi_range(0, top.size() - 1)]


## 本周已经出过（或正挂着）的说话人。
## 【为什么一周不许同一个人来两次】会话是按「说话人」分组的：同一个人的两条事件
## 会挤进同一个聊天框，里面要同时挂两组二选一按钮 —— 点错、看不懂都从这里来。
static func speakers_in_week(state: GameState, week: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: String in state.pending_events:
		var ev := EventLibrary.find(StringName(id))
		if ev != null and not out.has(ev.speaker):
			out.append(ev.speaker)
	for h: Dictionary in state.event_history:
		if int(h.get("week", -1)) != week:
			continue
		var sp := StringName(h.get("speaker", ""))
		if sp != &"" and not out.has(sp):
			out.append(sp)
	return out


## 这一周的候选池（已按周次 / 出现条件 / 是否出现过 / 本周说过话的人 筛过）。
## 公开是为了让测试与工具能看到「为什么这周挑了它」。
static func candidates(state: GameState, week: int) -> Array[EventData]:
	var used := speakers_in_week(state, week)
	var out: Array[EventData] = []
	for e: EventData in EventLibrary.book().entries:
		if e == null:
			continue
		if e.week != 0 and e.week != week:
			continue
		if not e.repeatable and state.has_seen_event(e.id):
			continue
		if used.has(e.speaker):
			continue
		if e.require_money_min >= 0 and state.money < e.require_money_min:
			continue
		if e.require_acting_min >= 0 and state.acting < e.require_acting_min:
			continue
		out.append(e)
	return out


## 同优先级里挑最高的一组。
## 【为什么用优先级而不是「手写 vs 模板」两套机制】手写的那几周是**指定内容**
## （那一周就该演那一出），模板事件是池子 —— 用同一个字段就把两者装下了。
static func _top_priority(pool: Array[EventData]) -> Array[EventData]:
	var best := -2147483648
	for e: EventData in pool:
		best = maxi(best, e.priority)
	var out: Array[EventData] = []
	for e: EventData in pool:
		if e.priority == best:
			out.append(e)
	return out
