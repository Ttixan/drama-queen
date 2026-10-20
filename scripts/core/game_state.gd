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

## ---- 开场 / 身份 ----
## 开场（A1 报纸广告 → A2/A3 独白 → 取名）播完了没有。
## 【新局 = false，老存档 = true】`from_save_dict` 对缺失字段的默认值见那里 ——
## 10-19 之前的存档不该被强制重看一遍开场。
var intro_done: bool = false
## 玩家自己取的名字。空 = 还没取，邮件 / 报纸 / 微信回退到定角池的占位名。
## 【为什么存在状态层而不是直接写 CastingPool】名字必须跟着存档走；
## `CastingPool` 是磁盘上的模板资源，往它身上写只在本进程有效。
var player_name: String = ""
## 新手引导走到哪一步（见 `TutorialLayer.Step`）。
## 【0 = 没开始，7 = 这批引导走完，-1 = 老档视为已完成】
## 与 `intro_done` 同一套口径：字段缺失时默认 `-1`，老玩家不会被按着重新看一遍。
var tutorial_step: int = 0

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
## 每条：{day, company_code, role_tier, passed, match_rate, labels, play_title, role_name,
##        payout, acting_gain, play_is_good, mail}
## `play_is_good` = 投递那一刻按公司概率摇的「这部戏本身好不好」，**存下来不再重算**
## （口径见 `core/broadcast.gd`）。缺这个字段的旧存档一律当「好剧」。
## 表情包一次性消耗，所以这里天然按时间顺序记录「你演过什么」，
## 供电子报的「标题调用条件」判断玩家过往经历。
var history: Array[Dictionary] = []

## ---- HR 解锁 ----
## 决策 12：先在 Boss直聘 逛过某家公司，微信里才会解锁它的 HR。
##
## 【为什么放在 GameState 而不是 UI 里】它是**进度**（要进存档），
## 而且决定了「哪家公司现在能投」—— 是玩法状态，不是显示状态。
var unlocked_hr: Array[String] = []

## 微信里「有未读」的 HR 代号。
##
## 【为什么只有「新解锁」会未读】HR 没有任何异步来信：投递的回复是玩家点「发送」
## 那一刻当场生成的，人就在会话里，天然已读。所以当前唯一的未读来源是
## 「刚在简历拿来加上这个人，还没点开看过他」。以后真加了 HR 主动找你，也往这里塞。
##
## 【为什么不存成每条消息的已读游标】那需要一份真正的消息时间线；
## 现在会话是**从状态重建**的（没有消息表），存游标等于凭空造一套数据。
var unread_hrs: Array[String] = []

## 玩家在 Boss直聘 的「初次沟通」里挑过的句子：`"A#0" -> 1`（A 家第 0 组选项里的第 1 句）。
## 【为什么要存】第二次进同一家时那段对话**不再逐字演、直接铺完** —— 那时必须把他
## **当初挑的那句**铺出来，否则他会看见一句自己没说过的话。
## 【为什么键里要带组号】md 里连着几行 `选` 就是一组，格式允许一家写好几组；
## 只按公司存一个序号，第二组就会串到第一组的答案上。
## 与 `unlocked_hr` 一样是**进度**：读档回来再点开那家，看到的还是他选过的。
var hr_choice: Dictionary = {}

## 这家 HR **手上那份剧本**：`"A" -> {"play": 1, "tier": 0}`（剧本1 的龙套视角）。
##
## 【为什么是进度而不是界面状态】微信会被销毁重建（去录像机 / 去简历拿来都整屏切走），
## 而读档回来时玩家还得看得见「我手上是哪个档的剧本」。
## 存的是 (剧本序号, 档位) 两个数、不是文案 —— 狗牙改剧本内容不用迁移任何存档。
## 【什么时候清】投出去之后清掉（由界面在投递成功后调 `clear_hr_script`）——
## 一部拍完，HR 接着问下一部要试哪类角色。
var hr_script: Dictionary = {}

## ---- 复杂表情（周结算翻牌奖励）----
## 【规则】龙套 / 配角 / 主角**各自首次**成功投递 → 各得一次翻牌机会；
## 翻到哪套就永久拥有哪套的三件部件（牌面与部件表见 `ExpressionSets`）。
##
## 已经拿到的表情套 id。录像机按它决定那 9 件部件能不能点。
var owned_sets: Array[String] = []
## 已经发过奖励的档位（`RoleRequirement.Tier` 的整数）—— 每档一辈子一次。
## 【为什么不靠 owned_sets 反推】三套牌 vs 三个档位，数量刚好相等只是巧合；
## 一旦以后一套牌拆成两档、或一档给两套，反推就会重复发奖。
var rewarded_tiers: Array[int] = []
## 攒着还没翻的牌：每项 `{tier, set}`。第一项就是界面该翻的那一张。
## 【为什么结算时就把 set 抽好】与定角抽签同一条口径：抽一次、存下来，
## 读档回来还是同一张脸。玩家点哪张牌只是表演，不改变结果 ——
## 也正因为如此，三张牌背可以长得一模一样。
var pending_flips: Array[Dictionary] = []

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
## 本周等着处理的事件 id —— **1~2 条**（10-17 起从「一周一出」放开）。
## 空数组 = 这周没有事件（内容没配 / 已处理 / 条件不满足）。
##
## 【为什么是数组】一周可能排两条，且第一条不处理时第二条照样会来。
## 用单值的话，第二条会被第一条挡住（`has_pending_event` 恒真 → 调度器直接返回）。
##
## 【顺序有意义】按排进来的先后排 —— 界面「先看谁」、读档回放都照这个顺序。
var pending_events: Array[String] = []

## 兼容旧接口：单值读写。
##   读 = 最早那条（没有就空）；
##   写 = **整队替换**（空串 = 清空）。
## 留它的原因是测试与界面里遍布 `state.pending_event = &"xxx"` 这种写法，
## 而语义变了（多了「并列」这一维）—— 与其全改成数组运算，不如把单值语义钉死在这里。
var pending_event: StringName:
	get:
		return StringName(pending_events[0]) if not pending_events.is_empty() else &""
	set(value):
		pending_events.clear()
		if value != &"":
			pending_events.append(String(value))
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
	return not pending_events.is_empty()


## 排进来一件（不查重 —— 查重在 `EventScheduler`，这里只管状态）
func add_pending_event(id: StringName) -> void:
	if id == &"" or pending_events.has(String(id)):
		return
	pending_events.append(String(id))


## 处理掉一件。返回是否真的在队里 —— 界面据此判断「是不是点了个已经过去的事」
func remove_pending_event(id: StringName) -> bool:
	var key := String(id)
	if not pending_events.has(key):
		return false
	pending_events.erase(key)
	return true


## 这个事件出现过没有（含错过的）—— 事件表用它决定要不要再让同一条出现
func has_seen_event(id: StringName) -> bool:
	return seen_events.has(String(id))


## 解锁某家公司的 HR。返回 true 表示这次是**新**解锁的。
func unlock_hr(code: String) -> bool:
	if code.is_empty() or unlocked_hr.has(code):
		return false
	unlocked_hr.append(code)
	# 新解锁 = 一条未读（手机上微信图标要亮起来，玩家才知道「多了个人可以聊」）
	if not unread_hrs.has(code):
		unread_hrs.append(code)
	return true


## 打开过这位 HR 的会话 = 已读
func mark_hr_read(code: String) -> void:
	unread_hrs.erase(code)


## 这件事还等着回话吗
func has_pending_event_id(id: StringName) -> bool:
	return pending_events.has(String(id))


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


## 这家 HR 手上那份剧本。**没有就返回空字典**（还没要过 / 已经拍完了）
func hr_script_of(code: String) -> Dictionary:
	var v: Variant = hr_script.get(code, {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


## 记下 HR 刚发过来的这份剧本。`play_index` = 三份剧本里的第几份（1 起）
func set_hr_script(code: String, play_index: int, tier: int) -> void:
	if code.is_empty():
		return
	hr_script[code] = {"play": play_index, "tier": tier}


## 这一份用掉了（投出去了）—— HR 会接着问下一部
func clear_hr_script(code: String) -> void:
	hr_script.erase(code)


## 这套表情拿到了没有（部件列表见 `ExpressionSets`）
func owns_expression_set(id: String) -> bool:
	return not id.is_empty() and owned_sets.has(id)


## 这个档位的奖励发过没有
func has_rewarded_tier(tier: int) -> bool:
	return rewarded_tiers.has(tier)


## 结算时排一张牌。**同一档只排一次**（调用方仍应先用 `has_rewarded_tier` 判）。
func queue_flip(tier: int, set_id: String) -> void:
	if set_id.is_empty() or has_rewarded_tier(tier):
		return
	rewarded_tiers.append(tier)
	pending_flips.append({"tier": tier, "set": set_id})


func pending_flip_count() -> int:
	return pending_flips.size()


## 最前面那张牌（**不消费**）—— 界面拿它显示牌面，玩家点哪张都不改变结果。
## 没有就返回空字典。
func peek_flip() -> Dictionary:
	return {} if pending_flips.is_empty() else pending_flips[0]


## 玩家点「收下」时消费：把这一套加进已拥有，返回刚翻到的那条记录。
## 【为什么不在翻开动画一开始就消费】动画中途退出（切屏 / 杀进程）不该吞掉奖励 ——
## 只有他说「收下」才算数。
func claim_flip() -> Dictionary:
	if pending_flips.is_empty():
		return {}
	var entry: Dictionary = pending_flips.pop_front()
	var set_id := String(entry.get("set", ""))
	if not set_id.is_empty() and not owned_sets.has(set_id):
		owned_sets.append(set_id)
	return entry


## 该发的表情奖励排进状态，返回这次新排的牌（`{tier, set}` 列表）。
##
## 【什么时候调】**玩家按下「下一天」时**（`Game.end_day` 开头）—— 试镜成功的当下不弹，
## 翻牌才是「第二天睁眼，剧组给了个回应」的仪式。
## 【触发条件】某个档位**累计成功过至少一次**，且这个档位还没发过奖。
## 因为 `history` 是跨周累加的，同一档不会因为"又演成一次"再发一张。
func queue_expression_rewards(week: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for tier: int in [
			RoleRequirement.Tier.EXTRA,
			RoleRequirement.Tier.SUPPORTING,
			RoleRequirement.Tier.LEAD]:
		if has_rewarded_tier(tier):
			continue
		if count_success_by_tier(tier) <= 0:
			continue
		var set_id := roll_reward_set(tier, week)
		if set_id.is_empty():
			continue
		queue_flip(tier, set_id)
		out.append({"tier": tier, "set": set_id})
	return out


## 这张牌翻到哪套：只在**还没拿到 / 还没排进队列**的套里抽，尽量不重复。
##
## 【为什么用固定种子而不是 randi()】读档重放同一天必须翻到同一张脸 ——
## 与定角抽签、周初事件同一条口径（随机只发生一次，之后谁都读同一份）。
## 种子只由 (event_seed, week, tier) 派生，所以「同一份存档 + 同一个周次」
## 在任何机器上都得到同一个结果，模拟器也能复现。
func roll_reward_set(tier: int, week: int) -> String:
	var taken := {}
	for id: String in owned_sets:
		taken[id] = true
	for f: Dictionary in pending_flips:
		var queued := String(f.get("set", ""))
		if not queued.is_empty():
			taken[queued] = true

	var pool: Array[String] = []
	for id: String in ExpressionSets.ids():
		if not taken.has(id):
			pool.append(id)
	# 三套都拿过了（正常玩不到：只有三个档位）—— 兜底回全套，宁可重复也不空手
	if pool.is_empty():
		pool = ExpressionSets.ids()
	if pool.is_empty():
		return ""

	var rng := RandomNumberGenerator.new()
	rng.seed = event_seed * 7919 + week * 131 + tier * 17
	return pool[rng.randi_range(0, pool.size() - 1)]


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


## 按公司代号统计成功演出次数 —— 回答「你签过几家、在哪几家演成过」。
## 【不再是「烂片女王」的口径】片子好坏看履历里的 `play_is_good`（见 `count_bad_plays`），
## 按代号数会把「你拍了多少部烂片」数成「你签了多少家小厂」。
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


## 累计演过的**烂片**部数 —— 「烂片女王」用这个口径。
##
## 【为什么不再按公司代号数】片子好坏是公司自带的概率（`CompanyData.good_play_chance`），
## 投递那一刻摇一次、写进履历（`play_is_good`）—— A 厂也会出好片、E 厂也会出烂片。
## 按代号数等于把「你拍了多少部烂片」数成「你签了多少家小厂」。
## 【缺字段时按「好剧」】旧存档的履历里没有这个字段，读回来不该突然变成一柜子烂片。
func count_bad_plays() -> int:
	var n := 0
	for h: Dictionary in history:
		if h.get("passed", false) and not bool(h.get("play_is_good", true)):
			n += 1
	return n


## 累计失败投递次数 —— 「被解雇」结局用这个口径
func failed_submissions() -> int:
	return submissions_total - successes_total


func to_save_dict() -> Dictionary:
	return {
		"money": money, "acting": acting, "fame": fame,
		"reputation": reputation, "negative_exposure": negative_exposure,
		"intro_done": intro_done, "player_name": player_name,
		"tutorial_step": tutorial_step,
		"day": day, "ap_left_today": ap_left_today,
		"submissions_total": submissions_total, "successes_total": successes_total,
		"submissions_this_week": submissions_this_week,
		"days_without_success": days_without_success,
		"work_this_week": work_this_week, "class_this_week": class_this_week,
		"ps5_paid": ps5_paid,
		"black_fame_seen": black_fame_seen, "extra_star_seen": extra_star_seen,
		"unlocked_hr": unlocked_hr, "hr_choice": hr_choice,
		"hr_script": hr_script,
		"owned_sets": owned_sets, "rewarded_tiers": rewarded_tiers,
		"pending_flips": pending_flips,
		# 待投递的表情包存成部件 id（见 `Clip.save_dict`）。没有时给一个空字典 ——
		# JSON 里 null 落不住，`from_save_dict` 认空字典就是「没有」。
		"pending_clip": {} if pending_clip == null else pending_clip.save_dict(),
		"focus_hr": focus_hr,
		"reports": reports,
		"history": history,
		# 【pending_event 存成空串而不是 null】JSON 里 StringName 落不住，
		# 读回来一律走 StringName(...) —— 与 ending_id 同一个处理方式
		"event_seed": event_seed,
		# 【10-17 起是数组】老档里的单值 `pending_event` 由 `from_save_dict` 兜底转换
		"pending_events": pending_events,
		"unread_hrs": unread_hrs,
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
	# 【老档默认 true】这个字段是 10-19 加进来的；之前的存档里没有它，
	# 默认成 false 会让所有老玩家在读档后被按着看一遍开场。
	intro_done = bool(d.get("intro_done", true))
	# 【老档默认 -1 = 已完成】理由同 `intro_done`：这是 10-20 才加进来的字段，
	# 默认 0 会把所有老玩家拉回「点了手机才刚开始」的状态。
	tutorial_step = int(d.get("tutorial_step", -1))
	player_name = String(d.get("player_name", "")).strip_edges()
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
	# 旧存档没有这一项 —— 读回空字典就是「还没跟 HR 要过剧本」，界面会重新问一遍
	hr_script = d.get("hr_script", {})
	# 【老档没有这几项 = 一套都没拿到、也没有待翻的牌】正好是加这个功能之前的语义
	owned_sets.assign(d.get("owned_sets", []))
	# 【JSON 里整数会读成浮点】`Array[int].assign()` 碰到 0.0 会当场报类型错，
	# 所以这里逐个转 —— 也顺手挡掉存档里混进来的别的类型
	rewarded_tiers.clear()
	for t: Variant in d.get("rewarded_tiers", []):
		rewarded_tiers.append(int(t))
	pending_flips.clear()
	for f: Variant in d.get("pending_flips", []):
		if typeof(f) == TYPE_DICTIONARY:
			pending_flips.append(f)
	var clip_dict: Variant = d.get("pending_clip", null)
	pending_clip = Clip.from_save_dict(clip_dict) if typeof(clip_dict) == TYPE_DICTIONARY else null
	focus_hr = String(d.get("focus_hr", ""))
	reports.assign(d.get("reports", []))
	history.assign(d.get("history", []))
	event_seed = int(d.get("event_seed", 0))
	# 【老存档兼容】以前存的是单值 `pending_event`（String）。读到字符串就包成一条，
	# 否则「一周一出」时代存下来的档会丢掉那件正等着处理的事。
	var pend: Variant = d.get("pending_events", null)
	if typeof(pend) == TYPE_ARRAY:
		pending_events.assign(pend)
	else:
		var one := String(d.get("pending_event", ""))
		pending_events.clear()
		if not one.is_empty():
			pending_events.append(one)
	unread_hrs.assign(d.get("unread_hrs", []))
	seen_events.assign(d.get("seen_events", []))
	event_history.assign(d.get("event_history", []))
	ending_flags = d.get("ending_flags", {})
	ending_id = StringName(d.get("ending_id", ""))
	finished = bool(d.get("finished", false))
