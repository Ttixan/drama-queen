class_name SimRunner
extends RefCounted
## 跑一局完整的 21 天 —— 数值模拟器与它的测试**共用这一份代码**
##
## 【为什么不写在 simulate.gd 里】那样测试就得自己再抄一遍"怎么跑一局"，
## 而**测试跑的其实是另一套代码**正是这个项目已经吃过一次的亏
## （见 `进度.md`：结算浮层的脚本解析失败时，断言全绿，实际全假）。
##
## 【它走的是真实路径】投递/打工/上课走 `DailyActions`，结算走 `WeekCycle.settle`，
## 与游戏本体是同一份函数 —— 只有"谁来做决定"换成了 agent。
##
## 【它绕开了什么】`Game`（Node 壳）与 `EventBus`。这两样都只负责发信号，
## 不影响任何数值。数值模拟器不加载场景树就能跑，靠的就是这条边界。

const CODES: Array[String] = ["A", "B", "C", "D", "E"]


## 开局把五家公司的招聘页都逛一遍。
## 【为什么连随机 agent 也享受这个待遇】浏览 Boss直聘 **不花行动点**（它是只读的），
## 任何一个打开过 App 的玩家都会顺手点完五家。不解锁的话，模拟器测出来的
## 会是「一个从没打开过 App 的玩家」—— 那个数字对平衡没有任何指导意义。
static func unlock_all(state: GameState) -> void:
	for code: String in CODES:
		state.unlock_hr(code)


## 跑一局。可复现性完全来自 `agent` 自己的随机种子
## （定角抽签的种子由 `state.day` 与投递序号推出，本来就确定）。
static func run_one(agent: SimAgent) -> Dictionary:
	var bal := BalanceLibrary.data()
	var state := GameState.new()
	state.money = bal.init_money
	state.acting = bal.init_acting
	unlock_all(state)

	var ap := {SimAgent.Action.SUBMIT: 0, SimAgent.Action.WORK: 0,
			SimAgent.Action.CLASS: 0, SimAgent.Action.IDLE: 0}
	var by_company := {}
	# 投递那一刻手上的演技最高到过多少 —— 公司演技门槛就是拿它去比的
	var stats := {"max_acting_at_submit": 0}

	# 【必须走 advance_day()，不能自己改 state.day】跨周清零（每周的投递 / 打工 / 上课
	# 计数）与行动点恢复都写在 `GameState.advance_day()` 里。绕开它的话，第一周投满
	# 4 次之后**后面两周再也投不出去** —— 而报告只会显示「玩家好像不太爱投递」。
	# 顺序也照抄 `Game.end_day()`：先在周末当天结算，再推进到第二天。
	for week in GameState.WEEKS:
		for d in GameState.DAYS_PER_WEEK:
			ap[take_action(agent, state, by_company, stats)] += 1
			if state.is_week_end():
				WeekCycle.settle(state, state.week())
			state.advance_day()

	return {
		"ending": String(state.ending_id),
		"finished": state.finished,
		"money": state.money,
		"acting": state.acting,
		"fame": state.fame,
		"rep": state.reputation,
		"ps5_off": Economy.ps5_paid_off(state),
		"ap": ap,
		"by_company": by_company,
		"max_acting_at_submit": stats["max_acting_at_submit"],
		"successes": state.successes_total,
	}


## 执行 agent 的决定，返回**实际发生**的动作。
##
## 【为什么返回实际值而不是它想做的】行动点去向表要回答「这 21 天都花在哪」。
## agent 想投递但被拦下来（没行动点、超周上限）时，那一天是真的白过了 ——
## 记成「投递」会把这笔账算错，而"某一天白过了"恰恰是设计上要看的东西。
static func take_action(agent: SimAgent, state: GameState, by_company: Dictionary,
		stats: Dictionary) -> int:
	var decision := agent.decide(state)
	match int(decision.get("action", SimAgent.Action.IDLE)):
		SimAgent.Action.SUBMIT:
			var co: CompanyData = decision["company"]
			var role: RoleRequirement = decision["role"]
			stats["max_acting_at_submit"] = maxi(int(stats["max_acting_at_submit"]), state.acting)
			var res := DailyActions.submit(state, agent.make_clip(co), co, role)
			if res.get("rejected", true):
				return SimAgent.Action.IDLE
			var key := "%s-%s" % [co.code, RoleRequirement.TIER_NAMES[role.tier]]
			if not by_company.has(key):
				by_company[key] = {"n": 0, "pass": 0}
			by_company[key]["n"] += 1
			if res["passed"]:
				by_company[key]["pass"] += 1
			return SimAgent.Action.SUBMIT
		SimAgent.Action.WORK:
			return SimAgent.Action.WORK if DailyActions.work(state).get("ok", false) \
					else SimAgent.Action.IDLE
		SimAgent.Action.CLASS:
			return SimAgent.Action.CLASS if DailyActions.take_class(state).get("ok", false) \
					else SimAgent.Action.IDLE
	return SimAgent.Action.IDLE
