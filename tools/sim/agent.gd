class_name SimAgent
extends RefCounted
## 数值模拟器里的「玩家」—— 每天做一个决定
##
## 【为什么要有两种极端】随机 agent 给出**下界**（完全不学，乱拼乱投），
## 贪心 agent 给出**上界**（读懂线索、算得清账）。两者之间的差距就是
## **学习成本的量化** —— 差距越大，说明隐藏公式越难，越需要更强的反馈（风险表第 10 条）。
## 当然，真实玩家在两者之间，所以贪心那边还要扫一遍「手潮程度」。
##
## 【agent 为什么只「决定」不改状态】执行统一由 `tools/simulate.gd` 走
## `DailyActions` / `WeekCycle` 这些**真实路径**。agent 一旦能自己改状态，
## 它测出来的就不是这个游戏了。

enum Action { SUBMIT, WORK, CLASS, IDLE }

const ACTION_NAMES := {
	Action.SUBMIT: "投递",
	Action.WORK: "打工",
	Action.CLASS: "上课",
	Action.IDLE: "闲置",
}

## 每帧有多大概率被「挑错一个部件」。0 = 手不抖，1 = 基本全错。
## 【为什么用「挑错一个槽位」而不是「整段重拼」】真实的失误是**零散**的：
## 线索读懂了、大方向对，只是某一帧的眉毛选错了。整段重拼测的是「完全没懂」，
## 那是随机 agent 的职责。
var sloppiness := 0.0

var rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0, p_sloppiness: float = 0.0) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	sloppiness = p_sloppiness


## 决定今天做什么。返回 {action: Action, company: CompanyData, role: RoleRequirement}
func decide(_state: GameState) -> Dictionary:
	return {"action": Action.IDLE}


## 造出今天的表情包。**只在走投递时才会被调用** ——
## 在录像机里拼表情包不花行动点（决策 1.1：行动点只花在投递/打工/上课/事件上）。
func make_clip(_company: CompanyData) -> Clip:
	return null


static func _part(slot: int, rng: RandomNumberGenerator) -> PartData:
	var opts := PartLibrary.by_slot(slot)
	if opts.is_empty():
		return null
	return opts[rng.randi_range(0, opts.size() - 1)]


static func _extra(rng: RandomNumberGenerator) -> PartData:
	var opts := PartLibrary.slot_options(PartData.Slot.EXTRA)
	return opts[rng.randi_range(0, opts.size() - 1)]


# ============================================================
# 随机玩家：什么都不知道，从零开始玩
# ============================================================
## 【它测的是下界】不读线索、不算账、拼表情包靠瞎点。
## 它给出的数字回答一个很重要的问题：**这个游戏会不会白送玩家东西**。
## 如果随机玩也能拿影后，那整套判定与线索就都白做了。
class RandomPlayer extends SimAgent:
	const CODES: Array[String] = ["A", "B", "C", "D", "E"]
	const TIERS: Array[int] = [
		RoleRequirement.Tier.EXTRA,
		RoleRequirement.Tier.SUPPORTING,
		RoleRequirement.Tier.LEAD,
	]

	func decide(state: GameState) -> Dictionary:
		var pool: Array[Dictionary] = []
		if state.can_submit():
			for code: String in CODES:
				if not state.is_hr_unlocked(code):
					continue
				var co := CompanyLibrary.by_code(code)
				for tier: int in TIERS:
					var role := co.role_of(tier)
					# 只挑「投得出去」的 —— 演技不够的档位连试都不试，
					# 那是连规则都没看的人才会干的事
					if state.acting >= maxi(co.acting_threshold, role.acting_required):
						pool.append({"action": Action.SUBMIT, "company": co, "role": role})
		if Economy.can_work(state):
			pool.append({"action": Action.WORK})
		if Economy.can_take_class(state):
			pool.append({"action": Action.CLASS})
		pool.append({"action": Action.IDLE})
		return pool[rng.randi_range(0, pool.size() - 1)]

	## 瞎拼：三段全随机
	func make_clip(_company: CompanyData) -> Clip:
		var clip := Clip.new(3)
		for i in 3:
			clip.frames[i] = Clip.Frame.new(
					_part(PartData.Slot.EYES, rng),
					_part(PartData.Slot.MOUTH, rng),
					_part(PartData.Slot.BROWS, rng),
					_extra(rng))
		return clip


# ============================================================
# 贪心玩家：看懂了线索，也算得清账
# ============================================================
## 【它测的是上界】每天按固定优先级挑一件事：
##   1. **凑钱** —— 手上不够交本周的房租与分期，且还能打工 → 打工
##   2. **上课** —— 演技还没到 25（影后与 E 大厂的门槛）且本周没上过课，且交得起
##   3. **投递** —— 选「演技收益最高、且理想解过得了线」的档位
##   4. **打工** —— 本周还有次数
##   5. 闲置
##
## 每周刚好 7 点：上课 1 + 投递 4 + 打工 2 —— 与数值表那张「零冗余」的预算表一致。
## 所以它的行动点去向本身就是对「随机事件还剩不剩点」的回答。
class GreedyPlayer extends SimAgent:
	## 演技目标。取 E 大厂门槛，也就是影后的门槛 —— 数值表 3 的 25。
	const ACTING_GOAL := 25
	const CODES: Array[String] = ["A", "B", "C", "D", "E"]
	const TIERS: Array[int] = [
		RoleRequirement.Tier.LEAD,
		RoleRequirement.Tier.SUPPORTING,
		RoleRequirement.Tier.EXTRA,
	]

	func decide(state: GameState) -> Dictionary:
		if _short_on_cash(state) and Economy.can_work(state):
			return {"action": Action.WORK}

		if state.acting < ACTING_GOAL \
				and Economy.can_take_class(state) \
				and state.money >= Economy.class_fee():
			return {"action": Action.CLASS}

		var pick := _best_submission(state)
		if not pick.is_empty():
			return pick

		if Economy.can_work(state):
			return {"action": Action.WORK}
		return {"action": Action.IDLE}

	## 手上不够交本周的房租 + 分期 → 先去挣钱
	func _short_on_cash(state: GameState) -> bool:
		var need := Economy.rent()
		if not Economy.ps5_paid_off(state):
			need += Economy.ps5_amount()
		return state.money < need

	## 挑一个「演技能过门槛 + 理想解能过线」的档位。
	## 排序：**演技收益优先**（因为目标是 25），同收益时挑片酬最高的那家。
	## 【为什么演技优先】演技是唯一能解锁更高档位的东西；钱只影响能不能活下去，
	## 而这个 agent 已经在第 1 步单独处理过钱了。
	func _best_submission(state: GameState) -> Dictionary:
		var best := {}
		var best_gain := -1
		var best_payout := -1
		# 【这一行不写的话，agent 会空转】额度用完时它仍然"决定投递"，
		# 执行时被拒 → 那一天白白浪费，而且报告上显示成「闲置」。
		# 真实玩家会退而求其次去打工，agent 也得会。
		if not state.can_submit():
			return best
		for code: String in CODES:
			if not state.is_hr_unlocked(code):
				continue
			var co := CompanyLibrary.by_code(code)
			var rate := ClipSolver.rate(co.conditions)
			for tier: int in TIERS:
				var role := co.role_of(tier)
				if state.acting < maxi(co.acting_threshold, role.acting_required):
					continue
				if rate < role.match_line:
					continue
				var payout := Economy.payout(co, role)
				if role.acting_gain > best_gain \
						or (role.acting_gain == best_gain and payout > best_payout):
					best_gain = role.acting_gain
					best_payout = payout
					best = {"action": Action.SUBMIT, "company": co, "role": role}
		return best

	func make_clip(company: CompanyData) -> Clip:
		return ClipSolver.make_sloppy(
				ClipSolver.solve_for_company(company), rng, sloppiness)
