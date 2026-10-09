class_name GameState
extends RefCounted
## 全局状态
##
## 【纯逻辑】不继承 Node —— 数值模拟器要能在 headless 下直接构造这个对象跑几千局。
## 场景里由 Game 单例持有，界面只读不写。

const WEEKS := 3
const DAYS_PER_WEEK := 7
const TOTAL_DAYS := WEEKS * DAYS_PER_WEEK  ## 21
const AP_PER_DAY := 1
const TOTAL_AP := TOTAL_DAYS * AP_PER_DAY  ## 21 —— 全局最硬的资源：钱能欠，行动点不能
const MAX_SUBMIT_PER_WEEK := 4

## ---- 属性（状态栏四项 + 一个隐藏项）----
var money: int = 0
var acting: int = 0            ## 演技值
var fame: int = 0              ## 知名度
var reputation: int = 0        ## 风评
var negative_exposure: int = 0 ## 负面曝光累计（隐藏，不上状态栏）

## ---- 时间 ----
var day: int = 1               ## 1 .. 21
var ap_left_today: int = AP_PER_DAY

## ---- 计数（结局判定用）----
var submissions_total: int = 0       ## 投递次数 —— 「龙套之王」用这个口径，不是成功次数
var successes_total: int = 0         ## 成功演出次数
var submissions_this_week: int = 0
var days_without_success: int = 0

## ---- 履历 ----
## 每条：{day, company_code, role_tier, passed, match_rate, labels, play_title, role_name}
## 表情包一次性消耗，所以这里天然按时间顺序记录「你演过什么」，
## 供电子报的「标题调用条件」判断玩家过往经历。
var history: Array[Dictionary] = []

## ---- 结局标记 ----
var ending_flags: Dictionary = {}
var finished: bool = false


func week() -> int:
	return int((day - 1) / DAYS_PER_WEEK) + 1


func day_of_week() -> int:
	return ((day - 1) % DAYS_PER_WEEK) + 1


func is_last_day() -> bool:
	return day >= TOTAL_DAYS


func is_week_end() -> bool:
	return day_of_week() == DAYS_PER_WEEK


func ap_used_total() -> int:
	return (day - 1) * AP_PER_DAY + (AP_PER_DAY - ap_left_today)


func can_submit() -> bool:
	return (not finished) and ap_left_today > 0 and submissions_this_week < MAX_SUBMIT_PER_WEEK


## 消耗行动点。成功返回 true。
func spend_ap(n: int = 1) -> bool:
	if ap_left_today < n:
		return false
	ap_left_today -= n
	return true


## 记录一次投递（无论成败都计入 submissions_total）
func record_submission(passed: bool, payload: Dictionary) -> void:
	submissions_total += 1
	submissions_this_week += 1
	var entry := payload.duplicate()
	entry["day"] = day
	entry["passed"] = passed
	history.append(entry)
	if passed:
		successes_total += 1
		days_without_success = 0
	else:
		days_without_success += 1


## 推进到第二天。跨周时返回 true，调用方据此触发周末结算。
func advance_day() -> bool:
	var was_week_end := is_week_end()
	day = mini(day + 1, TOTAL_DAYS)
	ap_left_today = AP_PER_DAY
	if was_week_end:
		submissions_this_week = 0
		return true
	return false


## 「龙套之王」条件提醒：演技单调递增，所以这条路必须用【投递次数】口径，
## 用成功次数会推出「演技必然 >= 成功数」的矛盾。
func has_ever_played(tier: int) -> bool:
	for h: Dictionary in history:
		if h.get("passed", false) and h.get("role_tier", -1) == tier:
			return true
	return false


func to_save_dict() -> Dictionary:
	return {
		"money": money, "acting": acting, "fame": fame,
		"reputation": reputation, "negative_exposure": negative_exposure,
		"day": day, "ap_left_today": ap_left_today,
		"submissions_total": submissions_total, "successes_total": successes_total,
		"submissions_this_week": submissions_this_week,
		"days_without_success": days_without_success,
		"history": history, "ending_flags": ending_flags, "finished": finished,
	}


func from_save_dict(d: Dictionary) -> void:
	money = int(d.get("money", 0))
	acting = int(d.get("acting", 0))
	fame = int(d.get("fame", 0))
	reputation = int(d.get("reputation", 0))
	negative_exposure = int(d.get("negative_exposure", 0))
	day = int(d.get("day", 1))
	ap_left_today = int(d.get("ap_left_today", AP_PER_DAY))
	submissions_total = int(d.get("submissions_total", 0))
	successes_total = int(d.get("successes_total", 0))
	submissions_this_week = int(d.get("submissions_this_week", 0))
	days_without_success = int(d.get("days_without_success", 0))
	history.assign(d.get("history", []))
	ending_flags = d.get("ending_flags", {})
	finished = bool(d.get("finished", false))
