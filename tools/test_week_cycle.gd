extends SceneTree
## 周末结算 + 播出反馈 + 结局判定验证 —— headless 运行，不加载任何场景与 autoload
##
##   godot --headless --path <项目目录> --script res://tools/test_week_cycle.gd
##
## 【这条链守的是什么】M2 的主干：投出去的东西要等到周末才变成钱与名声。
## 最难测、也最容易写错的四件事全在这里钉住：
##   1. 只结算**本周**的作品，上周的不会被反复结算
##   2. 结算顺序：先拿片酬，再扣房租与分期（顺序错了会出现「明明赚了钱却交不起」）
##   3. 「无知名度的龙套」是动态状态，不是一刀切
##   4. 结局的优先级 —— 影后必须压过龙套之王

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	print("")
	print("=== 周末结算 / 播出反馈 / 结局 验证 ===")
	print("")

	_test_broadcast_grades()
	_test_unnoticed_extra()
	_test_play_good()
	_test_settle_money()
	_test_settle_scope()
	_test_overdue()
	_test_headlines()
	_test_black_fame()
	_test_endings()
	_test_full_playthrough()

	print("")
	print("共 %d 项断言" % _checks)
	if _failures.is_empty():
		print("✅ 全部通过")
		quit(0)
	else:
		print("❌ %d 项失败：" % _failures.size())
		for f: String in _failures:
			print("   - " + f)
		quit(1)


func _check(label: String, got: Variant, want: Variant) -> void:
	_checks += 1
	if got != want:
		_failures.append("%s: 期望 %s，实际 %s" % [label, want, got])


# ============================================================
# 造数据的小工具
# ============================================================
## 记一笔**成功**的投递，片酬与演技按真实公司/角色数据取 ——
## 手工填数字的话，测试通过而游戏里发错钱这种事就测不出来。
func _play(s: GameState, day: int, code: String, tier: int, match_rate: float) -> Dictionary:
	var co := CompanyLibrary.by_code(code)
	var role := co.role_of(tier)
	s.day = day
	var payload := {
		"company_code": code,
		"role_tier": tier,
		"match_rate": match_rate,
		"play_title": "测试剧",
		"role_name": "测试角色",
		"payout": Economy.payout(co, role),
		"acting_gain": role.acting_gain,
	}
	s.record_submission(true, payload)
	return payload


func _entry(code: String, tier: int, match_rate: float) -> Dictionary:
	var co := CompanyLibrary.by_code(code)
	var role := co.role_of(tier)
	return {
		"company_code": code, "role_tier": tier, "match_rate": match_rate,
		"payout": Economy.payout(co, role), "acting_gain": role.acting_gain,
	}


# ============================================================
func _test_broadcast_grades() -> void:
	print("[1] 播出三档：同一份匹配度既决定过不过，也决定夸还是骂")
	var lead_high := Broadcast.evaluate(_entry("C", RoleRequirement.Tier.LEAD, 0.80), 0)
	_check("高分档", lead_high["grade"], BalanceData.Grade.HIGH)
	_check("高分·知名度 = 结果档 2 + 戏份档 3", lead_high["fame"], 5)
	_check("高分·风评 +2", lead_high["rep"], 2)
	_check("高分·负面曝光 0", lead_high["neg"], 0)

	var support_normal := Broadcast.evaluate(_entry("C", RoleRequirement.Tier.SUPPORTING, 0.50), 0)
	_check("普通档", support_normal["grade"], BalanceData.Grade.NORMAL)
	_check("普通·知名度 = 1 + 2", support_normal["fame"], 3)
	_check("普通·风评不变", support_normal["rep"], 0)
	_check("普通·负面曝光 0", support_normal["neg"], 0)

	var support_low := Broadcast.evaluate(_entry("C", RoleRequirement.Tier.SUPPORTING, 0.20), 30)
	_check("低分档", support_low["grade"], BalanceData.Grade.LOW)
	_check("低分·知名度仍 +1（骂声也让人认识你）", support_low["fame"], 3)
	_check("低分·风评 −2", support_low["rep"], -2)
	_check("低分·负面曝光 +1", support_low["neg"], 1)

	# 分档线本身
	_check("刚好 0.70 算高分", BalanceLibrary.data().grade_of(0.70), BalanceData.Grade.HIGH)
	_check("刚好 0.40 算普通", BalanceLibrary.data().grade_of(0.40), BalanceData.Grade.NORMAL)
	_check("0.39 算低分", BalanceLibrary.data().grade_of(0.39), BalanceData.Grade.LOW)
	print("   高 2+3 / 普通 1+2 / 低 1+2，风评 +2 / 0 / −2")


func _test_unnoticed_extra() -> void:
	print("[2] 「低分龙套没被注意到」—— 数值表里最容易被漏掉的一格")
	var low_extra := Broadcast.evaluate(_entry("A", RoleRequirement.Tier.EXTRA, 0.10), 0)
	_check("没名气时的低分龙套·知名度 0", low_extra["fame"], 0)
	_check("没名气时的低分龙套·风评 0", low_extra["rep"], 0)
	_check("没名气时的低分龙套·负面 0", low_extra["neg"], 0)
	_check("标记为「没被注意到」", low_extra["unnoticed"], true)

	# 已经有点名气了，同一个低分龙套就会被观众拎出来骂
	var famous := Broadcast.evaluate(_entry("A", RoleRequirement.Tier.EXTRA, 0.10), 20)
	_check("有名气时的低分龙套·知名度 1+1", famous["fame"], 2)
	_check("有名气时的低分龙套·风评 −2", famous["rep"], -2)
	_check("有名气时的低分龙套·负面 +1", famous["neg"], 1)
	_check("不再标记为没被注意到", famous["unnoticed"], false)

	# 高分的龙套就算没名气也照样被夸
	var good := Broadcast.evaluate(_entry("A", RoleRequirement.Tier.EXTRA, 0.90), 0)
	_check("高分龙套不受这条规则影响", good["fame"], 3)
	_check("高分龙套·风评 +2", good["rep"], 2)
	print("   只有「低分 + 龙套 + 还没名气」三者同时成立才归零")


func _test_play_good() -> void:
	print("[3] 好剧 / 烂剧口径")
	_check("A 厂 = 烂剧", Broadcast.play_is_good("A"), false)
	_check("B 小公司 = 烂剧", Broadcast.play_is_good("B"), false)
	_check("C 商业片 = 好剧", Broadcast.play_is_good("C"), true)
	_check("D 文艺片 = 好剧", Broadcast.play_is_good("D"), true)
	_check("E 大厂 = 好剧", Broadcast.play_is_good("E"), true)
	print("   按公司档次定（口径见 broadcast.gd 顶部注释，需狗牙确认）")


func _test_settle_money() -> void:
	print("[4] 结算顺序：先拿片酬，再扣房租与分期")
	var s := GameState.new()
	s.money = 0
	# 本周两部：A 厂主角 高分（片酬 120）、C 厂配角 普通（片酬 160）
	_play(s, 6, "A", RoleRequirement.Tier.LEAD, 0.80)
	_play(s, 7, "C", RoleRequirement.Tier.SUPPORTING, 0.50)
	s.day = 7
	s.money = 0

	var r := WeekCycle.settle(s, 1)
	_check("片酬合计", r["payout"], 120 + 160)
	_check("演技合计 = 主角 5 + 配角 2", r["acting_gain"], 7)
	_check("知名度合计 = 5 + 3", r["fame_gain"], 8)
	_check("风评合计 = +2 + 0", r["rep_gain"], 2)
	_check("负面曝光 0", r["neg_gain"], 0)
	_check("房租扣了", r["rent"], 80)
	_check("这一期分期扣了", r["ps5_paid"], 135)
	_check("没逾期", r["ps5_overdue"], false)
	# 280 − 80 − 135
	_check("期末金钱", s.money, 65)
	_check("期末演技", s.acting, 7)
	_check("期末知名度", s.fame, 8)
	_check("PS5 已付", s.ps5_paid, 135)
	_check("周报前值·金钱", int(r["before"]["money"]), 0)
	_check("周报后值·金钱", int(r["after"]["money"]), 65)
	_check("周报进了存档（微博能翻往期）", s.reports.size(), 1)
	_check("存档版周报剔掉了逐条履历原文", (s.reports[0]["plays"][0] as Dictionary).has("entry"), false)
	print("   280 片酬 − 80 房租 − 135 分期 = 65")


func _test_settle_scope() -> void:
	print("[5] 只结算本周 —— 上周的作品不会被反复结算")
	var s := GameState.new()
	s.money = 1000
	_play(s, 7, "A", RoleRequirement.Tier.EXTRA, 0.90)
	s.day = 7
	var first := WeekCycle.settle(s, 1)
	_check("第1周结算到 1 部", (first["plays"] as Array).size(), 1)

	s.day = 14
	var second := WeekCycle.settle(s, 2)
	_check("第2周没有作品可结算", (second["plays"] as Array).size(), 0)
	_check("第2周片酬为 0", second["payout"], 0)
	# 只扣房租与分期
	var before_second := 1000 + 40 - 80 - 135
	_check("第2周只剩固定支出", s.money, before_second - 80 - 135)
	print("   按 day 区间筛履历，不重复也不遗漏")


func _test_overdue() -> void:
	print("[6] 逾期：付不出分期不扣钱，只扣风评")
	var s := GameState.new()
	s.money = 10
	s.reputation = 0
	s.day = 7
	var r := WeekCycle.settle(s, 1)
	_check("标记为逾期", r["ps5_overdue"], true)
	_check("这一期没付", r["ps5_paid"], 0)
	_check("累计已付仍是 0", s.ps5_paid, 0)
	_check("风评被罚", r["ps5_penalty"], 5)
	_check("风评", s.reputation, -5)
	# 房租先扣：10 − 80 = −70。**逾期不扣钱** —— 既没交钱又扣钱等于一罚两遍
	_check("金钱扣成负数（欠债来源）", s.money, -70)
	_check("欠债时也没凑齐", Economy.ps5_paid_off(s), false)
	# 反证：如果逾期也扣钱，会是 −70 − 135 = −205
	_check("确认逾期没有动钱", s.money != -205, true)
	print("   10 − 80 = −70，这就是「欠债 = 金钱 < 0」的唯一起源")


func _test_headlines() -> void:
	print("[7] 电子报头条")
	var bal := BalanceLibrary.data()
	var s := GameState.new()
	_check("标题库读到了", HeadlineLibrary.count() > 0, true)

	# 没名气 + 主要角色 → 用角色定位称呼
	var b_lead := _play_result("B", RoleRequirement.Tier.LEAD, 0.80, 0)
	var low_fame := HeadlineComposer.compose(b_lead, s, 0)
	_check("取到了标题", String(low_fame["text"]).is_empty(), false)
	_check("没有残留的【xx】字段", MailComposer.find_leftovers(String(low_fame["text"])), [] as Array[String])
	_check("没名气时用角色定位，不直呼玩家名",
			String(low_fame["text"]).contains("主角") and not String(low_fame["text"]).contains("小满"), true)

	# 有知名度 → 直接点名
	var famous := HeadlineComposer.compose(b_lead, s, bal.fame_named_threshold)
	_check("过了门槛就直呼玩家名", String(famous["text"]).contains("小满"), true)

	# 龙套高分 + 已有名气 + 首次 → 找人标题，且只出一次
	var star_play := _play_result("C", RoleRequirement.Tier.EXTRA, 0.90, bal.fame_named_threshold)
	var star := HeadlineComposer.compose(star_play, s_with_star(false), bal.fame_named_threshold)
	_check("龙套首次出圈用「找人」标题", String(star["kind"]), String(Headline.KIND_EXTRA_STAR))
	var again := HeadlineComposer.compose(star_play, s_with_star(true), bal.fame_named_threshold)
	_check("出过圈之后不再用「找人」标题",
			String(again["kind"]) == String(Headline.KIND_EXTRA_STAR), false)

	# D 高分但没有烂剧经历 → 换备选（主表那句「谁说只会演烂剧」会穿帮）
	var d_res := _play_result("D", RoleRequirement.Tier.LEAD, 0.80, 0)
	var d_plain := HeadlineComposer.compose(d_res, GameState.new(), 0)
	_check("没演过烂剧时 D 高分走备选",
			String(d_plain["kind"]), String(Headline.KIND_FALLBACK_D_HIGH))
	var d_veteran := GameState.new()
	d_veteran.record_submission(true, {"company_code": "A", "role_tier": 0})
	# 【注意比的是 id 不是 kind】kind 只对 SPECIAL 类的标题有值，
	# 主表和龙套表的标题靠 (公司, 档位) 或 (档位, 剧好不好) 定位。
	_check("演过烂剧就用主表那条", String(HeadlineComposer.compose(d_res, d_veteran, 0)["id"]),
			String(HeadlineLibrary.find_main("D", BalanceData.Grade.HIGH).id))
	print("   报道对象按知名度切换：角色名 / 角色定位 / 玩家名")


## 造一份与 WeekCycle 产出形状一致的「播出结果」
## —— 真实路径是 `res["entry"] = entry`，测试必须走同样的形状，
## 否则测的是另一个东西。
func _play_result(code: String, tier: int, match_rate: float, fame: int) -> Dictionary:
	var e := _entry(code, tier, match_rate)
	var res := Broadcast.evaluate(e, fame)
	res["entry"] = e
	return res


func s_with_star(seen: bool) -> GameState:
	var s := GameState.new()
	s.extra_star_seen = seen
	return s


func _test_black_fame() -> void:
	print("[8] 黑红：不是成就系统，只是一条微博标题")
	var s := GameState.new()
	s.money = 1000
	s.negative_exposure = 4
	s.day = 7
	var r1 := WeekCycle.settle(s, 1)
	_check("负面曝光 4 < 5 不触发", r1["black_fame"], false)

	var t := GameState.new()
	t.money = 1000
	t.negative_exposure = 5
	t.day = 7
	var r2 := WeekCycle.settle(t, 1)
	_check("负面曝光 5 触发黑红", r2["black_fame"], true)
	_check("标记已出现", t.black_fame_seen, true)
	var first_black := String((r2["headlines"] as Array)[(r2["headlines"] as Array).size() - 1])
	_check("黑红标题点到玩家名", first_black.contains("小满"), true)
	_check("黑红标题没有残留字段", MailComposer.find_leftovers(first_black), [] as Array[String])

	# 之后那一周没有新增负面曝光 → 不再重复出现
	t.day = 14
	var r3 := WeekCycle.settle(t, 2)
	_check("没有新负面就不重复曝光", r3["black_fame"], false)
	print("   首次是惊奇，之后要靠「本周又有新负面」才重复")


func _test_endings() -> void:
	print("[9] 结局判定与优先级")
	var bal := BalanceLibrary.data()

	# 影后：E 公司主角 + 演技 25 + PS5 付清
	var champ := GameState.new()
	champ.acting = 25
	champ.ps5_paid = bal.ps5_total
	champ.record_submission(true, {"company_code": "E", "role_tier": RoleRequirement.Tier.LEAD})
	_check("影后成立", String(EndingResolver.resolve(champ)["id"]), "actress")

	# 少一样就不成立：PS5 没付清
	var no_ps5 := GameState.new()
	no_ps5.acting = 25
	no_ps5.ps5_paid = 270
	no_ps5.record_submission(true, {"company_code": "E", "role_tier": RoleRequirement.Tier.LEAD})
	_check("没凑齐 PS5 费就不是影后", String(EndingResolver.resolve(no_ps5)["id"]) != "actress", true)

	# 龙套之王：8 次龙套成功 + 演技 ≤ 12
	var king := GameState.new()
	for i in 8:
		king.acting += 1
		king.record_submission(true, {"company_code": "A", "role_tier": RoleRequirement.Tier.EXTRA})
	_check("龙套之王成立", String(EndingResolver.resolve(king)["id"]), "extra_king")

	# ★优先级：同时满足影后与龙套之王时必须判影后 ——
	# 否则「演技 25 但早年演过 8 个龙套」的玩家会拿到一句「你一直没红」
	var both := GameState.new()
	for i in 8:
		both.record_submission(true, {"company_code": "A", "role_tier": RoleRequirement.Tier.EXTRA})
	both.acting = 25
	both.ps5_paid = bal.ps5_total
	both.record_submission(true, {"company_code": "E", "role_tier": RoleRequirement.Tier.LEAD})
	_check("同时满足时影后优先", String(EndingResolver.resolve(both)["id"]), "actress")

	# 平庸兜底
	var nothing := GameState.new()
	_check("什么都没做 → 平庸", String(EndingResolver.resolve(nothing)["id"]), "mediocre")

	# 文艺片女神：判定已生效，文案仍是占位 —— 但**不能**掉到龙套之王去
	var arthouse := GameState.new()
	arthouse.acting = 20
	arthouse.record_submission(true, {"company_code": "D", "role_tier": RoleRequirement.Tier.LEAD})
	var a := EndingResolver.resolve(arthouse)
	_check("文艺片女神判定生效", String(a["id"]), "arthouse_goddess")
	_check("但文案还没补（界面上要标出来）", a["implemented"], false)

	# 【两个门槛刻意不同，别把它们绑回去】影后要 25，E 公司门槛是 20。
	# 影后在第 21 天**结算之后**才判，那时演技已经涨到 30 —— 所以 25 成立；
	# 卡住玩家的从来只是「提交那一刻的演技」（上限 21，见 1.11 第 10 条）。
	_check("影后要 25 点演技", EndingResolver.by_id(&"actress")["condition"].contains("25"), true)
	_check("E 公司门槛低于影后门槛 —— 否则影后就是死结局",
			CompanyLibrary.by_code("E").acting_threshold < EndingResolver.ACTRESS_ACTING, true)
	print("   影后 > 文艺片女神 > 龙套之王 > 烂片女王 > 被解雇 > 平庸")


func _test_full_playthrough() -> void:
	print("[10] 三周完整跑通 —— 数值表说的「低于 7 次成功投递必定破产」对不对")
	var s := GameState.new()
	s.money = BalanceLibrary.data().init_money
	var settled := 0
	var endings: Array[String] = []
	# 一个「够努力但不精致」的玩家：每周投递 4 次 A 厂龙套（匹配 0.5 → 普通档）、
	# 打工 2 次，第 7 天什么都不做 —— 每天 1 点行动点刚好用掉 6 点、浪费 1 点。
	for week in GameState.WEEKS:
		s.work_this_week = 0
		for d in GameState.DAYS_PER_WEEK:
			s.day = week * GameState.DAYS_PER_WEEK + d + 1
			s.ap_left_today = GameState.AP_PER_DAY
			if d < 4:
				s.spend_ap()
				_play(s, s.day, "A", RoleRequirement.Tier.EXTRA, 0.50)
			elif d < 6:
				s.spend_ap()
				s.work_this_week += 1
				s.money += Economy.work_income()
		s.day = week * GameState.DAYS_PER_WEEK + GameState.DAYS_PER_WEEK
		var r := WeekCycle.settle(s, week + 1)
		settled += 1
		endings.append(String(r["ending"].get("id", &"")))

	_check("三周都结算了", settled, 3)
	_check("第 3 周结束时判出结局", String(s.ending_id).is_empty(), false)
	_check("本局结束", s.finished, true)
	_check("结局是提前算好的那一个", endings[2], String(s.ending_id))
	# 账要平：初始 200 + 三周打工 6×30 + 片酬(12 次 A 龙套 40) − 房租 240 − 分期 405
	var expect := 200 + 30 * 6 + 40 * 12 - 80 * 3 - 135 * 3
	_check("三周后金钱等于手算结果", s.money, expect)
	_check("每周都付上了分期", s.ps5_paid, 405)
	_check("凑齐 PS5 费", Economy.ps5_paid_off(s), true)
	_check("12 次投递全成功（A 厂龙套 40% 线很好过）", s.successes_total, 12)
	# 演技 = 12 次龙套 ×1 = 12 ≤ 12 → 龙套之王
	_check("结局 = 龙套之王", String(s.ending_id), "extra_king")
	_check("周报存了三期", s.reports.size(), 3)
	print("   200 + 180 + 480 − 240 − 405 = %d，按期付清了 PS5" % expect)
	print("   12 次成功里全是龙套且演技停在 12 → 龙套之王")
	print("   ★低于 7 次成功投递必定中途破产 —— 这条路线刚好压线活下来")
