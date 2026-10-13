class_name Economy
extends RefCounted
## 钱与行动点的兑换规则 —— 全部是**纯函数**，不改状态
##
## 【为什么和 WeekCycle 分开】WeekCycle 管「什么时候收钱」（时序），
## Economy 管「收多少 / 能不能做」（数值）。分开之后数值模拟器可以单独问
## 「这一周最多能挣多少」而不必跑一遍结算流程，界面也才能在按钮上写清
## 「点下去会发生什么」。
##
## 【打工 / 上课是即时到账，作品收益才是周末到账】
## 决策 1.5 的「全部留到周末结算」针对的是**投递出去的作品** —— 那是播出收入，
## 得等片子播了才有。打工和上课不是作品：当天上工当天拿钱、当天交学费当天涨演技。
## 把三者混在一起，「今天打完工还交得起明天的学费吗」这个问题就没法回答了。

## 动作被拒绝的原因（空串 = 可以做）。
## 【为什么返回原因而不是 bool】手机壳上的「今日安排」要把原因**写在按钮上**，
## 否则玩家只会看到两个灰按钮，不知道是没钱、没行动点，还是本周次数用完了。
const REASON_AP := "今天的行动点已经用掉了"
const REASON_FINISHED := "本局已结束"


static func balance() -> BalanceData:
	return BalanceLibrary.data()


## 一部作品的片酬 —— 钱由**公司档次**决定，与演技和匹配度都无关（决策 1.3）
static func payout(company: CompanyData, role: RoleRequirement) -> int:
	if company == null:
		return 0
	return company.payout_for(role)


# ============================================================
# 打工
# ============================================================
static func work_income() -> int:
	return balance().work_income


static func work_left_this_week(state: GameState) -> int:
	return maxi(0, balance().work_max_per_week - state.work_this_week)


static func can_work(state: GameState) -> bool:
	return work_block_reason(state).is_empty()


static func work_block_reason(state: GameState) -> String:
	if state.finished:
		return REASON_FINISHED
	if state.ap_left_today <= 0:
		return REASON_AP
	if work_left_this_week(state) <= 0:
		return "本周已经打了 %d 次工（上限 %d）" % [state.work_this_week, balance().work_max_per_week]
	return ""


# ============================================================
# 表演课
# ============================================================
static func class_fee() -> int:
	return balance().class_price


static func class_gain() -> int:
	return balance().class_gain


static func class_left_this_week(state: GameState) -> int:
	return maxi(0, balance().class_max_per_week - state.class_this_week)


static func can_take_class(state: GameState) -> bool:
	return class_block_reason(state).is_empty()


static func class_block_reason(state: GameState) -> String:
	if state.finished:
		return REASON_FINISHED
	if state.ap_left_today <= 0:
		return REASON_AP
	if class_left_this_week(state) <= 0:
		return "本周已经上过课了（上限 %d）" % balance().class_max_per_week
	# 【顺序要紧】先报「钱不够」再报「演技到顶」——
	# 两者同时成立时，玩家更该知道的是钱的问题（演技到顶是他自己练出来的）
	if state.money < class_fee():
		return "学费 %d 元，手上只有 %d 元" % [class_fee(), state.money]
	if state.acting >= balance().acting_cap:
		return "演技已经到顶（%d）" % balance().acting_cap
	return ""


# ============================================================
# 固定支出
# ============================================================
static func rent() -> int:
	return balance().rent_per_week


static func ps5_amount() -> int:
	return balance().ps5_amount_per


static func ps5_total() -> int:
	return balance().ps5_total


## 「凑齐 PS5 费」—— 影后与平庸的门槛，也是整个游戏的目标
static func ps5_paid_off(state: GameState) -> bool:
	return state.ps5_paid >= ps5_total()


## 还差几期。界面用它显示「PS5 进度 2/3」
static func ps5_installments_paid(state: GameState) -> int:
	if ps5_amount() <= 0:
		return 0
	return int(state.ps5_paid / ps5_amount())


## 这一周该交的分期金额。分期数用完后返回 0。
## 【为什么按周算而不是按天】每期截止日就是每周最后一天（第 7/14/21 天），
## 而结算本来就发生在周最后一天 —— 两者是同一个时刻，不必再存一份截止日表。
static func ps5_due_for_week(week: int) -> int:
	if week > GameState.WEEKS:
		return 0
	return ps5_amount()
