class_name EndingResolver
extends RefCounted
## 结局判定 —— 按优先级取第一条成立的
##
## 【「先做 3 个结局」做的是什么，不是什么】
## Day 2 拍板的是**文案与演出**只做 3 个（影后 / 龙套之王 / 平庸）。
## 判定**六条全写了** —— 因为少写一条会造成静默的错误结局：
## 一个演过 D 公司主角、演技 20 的玩家本该是「文艺片女神」，
## 如果没有这一条，他会直接掉进「龙套之王」，玩家看到的是一句彻底跑偏的结语。
## 所以：判定全做，文案 3 条是真的，3 条明写「待补」并在界面上标出来。
##
## 【优先级为什么是这个顺序】好结局优先于坏结局，具体优先于笼统：
## 影后 > 文艺片女神 > 龙套之王 > 烂片女王 > 被解雇 > 平庸。
## 尤其是「龙套之王」必须排在影后之后 —— 演技 25 的人也可能演过 8 个龙套，
## 不能因为龙套演得多就给他一个「你一直没红」的结局。

## 【为什么条件是代码而不是数据】条件里要读 `GameState` 的统计方法
## （按档位计数、按公司计数、是否演过某公司的主角），
## 写成 Callable 数组比塞进 `.tres` 更直白，也更好测。
## 【文案是内容】狗牙补真文案时只改这里，不动判定。


static func all() -> Array[Dictionary]:
	return [
		{
			"id": &"actress",
			"name": "影后",
			"implemented": true,
			"text": "颁奖礼的红毯比你想的短。你从城郊老厂房摄影棚一路走到这里，用了二十一天。\n"
					+ "后台有人喊你的名字，这次不用谁提醒你该站哪一边。",
			"condition": "演技 ≥ %d ｜ 演过 E 公司主角 ｜ 凑齐 PS5 费" % _actress_acting(),
		},
		{
			"id": &"arthouse_goddess",
			"name": "文艺片女神",
			"implemented": false,
			"text": "【文案待补 · 狗牙】演技 ≥ 18 且演过 D 公司主角。\n"
					+ "判定已生效，缺的只是这一句结语。",
			"condition": "演技 ≥ 18 ｜ 演过 D 公司主角",
		},
		{
			"id": &"extra_king",
			"name": "龙套之王",
			"implemented": true,
			"text": "三年后你还在跑龙套。剧组换了一茬又一茬，只有场记见你还点头：「又是你。」\n"
					+ "PS5 摆在出租屋的电视柜上，箱子还没拆。",
			"condition": "龙套档成功演出 ≥ 8 ｜ 演技 ≤ 12",
		},
		{
			"id": &"bad_movie_queen",
			"name": "烂片女王",
			"implemented": false,
			"text": "【文案待补 · 狗牙】A/B 公司成功演出 ≥ 6 且演技 ≤ 12。\n"
					+ "判定已生效，缺的只是这一句结语。",
			"condition": "A/B 公司成功 ≥ 6 ｜ 演技 ≤ 12",
		},
		{
			"id": &"fired",
			"name": "被解雇",
			"implemented": false,
			"text": "【文案待补 · 狗牙】累计失败投递 ≥ 8 且欠债。\n"
					+ "判定已生效，缺的只是这一句结语。",
			"condition": "累计失败投递 ≥ 8 ｜ 金钱 < 0",
		},
		{
			"id": &"mediocre",
			"name": "平庸",
			"implemented": true,
			"text": "三周过去了。PS5 的分期还差最后一点，日子勉强过得下去。\n"
					+ "你已经在想下一部戏了 —— 想而已。",
			# 【为什么它没有条件】它同时是**兜底档**。一条兜底如果带条件，
			# 就会出现「六条全不成立」的空洞，那种局面玩家只能看到一个空白屏幕。
			# 数值表写的是「凑齐 PS5 费但未达上述任何一条」，这里取后半句。
			"condition": "以上都不成立（兜底）",
		},
	]


## 判定。**只在第 21 天结算之后调用** —— 中途不提前结束，理由见 `WeekCycle.settle()`。
static func resolve(state: GameState) -> Dictionary:
	for e: Dictionary in all():
		if _meets(state, e["id"]):
			return e.duplicate()
	# 走不到这里（平庸恒真），留着是为了让「加了带条件的兜底」时不会静默返回空
	return (all() as Array[Dictionary])[-1].duplicate()


static func by_id(id: StringName) -> Dictionary:
	for e: Dictionary in all():
		if e["id"] == id:
			return e
	return {}


# ============================================================
static func _meets(state: GameState, id: StringName) -> bool:
	match id:
		&"actress":
			return state.acting >= _actress_acting() \
					and state.count_success_by_company_tier(["E"], RoleRequirement.Tier.LEAD) >= 1 \
					and Economy.ps5_paid_off(state)
		&"arthouse_goddess":
			return state.acting >= 18 \
					and state.count_success_by_company_tier(["D"], RoleRequirement.Tier.LEAD) >= 1
		&"extra_king":
			# 【为什么是「龙套档成功 ≥ 8」而不是 successes_total】决策 1.9 的约束二：
			# 龙套之王测**数量**（你演了多少个小角色），烂片女王测**品质**（你演了多少部烂片）。
			# 两者都写成「演得多 + 演技低」的话，玩家根本分不出区别。
			return state.count_success_by_tier(RoleRequirement.Tier.EXTRA) >= 8 and state.acting <= 12
		&"bad_movie_queen":
			return state.count_success_by_company(Broadcast.BAD_PLAY_CODES) >= 6 and state.acting <= 12
		&"fired":
			return state.failed_submissions() >= 8 and state.money < 0
		&"mediocre":
			return true
	return false


## 影后要求的演技值。数值表 3 与决策 1.9 都写 25（GDD 原稿的 30 是修订前的值）。
##
## 【为什么不再从 E 公司的门槛读过来】这两个数**刻意已经不同了**：
## 影后门槛是 25，而 E 公司的门槛在 Day 2 降到了 20 —— 因为门槛 25 越过
## 「可投递时刻的演技上限 21」，会让 E 公司永远进不去（原因见 `tools/gen_data.gd` 的 E 段）。
##
## 两件事本来就不在同一个时刻发生：
##   · **公司门槛**卡的是"提交那一刻"的演技（第 3 周内最多 21）
##   · **影后条件**在第 21 天**结算之后**才判，那时演技已经涨到 30 —— 所以 25 成立
## 之前把两者绑在一起（"从公司数据读"）本身就是个隐患：谁动了公司门槛，
## 影后的门槛会跟着偷偷变。现在它们是两个独立的数。
const ACTRESS_ACTING := 25


static func _actress_acting() -> int:
	return ACTRESS_ACTING
