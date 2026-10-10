extends Node
## Game 单例（Autoload 名：Game）
##
## 【架构约束】这是个**壳**，只做两件事：持有 GameState、把状态变更转成 EventBus 信号。
## 判定、经济、周流程的逻辑一律写在 GameState / AuditionResolver / Economy 里，
## 那些类全部是 RefCounted、不继承 Node —— 数值模拟器要能脱离场景树 headless 跑。
## **不要**往这个文件里加任何计算逻辑。

var state: GameState


func _ready() -> void:
	new_game()


func new_game(init_money: int = 0, init_acting: int = 0) -> void:
	state = GameState.new()
	state.money = init_money
	state.acting = init_acting
	EventBus.ap_changed.emit(state.ap_left_today)
	# 放在最后：界面收到它时，新状态已经就位，可以放心照着重画
	EventBus.state_reset.emit()


# ============================================================
# 只读访问 —— 界面用这些，不要直接改 state
# ============================================================
func money() -> int:
	return state.money


func acting() -> int:
	return state.acting


func fame() -> int:
	return state.fame


func reputation() -> int:
	return state.reputation


func day() -> int:
	return state.day


func week() -> int:
	return state.week()


func ap_left() -> int:
	return state.ap_left_today


func can_submit() -> bool:
	return state.can_submit()


func submissions_left_this_week() -> int:
	return maxi(0, GameState.MAX_SUBMIT_PER_WEEK - state.submissions_this_week)


# ============================================================
# 属性变更 —— 改值 + 发信号，成对出现
# ============================================================
func add_money(delta: int) -> void:
	state.money += delta
	EventBus.money_changed.emit(state.money, delta)


func add_acting(delta: int) -> void:
	state.acting += delta
	EventBus.acting_changed.emit(state.acting, delta)


func add_fame(delta: int) -> void:
	state.fame += delta
	EventBus.fame_changed.emit(state.fame, delta)


func add_reputation(delta: int) -> void:
	state.reputation += delta
	EventBus.reputation_changed.emit(state.reputation, delta)


# ============================================================
# HR 解锁（决策 12：先在 Boss直聘 逛过该公司，微信里才解锁它的 HR）
# ============================================================
## 返回 true 表示这次是新解锁的
func unlock_hr(code: String) -> bool:
	if not state.unlock_hr(code):
		return false
	EventBus.hr_unlocked.emit(code)
	return true


func is_hr_unlocked(code: String) -> bool:
	return state.is_hr_unlocked(code)


# ============================================================
# 投递
# ============================================================
## 一次投递的完整流程：校验 → 扣行动点 → 判定 → 记履历 → 配回信 → 发信号
##
## 【重要】这里**只出通过/失败，不发钱、不发演技** ——
## 钱、演技、知名度、风评全部留到本周末结算（见决策记录 1.5）。
## 返回的 Dictionary 里 rejected=true 表示根本没投出去（没扣行动点）。
func submit_audition(clip: Clip, company: CompanyData, role: RoleRequirement) -> Dictionary:
	if company == null or role == null:
		return {"passed": false, "rejected": true, "fail_reasons": ["公司或角色未指定"]}
	if state.finished:
		return {"passed": false, "rejected": true, "fail_reasons": ["本局已结束"]}
	if not clip.is_complete():
		return {"passed": false, "rejected": true,
				"fail_reasons": ["表情包没拼完（眼/嘴/眉必须齐全）"]}
	# 投递只能走微信私聊，所以 HR 没解锁就没这条渠道。
	# 【为什么在核心层也拦一道】决策 12 是玩法规则，不是界面规则 ——
	# 只写在界面里的话，界面漏判一次就等于规则失效。
	if not state.is_hr_unlocked(company.code):
		return {"passed": false, "rejected": true,
				"fail_reasons": ["还没加上 %s 的 HR（先去 Boss直聘 逛一圈）" % company.code]}
	if state.submissions_this_week >= GameState.MAX_SUBMIT_PER_WEEK:
		return {"passed": false, "rejected": true,
				"fail_reasons": ["本周投递次数已用完（上限 %d）" % GameState.MAX_SUBMIT_PER_WEEK]}
	if not state.spend_ap(company.ap_cost):
		return {"passed": false, "rejected": true, "fail_reasons": ["行动点不够"]}

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
		# 回信原文也存进去 —— 微信的聊天记录要能完整还原，
		# 否则读档回来只剩一条「投递过」的摘要，玩家没法回看邮件
		"mail": result["mail"],
	})

	# 表情包一次性消耗 —— 记进履历供电子报的「标题调用条件」判定过往经历
	EventBus.clip_recorded.emit(clip.summarize(), clip.all_labels())
	EventBus.ap_changed.emit(state.ap_left_today)
	EventBus.audition_submitted.emit(result)
	EventBus.hr_replied.emit(company.code, result["passed"], result)

	return result


# ============================================================
# 时间推进（周末结算的实现在 M2）
# ============================================================
## 推进一天。返回 true 表示跨过了周末，调用方应触发周结算。
func advance_day() -> bool:
	var crossed_week := state.advance_day()
	EventBus.ap_changed.emit(state.ap_left_today)
	EventBus.day_advanced.emit(state.day, state.week())
	return crossed_week


# ============================================================
# 存档（每周结算时调用）
# ============================================================
func save_to(path: String = "user://save.json") -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(state.to_save_dict(), "\t"))
	f.close()
	return OK


func load_from(path: String = "user://save.json") -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	state.from_save_dict(parsed)
	EventBus.ap_changed.emit(state.ap_left_today)
	# 读档对界面来说和开新局一样：状态整个换了，必须照着重画
	EventBus.state_reset.emit()
	return true
