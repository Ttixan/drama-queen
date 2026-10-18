class_name WeekCycle
extends RefCounted
## 周末结算 —— 把「这一周投出去的东西」变成「实际到手的钱与名声」
##
## 【为什么不能写在 Game（Node）里】数值模拟器要跑几千局、每局三次结算，
## 逻辑一旦绑上场景树就跑不动了。Game 只负责把结果转成信号。
##
## 【结算顺序，每一步都有理由】
##   1. 先算本周播出的戏 —— 拿到片酬，才有钱交房租与分期
##   2. 房租：**可以直接扣成负数**，这就是「欠债 = 金钱 < 0」的唯一起源
##   3. PS5 分期：付得出就付，付不出记逾期 + 风评惩罚，**不扣钱** ——
##      「逾期」的含义是这笔钱没交出去，同时扣钱又记逾期等于一罚两遍
##   4. 电子报：必须等账算完。同一期报纸上称呼是**统一**的，
##      不会出现前半版写「男主」、后半版写玩家名
##   5. 结局：只在第 21 天判定
##
## 【为什么中途不提前结束】「被解雇」看起来像能提前触发的结局，但它是
## **第 21 天的状态判定**，不是中途事件。中途结束会让「21 天」这个骨架白立，
## 而且玩家会失去补救欠债的机会 —— 而钱能欠、行动点不能，本来就是设计的一部分。


## 本周播出的作品。**只算成功的** —— 没通过试镜就没有作品，也就没有播出。
## 【为什么按 day 区间筛而不是记「本周投递列表」】history 本来就带 day，
## 多存一份列表就多一个会读档读丢的东西。
static func plays_of_week(state: GameState, week: int) -> Array[Dictionary]:
	var lo := (week - 1) * GameState.DAYS_PER_WEEK + 1
	var hi := week * GameState.DAYS_PER_WEEK
	var out: Array[Dictionary] = []
	for h: Dictionary in state.history:
		var d := int(h.get("day", 0))
		if d >= lo and d <= hi and bool(h.get("passed", false)):
			out.append(h)
	return out


## 结算第 `week` 周，**直接改 state**，并返回一份完整周报。
## 界面只需要读周报，不需要自己再算一遍。
static func settle(state: GameState, week: int) -> Dictionary:
	var bal := BalanceLibrary.data()
	var before := snapshot(state)
	var report := {
		"week": week,
		"day": state.day,
		"plays": [],
		"headlines": [],
		"payout": 0, "acting_gain": 0, "fame_gain": 0, "rep_gain": 0, "neg_gain": 0,
		"rent": 0,
		"ps5_due": 0, "ps5_paid": 0, "ps5_overdue": false, "ps5_penalty": 0,
		"black_fame": false,
		"before": before,
		"after": {},
		"ending": {},
	}

	# ---- 1. 本周播出的作品 ----
	var plays: Array[Dictionary] = []
	# 【知名度要逐部推进】「无知名度的龙套」是动态状态：同一周里先靠一部主角戏出了名，
	# 后面那个龙套低分就会被观众注意到。用周一早上的知名度一刀切会把顺序抹平。
	var fame_before := state.fame
	for entry: Dictionary in plays_of_week(state, week):
		var res := Broadcast.evaluate(entry, fame_before)
		res["entry"] = entry
		state.money += int(res["payout"])
		state.acting = mini(state.acting + int(res["acting_gain"]), bal.acting_cap)
		state.fame = clampi(state.fame + int(res["fame"]), 0, bal.fame_max)
		state.reputation = clampi(state.reputation + int(res["rep"]), bal.rep_min, bal.rep_max)
		state.negative_exposure += int(res["neg"])
		# 下一部要用夹过之后的知名度当基准，否则夹紧生效时逐部累计会偏
		fame_before = state.fame
		plays.append(res)

	var totals := Broadcast.total(plays)
	report["plays"] = plays
	report["payout"] = totals["payout"]
	report["acting_gain"] = totals["acting"]
	report["fame_gain"] = totals["fame"]
	report["rep_gain"] = totals["rep"]
	report["neg_gain"] = totals["neg"]

	# ---- 4a. 电子报头条（放在账算完之后，理由见文件头）----
	for p: Dictionary in plays:
		var hl := HeadlineComposer.compose(p, state, state.fame)
		p["headline"] = hl.text
		p["headline_id"] = hl.id
		if not String(hl.text).is_empty():
			(report["headlines"] as Array).append(hl.text)

	# ---- 2. 房租 ----
	var rent := Economy.rent()
	state.money -= rent
	report["rent"] = rent

	# ---- 3. PS5 分期 ----
	# 【为什么还要判一次付清】正常玩法下 ps5_paid 只可能由这三次结算累加，
	# 但读档、调数值、或者将来的「补交分期」都可能把它先填满 ——
	# 那时候再扣一次就等于从玩家口袋里多拿 135 元。
	var due := Economy.ps5_due_for_week(week)
	if due > 0 and not Economy.ps5_paid_off(state):
		report["ps5_due"] = due
		if state.money >= due:
			state.money -= due
			state.ps5_paid += due
			report["ps5_paid"] = due
		else:
			report["ps5_overdue"] = true
			var penalty: int = bal.ps5_overdue_rep_penalty
			state.reputation = clampi(state.reputation - penalty, bal.rep_min, bal.rep_max)
			report["ps5_penalty"] = penalty

	# ---- 4b. 黑红：负面曝光累计够了，就有一条微博标题 ----
	# 【不是成就系统】GDD 边界写明「绝对不做成就」，所以它只是一条标题。
	# 「首次」与「重复」两句文案不同 —— 第一次是惊奇，之后是嫌烦。
	if state.negative_exposure >= bal.black_fame_threshold:
		var repeat := state.black_fame_seen
		if not repeat or int(report["neg_gain"]) > 0:
			var hl := HeadlineComposer.compose_black_fame(state, repeat)
			if not String(hl.text).is_empty():
				(report["headlines"] as Array).append(hl.text)
			report["black_fame"] = true
			state.black_fame_seen = true

	# 【复杂表情的奖励不在这里】它在「推进到新的一天」时发牌（`GameState.queue_expression_rewards`
	# 由 `Game._advance` 调用）—— 玩家按「下一天」就看见翻牌，而不是等一周的报纸。

	# ---- 5. 结局 ----
	if week >= GameState.WEEKS:
		report["ending"] = EndingResolver.resolve(state)
		state.ending_id = StringName(report["ending"].get("id", &""))
		state.finished = true

	report["after"] = snapshot(state)
	state.reports.append(trim(report))
	return report


## 周报的**存档版**：剔掉逐条作品的 `entry`（那是履历的原文，history 里已经有一份），
## 否则每期周报都要把整封邮件再存一次，三周下来存档会大一倍。
static func trim(report: Dictionary) -> Dictionary:
	var out := report.duplicate()
	var plays: Array[Dictionary] = []
	for p: Dictionary in report.get("plays", []):
		var q := p.duplicate()
		q.erase("entry")
		plays.append(q)
	out["plays"] = plays
	out.erase("before")
	out.erase("after")
	return out


## 结算前后的关键数字快照 —— 周报要能显示「这周从 200 变成了 265」
static func snapshot(state: GameState) -> Dictionary:
	return {
		"money": state.money,
		"acting": state.acting,
		"fame": state.fame,
		"reputation": state.reputation,
		"neg": state.negative_exposure,
	}


## 这一期分期在第几天到期（界面用）。已经付清返回 0。
##
## 【为什么按「本周最后一天」算而不是按已付期数推】逾期的那一期不会被补交，
## 所以「已付 2 期」并不能推出「下次是第 3 期」—— 按当前周推才是对的。
static func next_installment_day(state: GameState) -> int:
	if Economy.ps5_paid_off(state):
		return 0
	return state.week() * GameState.DAYS_PER_WEEK
