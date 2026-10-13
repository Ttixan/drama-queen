class_name EventScheduler
extends RefCounted
## 周初事件的挑选规则 —— 回答「这一周该上演哪一出」
##
## 【对应 GDD 3.5「阶段1：周初（事件推送）」】
## 每周开头触发一个事件（原文：「随机或条件」），玩家在微信里读、可能做出选择。
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


## 这一周该上演的事件。挑不出来返回 null（内容没配 / 条件不满足 / 全都出现过了）。
##
## 【为什么第一句是「已经有了就直接给」】本方法会被反复调用（每周初触发一次、
## 界面刷新、读档后重算）。只要本周已经排出过，就必须原样返回 ——
## 否则「读一次档换一出戏」这种 bug 会以最难查的方式出现。
static func pick(state: GameState, week: int) -> EventData:
	if state.has_pending_event():
		return EventLibrary.find(state.pending_event)
	# 【一周只演一出】本周已经处理过（或错过）一个事件就到此为止 ——
	# 否则处理完再挑一次会从通用池里捞出第二个，一周演两出。
	if had_event_in(state, week):
		return null
	var pool := candidates(state, week)
	if pool.is_empty():
		return null
	var top := _top_priority(pool)
	if top.size() == 1:
		return top[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = state.event_seed + week * WEEK_STRIDE
	return top[rng.randi_range(0, top.size() - 1)]


## 这一周是否已经演过一出（处理掉的、错过的都算）。
## 【为什么看历史而不是新加一个 bool】历史里本来就带着 week，
## 再存一个「本周排过没有」的字段，就多了一处可能不同步的状态。
static func had_event_in(state: GameState, week: int) -> bool:
	for h: Dictionary in state.event_history:
		if int(h.get("week", -1)) == week:
			return true
	return false


## 这一周的候选池（已按周次 / 出现条件 / 是否出现过筛过）。
## 公开是为了让测试与工具能看到「为什么这周挑了它」。
static func candidates(state: GameState, week: int) -> Array[EventData]:
	var out: Array[EventData] = []
	for e: EventData in EventLibrary.book().entries:
		if e == null:
			continue
		if e.week != 0 and e.week != week:
			continue
		if not e.repeatable and state.has_seen_event(e.id):
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
