class_name DailyActions
extends RefCounted
## 玩家在一天里能做的四件事：**投递 / 打工 / 表演课 / 事件**（各占 1 点行动点）
##
## 【事件为什么也算「一天里做的事」】数值表 sheet 1 里 `ap_cost_event = 1` 本来就是
## 「已定」，待决的只是「到底占不占」—— 定了占，它就和打工、上课是同一类东西：
## 吃掉当天的行动点换一个结果。区别只在**来历**：打工上课是玩家主动去点的，
## 事件是**周初自己找上门的**（`EventScheduler` 在每周第一天排进来），
## 所以它多一层「本周待处理」的状态。
##
## 【为什么全都搬到 core 里】数值模拟器要跑几千局、每天做一次决定。
## 它不可能加载场景树去调 `Game`（那是个 Node），而在模拟器里把规则抄一份的话，
## 两边迟早不一样 —— 这类漂移最难查：游戏本体是对的，模拟器算出来的平衡结论是错的，
## 而你还照着那个结论去调数值。
##
## 所以：规则全在这里（纯 RefCounted，只改 `GameState`），
## `Game` 上的那三个同名方法只是它们 + 发信号。
##
## 【为什么「拼表情包」不在这里】决策 1.1 定的是行动点花在投递 / 打工 / 上课 / 事件上。
## 在录像机里拼一段表情包**不花行动点** —— 所以它没有对应的动作，也不该有。
##
## 【重要】投递**只出通过 / 失败，不发钱、不发演技** ——
## 钱、演技、知名度、风评全部留到本周末结算（决策 1.5）。
## 打工与上课反过来是**即时到账**：那是当天付出的劳动与学费，不是播出收入。


# ============================================================
# 投递
# ============================================================
## 执行一次投递。返回结果字典；`rejected = true` 表示根本没投出去（**没扣行动点**）。
static func submit(state: GameState, clip: Clip, company: CompanyData,
		role: RoleRequirement) -> Dictionary:
	if company == null or role == null:
		return rejected("公司或角色未指定")
	if state.finished:
		return rejected("本局已结束")
	if clip == null or not clip.is_complete():
		return rejected("表情包没拼完（眼/嘴/眉必须齐全）")
	# 投递只能走微信私聊，所以 HR 没解锁就没这条渠道。
	# 【为什么在核心层也拦一道】决策 12 是玩法规则，不是界面规则 ——
	# 只写在界面里的话，界面漏判一次就等于规则失效。
	if not state.is_hr_unlocked(company.code):
		return rejected("还没加上 %s 的 HR（先去简历拿来逛一圈）" % company.code)
	if state.submissions_this_week >= GameState.MAX_SUBMIT_PER_WEEK:
		return rejected("本周投递次数已用完（上限 %d）" % GameState.MAX_SUBMIT_PER_WEEK)
	if not state.spend_ap(company.ap_cost):
		return rejected("行动点不够")

	var result := AuditionResolver.resolve(clip, company, role, state.acting)
	result["rejected"] = false
	result["company_code"] = company.code
	result["role_tier"] = role.tier

	# 定角抽签：**只抽一次**，写进履历和回信。之后任何地方再显示都读同一份，
	# 否则读档回来会发现同一部戏改了名。
	var seed_value := state.day * 1000 + state.submissions_total
	var casting := MailComposer.roll_casting(
			MailLibrary.casting_pool(), seed_value, role.tier)
	result["casting"] = casting
	result["mail"] = MailComposer.compose_reply(
			MailLibrary.for_company(company.code), company, role, casting,
			state.day, result["passed"])

	state.record_submission(result["passed"], {
		"company_code": company.code,
		"role_tier": role.tier,
		"match_rate": result["match_rate"],
		"labels": clip.all_labels(),
		"play_title": casting.get("剧名", ""),
		"role_name": casting.get("角色名", ""),
		# 片酬与演技收益**在投递这一刻就定下来**，周末结算只负责把它们发出去。
		# 【为什么不等到结算时现算】中途调平衡会让旧存档的账目前后不一致：
		# 履历上写着「A 厂龙套」，结算却按新价发钱，玩家对不上账。
		# 和定角抽签同一个道理 —— 抽一次，之后谁都读同一份。
		"payout": Economy.payout(company, role),
		"acting_gain": role.acting_gain,
		# 回信原文也存进去 —— 微信的聊天记录要能完整还原，
		# 否则读档回来只剩一条「投递过」的摘要，玩家没法回看邮件
		"mail": result["mail"],
	})

	# 这两项由 Game 那一层转成 EventBus.clip_recorded / ap_changed
	result["clip_summary"] = clip.summarize()
	result["labels"] = clip.all_labels()
	return result


# ============================================================
# 打工 / 表演课
# ============================================================
## 打一次工。返回 {ok, income} 或 {ok: false, reason}。
##
## 【为什么即时结算】决策 1.5 的「全部留到周末」说的是**投出去的作品** ——
## 那是播出收入，得等片子播了才有。打工不是作品：上工当天拿钱，
## 否则「今天打完工还交得起明天的学费吗」就没法回答。
##
## 【为什么校验在 Economy 里、扣状态在这里】校验要能被界面**预演**
## （按钮上要写灰掉的原因），所以它必须是纯函数；真正的变更只能经过这一层。
static func work(state: GameState) -> Dictionary:
	var reason := Economy.work_block_reason(state)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	state.spend_ap()
	state.work_this_week += 1
	state.money += Economy.work_income()
	return {"ok": true, "income": Economy.work_income()}


## 上一次表演课
static func take_class(state: GameState) -> Dictionary:
	var reason := Economy.class_block_reason(state)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	state.spend_ap()
	state.class_this_week += 1
	state.money -= Economy.class_fee()
	# 【这里也要夹演技上限】`Game.add_acting` 会夹，但本类不走它 ——
	# 少夹一次就会让「演技到顶后还继续上课刷值」变成可能
	state.acting = mini(state.acting + Economy.class_gain(), BalanceLibrary.data().acting_cap)
	return {"ok": true, "fee": Economy.class_fee(), "gain": Economy.class_gain()}


static func rejected(reason: String) -> Dictionary:
	return {"passed": false, "rejected": true, "fail_reasons": [reason]}


# ============================================================
# 周初事件（第四个动作）
# ============================================================
## 本周等着处理的事件。没有就返回 null。
static func pending_event(state: GameState) -> EventData:
	if not state.has_pending_event():
		return null
	return EventLibrary.find(state.pending_event)


## 这个选项现在能不能选？返回 "" = 可以，否则是不能选的原因。
##
## 【为什么单独一个纯函数】界面要在按钮上**预演**（灰掉 + 把原因写在旁边），
## 而真正的变更只能经过 `resolve_event` —— 与 `Economy.work_block_reason` 同一个分工。
##
## 【事件和打工在这一点上不同】打工的门槛是「钱 / 次数 / 行动点」三条，
## 事件的门槛只有行动点一条：其他人都找上门了，没有「不够格谈」这回事。
static func event_option_block_reason(state: GameState, index: int) -> String:
	var ev := pending_event(state)
	if ev == null:
		return "这周没有等着处理的事"
	if index < 0 or index >= ev.options.size():
		return "没有这个选项"
	var opt: EventOption = ev.options[index]
	if opt == null:
		return "这个选项还没配好"
	if state.finished:
		return "本局已结束"
	# 【为什么把行动点放在最后判】它是唯一不能欠的资源（钱能欠，行动点不能），
	# 也是玩家最需要提前知道的一条 —— 所以这句话要带上具体数字
	if state.ap_left_today < opt.ap_cost:
		return "行动点不够（要 %d 点，今天还剩 %d 点）" % [opt.ap_cost, state.ap_left_today]
	return ""


## 选一个选项。返回 {ok, event, option, choice} 或 {ok: false, reason}。
static func resolve_event(state: GameState, index: int) -> Dictionary:
	var ev := pending_event(state)
	if ev == null:
		return {"ok": false, "reason": "这周没有等着处理的事"}
	var reason := event_option_block_reason(state, index)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}

	var opt: EventOption = ev.options[index]
	state.spend_ap(opt.ap_cost)
	state.money += opt.money
	# 【这里必须自己夹】`Game.add_acting` 那些会夹，但本类不走 Game
	# （数值模拟器要在 headless 下直接调它）。少夹一次就会出现
	# 「演技到顶之后接着涨」—— 与 take_class 里那句注释同一个理由。
	var bal := BalanceLibrary.data()
	state.acting = clampi(state.acting + opt.acting, 0, bal.acting_cap)
	state.fame = clampi(state.fame + opt.fame, 0, bal.fame_max)
	state.reputation = clampi(state.reputation + opt.reputation, bal.rep_min, bal.rep_max)

	_record(state, ev, index, opt)
	return {"ok": true, "event": ev, "option": opt, "choice": index}


## 周结束时还挂着的事件 —— 记一笔「没理会」，然后清掉。
##
## 【为什么非清不可】不清的话，下一周的 `EventScheduler.pick` 会因为
## 「本周已经排好了」而把**上一周**那条原样端出来，看起来像事件赖着不走。
static func miss_pending_event(state: GameState) -> void:
	if not state.has_pending_event():
		return
	var ev := pending_event(state)
	if not state.has_seen_event(state.pending_event):
		state.seen_events.append(String(state.pending_event))
	state.event_history.append({
		"week": state.week(), "day": state.day,
		"event": String(state.pending_event),
		"speaker": String(ev.speaker) if ev != null else "",
		"choice": -1, "label": "没理会", "note": "",
	})
	state.pending_event = &""


static func _record(state: GameState, ev: EventData, index: int, opt: EventOption) -> void:
	if not state.has_seen_event(ev.id):
		state.seen_events.append(String(ev.id))
	state.event_history.append({
		"week": state.week(), "day": state.day,
		"event": String(ev.id), "speaker": String(ev.speaker),
		"choice": index, "label": opt.label, "note": opt.note,
	})
	state.pending_event = &""
