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
var submissions_total: int = 0       ## 投递次数（成败都算）—— 「被解雇」用失败次数
var successes_total: int = 0         ## 成功演出次数 —— 还要按档位/公司细分见 count_success_by_*
var submissions_this_week: int = 0
var days_without_success: int = 0

## ---- 每周动作计数（跨周清零）----
## 【为什么「打工 / 上课」的次数要存在这里】两者的周上限（2 次 / 1 次）
## 决定了行动点怎么被吃掉，是**玩法状态**；放在界面里就等于界面一刷新上限就重来。
var work_this_week: int = 0
var class_this_week: int = 0

## ---- 目标与特殊标记（跨周累加）----
var ps5_paid: int = 0            ## PS5 已付累计 —— 「凑齐 PS5 费」= 这个数 ≥ ps5_total
var black_fame_seen: bool = false ## 黑红标题出现过没有：第一次是惊奇，之后是嫌烦，文案不同
var extra_star_seen: bool = false ## 龙套「首次出圈」出现过没有 —— 看过一次就不该再「全网找人」

## ---- 周报（微博可以翻往期）----
## 每条 = WeekCycle.trim() 过的周报。最多 3 条，存档体积可忽略。
var reports: Array[Dictionary] = []

## ---- 履历 ----
## 每条：{day, company_code, role_tier, passed, match_rate, labels, play_title, role_name}
## 表情包一次性消耗，所以这里天然按时间顺序记录「你演过什么」，
## 供电子报的「标题调用条件」判断玩家过往经历。
var history: Array[Dictionary] = []

## ---- HR 解锁 ----
## 决策 12：先在 Boss直聘 逛过某家公司，微信里才会解锁它的 HR。
##
## 【为什么放在 GameState 而不是 UI 里】它是**进度**（要进存档），
## 而且决定了「哪家公司现在能投」—— 是玩法状态，不是显示状态。
var unlocked_hr: Array[String] = []

## 玩家在 Boss直聘 的「初次沟通」里挑过的句子：`"A#0" -> 1`（A 家第 0 组选项里的第 1 句）。
## 【为什么要存】第二次进同一家时那段对话**不再逐字演、直接铺完** —— 那时必须把他
## **当初挑的那句**铺出来，否则他会看见一句自己没说过的话。
## 【为什么键里要带组号】md 里连着几行 `选` 就是一组，格式允许一家写好几组；
## 只按公司存一个序号，第二组就会串到第一组的答案上。
## 与 `unlocked_hr` 一样是**进度**：读档回来再点开那家，看到的还是他选过的。
var hr_choice: Dictionary = {}

## ---- 待投递的表情包 ----
## 录像机拼好、还没发出去的那一段。
## 【为什么放在状态里，而不是留在微信手上】录像机与微信是**两个各自整屏的 App**，
## 从微信点「去录像机」会整屏切过去，微信随之被手机屏销毁 —— 拼好的那段留在界面里
## 就等于白录一次。放进状态之后：切回来它还在，读档回来它也在。
## 一次性消耗由界面负责（投出去 / 重开一局时清掉，见 `Game.clear_pending_clip`）。
var pending_clip: Clip = null

## 微信该打开哪位联系人：刚从「简历拿来」加上的那位 / 刚在聊的那位。
## 【为什么不是界面自己的事】微信同样会被销毁重建（去录像机、去简历拿来都要整屏切走），
## 回来时落到「第一家已解锁的」而不是「你刚才那位」，玩家会以为自己点错了。
## 写入口有两处：`Game.unlock_hr()`（刚加上的人优先）与微信选中联系人时。
var focus_hr: String = ""

## ---- 周初事件 ----
## 【为什么种子要进存档】事件是抽签选出来的，读档重抽会让「这周那出戏」变成另一出。
## 与定角抽签同一个道理（决策：抽一次，之后谁都读同一份）：
## 开局抽一次（`Game.new_game`），之后每周期由它派生，模拟器也能复现同一局。
var event_seed: int = 0
## 本周等着处理的事件 id。空 = 这周没有事件（内容没配 / 已处理 / 条件不满足）
var pending_event: StringName = &""
## 已经出现过的事件 id（**含错过的**）—— 除 `repeatable` 外不再重复出现
var seen_events: Array[String] = []
## 每次处理的记录：{week, day, event, speaker, choice, label, note}
## `choice == -1` 表示周结束时也没处理（作废）。微信与模拟器都读这一份。
var event_history: Array[Dictionary] = []

## ---- 结局标记 ----
var ending_flags: Dictionary = {}
var ending_id: StringName = &""   ## 判出来的结局 id（空 = 还没到第 21 天）
var finished: bool = false


## 本周有没有等着处理的事件
func has_pending_event() -> bool:
	return pending_event != &""


## 这个事件出现过没有（含错过的）—— 事件表用它决定要不要再让同一条出现
func has_seen_event(id: StringName) -> bool:
	return seen_events.has(String(id))


## 解锁某家公司的 HR。返回 true 表示这次是**新**解锁的。
func unlock_hr(code: String) -> bool:
	if code.is_empty() or unlocked_hr.has(code):
		return false
	unlocked_hr.append(code)
	return true


func is_hr_unlocked(code: String) -> bool:
	return unlocked_hr.has(code)


## 记下玩家在第 `run` 组选项里挑的是第几句（都从 0 起）
func set_hr_choice(code: String, run: int, index: int) -> void:
	if code.is_empty():
		return
	hr_choice["%s#%d" % [code, run]] = index


## 他当初挑的是第几句？**没挑过返回 -1** —— 调用方自己决定退回第一句
func hr_choice_of(code: String, run: int) -> int:
	return int(hr_choice.get("%s#%d" % [code, run], -1))


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
##
## 【第 21 天之后不再前进】day 会被夹在 TOTAL_DAYS 上，于是 is_week_end() 永远为真 ——
## 调用方必须靠 state.finished 挡住重复结算，否则第 3 周的账会一遍遍算下去。
func advance_day() -> bool:
	var was_week_end := is_week_end()
	day = mini(day + 1, TOTAL_DAYS)
	ap_left_today = AP_PER_DAY
	if was_week_end:
		submissions_this_week = 0
		work_this_week = 0
		class_this_week = 0
		return true
	return false


## 是否演过某个档位的角色（「文艺片女神」要 D 公司主角、「影后」要 E 公司主角）
func has_ever_played(tier: int) -> bool:
	for h: Dictionary in history:
		if h.get("passed", false) and h.get("role_tier", -1) == tier:
			return true
	return false


## ---- 结局判定的计数口径 ----
##
## 【为什么不能直接用 successes_total】「龙套之王」要的是「演过多少个小角色」，
## 不是「演过多少部戏」。同样是 8 次成功，全是龙套和全是主角是两种人生。
## 所以结局条件必须能按档位 / 按公司分别计数，不能只有一个总数。

## 按角色档位统计成功演出次数
func count_success_by_tier(tier: int) -> int:
	var n := 0
	for h: Dictionary in history:
		if h.get("passed", false) and h.get("role_tier", -1) == tier:
			n += 1
	return n


## 按公司代号统计成功演出次数（「烂片女王」传 ["A", "B"]）
func count_success_by_company(codes: Array) -> int:
	var n := 0
	for h: Dictionary in history:
		if h.get("passed", false) and h.get("company_code", "") in codes:
			n += 1
	return n


## 公司 × 档位 —— 「影后」要 E 公司**主角**、「文艺片女神」要 D 公司主角。
## 【为什么不能只用 has_ever_played(tier)】那只能回答「演过主角没有」，
## 答不了「在哪家演的主角」。在 A 厂演主角和在大厂演主角不是一回事。
func count_success_by_company_tier(codes: Array, tier: int) -> int:
	var n := 0
	for h: Dictionary in history:
		if h.get("passed", false) \
				and h.get("company_code", "") in codes \
				and int(h.get("role_tier", -1)) == tier:
			n += 1
	return n


## 累计失败投递次数 —— 「被解雇」结局用这个口径
func failed_submissions() -> int:
	return submissions_total - successes_total


func to_save_dict() -> Dictionary:
	return {
		"money": money, "acting": acting, "fame": fame,
		"reputation": reputation, "negative_exposure": negative_exposure,
		"day": day, "ap_left_today": ap_left_today,
		"submissions_total": submissions_total, "successes_total": successes_total,
		"submissions_this_week": submissions_this_week,
		"days_without_success": days_without_success,
		"work_this_week": work_this_week, "class_this_week": class_this_week,
		"ps5_paid": ps5_paid,
		"black_fame_seen": black_fame_seen, "extra_star_seen": extra_star_seen,
		"unlocked_hr": unlocked_hr, "hr_choice": hr_choice,
		# 待投递的表情包存成部件 id（见 `Clip.save_dict`）。没有时给一个空字典 ——
		# JSON 里 null 落不住，`from_save_dict` 认空字典就是「没有」。
		"pending_clip": {} if pending_clip == null else pending_clip.save_dict(),
		"focus_hr": focus_hr,
		"reports": reports,
		"history": history,
		# 【pending_event 存成空串而不是 null】JSON 里 StringName 落不住，
		# 读回来一律走 StringName(...) —— 与 ending_id 同一个处理方式
		"event_seed": event_seed,
		"pending_event": String(pending_event),
		"seen_events": seen_events,
		"event_history": event_history,
		"ending_flags": ending_flags,
		"ending_id": String(ending_id), "finished": finished,
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
	work_this_week = int(d.get("work_this_week", 0))
	class_this_week = int(d.get("class_this_week", 0))
	ps5_paid = int(d.get("ps5_paid", 0))
	black_fame_seen = bool(d.get("black_fame_seen", false))
	extra_star_seen = bool(d.get("extra_star_seen", false))
	unlocked_hr.assign(d.get("unlocked_hr", []))
	hr_choice = d.get("hr_choice", {})
	var clip_dict: Variant = d.get("pending_clip", null)
	pending_clip = Clip.from_save_dict(clip_dict) if typeof(clip_dict) == TYPE_DICTIONARY else null
	focus_hr = String(d.get("focus_hr", ""))
	reports.assign(d.get("reports", []))
	history.assign(d.get("history", []))
	event_seed = int(d.get("event_seed", 0))
	pending_event = StringName(d.get("pending_event", ""))
	seen_events.assign(d.get("seen_events", []))
	event_history.assign(d.get("event_history", []))
	ending_flags = d.get("ending_flags", {})
	ending_id = StringName(d.get("ending_id", ""))
	finished = bool(d.get("finished", false))
