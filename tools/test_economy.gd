extends SceneTree
## 经济层验证 —— headless 运行，不加载任何场景与 autoload
##
##   godot --headless --path <项目目录> --script res://tools/test_economy.gd
##
## 【为什么要单独测】经济是「能不能活到结局」的唯一裁判。
## 数值表里那三行 ★校验（3 周固定支出 645 / 保底收入 380 / 缺口 265）
## 此前只是表格里的一段说明，这里是它们的可执行版本 ——
## 谁改了房租或分期，这几条断言会立刻告诉他还活不活得下去。

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	print("")
	print("=== 经济层验证 ===")
	print("")

	_test_balance_mirror()
	_test_payout_matrix()
	_test_action_gates()
	_test_cashflow()
	_test_ps5()
	_test_threshold_ceiling()

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


func _check_close(label: String, got: float, want: float) -> void:
	_checks += 1
	if absf(got - want) > 0.0001:
		_failures.append("%s: 期望 %f，实际 %f" % [label, want, got])


# ============================================================
func _test_balance_mirror() -> void:
	print("[1] 数值镜像 == 数值表")
	var b := BalanceLibrary.data()
	_check("读到了数值镜像", b != null, true)
	_check("自检没有硬伤", b.validate(), [] as Array[String])

	# 这些数字必须逐条对得上 docs/数值表_v1.xlsx。
	# 【为什么写死而不从别处推】这里就是「文档与代码是否一致」的那道闸门，
	# 从别处推等于自己证明自己。
	_check("初始金钱", b.init_money, 200)
	_check("房租/周", b.rent_per_week, 80)
	_check("打工收入/次", b.work_income, 30)
	_check("打工每周限次", b.work_max_per_week, 2)
	_check("表演课价格", b.class_price, 100)
	_check("表演课收益", b.class_gain, 3)
	_check("表演课每周限次", b.class_max_per_week, 1)
	_check("演技上限", b.acting_cap, 30)
	_check("PS5 总额", b.ps5_total, 405)
	_check("PS5 每期", b.ps5_amount_per, 135)
	_check("PS5 分期数", b.ps5_installments, 3)
	_check("逾期惩罚（风评）", b.ps5_overdue_rep_penalty, 5)
	_check("高分线", b.grade_high_line, 0.7)
	_check("普通线", b.grade_normal_line, 0.4)
	_check("点名门槛（知名度）", b.fame_named_threshold, 20)
	_check("黑红门槛（负面曝光）", b.black_fame_threshold, 5)
	print("   镜像与数值表逐条一致，且分期加得出总额")


func _test_payout_matrix() -> void:
	print("[2] 片酬矩阵：钱由公司档次决定，与演技无关")
	var want := {"A": 40, "B": 64, "C": 80, "D": 96, "E": 120}
	for code: String in want:
		var co := CompanyLibrary.by_code(code)
		_check("%s 公司存在" % code, co != null, true)
		if co == null:
			continue
		var extra := co.role_of(RoleRequirement.Tier.EXTRA)
		var support := co.role_of(RoleRequirement.Tier.SUPPORTING)
		var lead := co.role_of(RoleRequirement.Tier.LEAD)
		_check("%s 龙套片酬" % code, Economy.payout(co, extra), want[code])
		_check("%s 配角片酬 = 龙套 ×2" % code, Economy.payout(co, support), int(want[code]) * 2)
		_check("%s 主角片酬 = 龙套 ×3" % code, Economy.payout(co, lead), int(want[code]) * 3)
	# 空角色要给 0，而不是崩
	_check("角色为空时片酬 0", Economy.payout(CompanyLibrary.by_code("A"), null), 0)
	print("   A40/B64/C80/D96/E120，配角 ×2、主角 ×3")


func _test_action_gates() -> void:
	print("[3] 打工 / 上课的门槛")
	var s := GameState.new()
	s.money = 200

	_check("开局可以打工", Economy.can_work(s), true)
	_check("开局可以上课", Economy.can_take_class(s), true)

	s.spend_ap()
	_check("行动点用掉后打不了工", Economy.can_work(s), false)
	_check("没行动点的原因写清楚了", Economy.work_block_reason(s), Economy.REASON_AP)
	_check("没行动点时也上不了课", Economy.can_take_class(s), false)

	# 次数上限
	s.ap_left_today = 1
	s.work_this_week = 2
	_check("本周打满 2 次后打不了工", Economy.can_work(s), false)
	_check("周次数用尽的原因带数字", "2" in Economy.work_block_reason(s), true)
	_check("打工次数不影响上课", Economy.can_take_class(s), true)

	# 学费
	s.money = 99
	_check("钱不够交学费", Economy.can_take_class(s), false)
	_check("学费不足的原因写清楚了", "学费" in Economy.class_block_reason(s), true)
	s.money = 100
	_check("刚好够学费", Economy.can_take_class(s), true)

	# 演技到顶
	s.acting = 30
	_check("演技到顶后上不了课", Economy.can_take_class(s), false)
	_check("到顶的原因写清楚了", "到顶" in Economy.class_block_reason(s), true)

	# 结局之后一切都停
	s.money = 500
	s.acting = 0
	s.finished = true
	_check("本局结束后打不了工", Economy.can_work(s), false)
	_check("结束的原因写清楚了", Economy.work_block_reason(s), Economy.REASON_FINISHED)
	print("   行动点 → 周上限 → 学费 → 演技上限，顺序固定")


func _test_cashflow() -> void:
	print("[4] ★3 周现金流（数值表 sheet 2 的校验）")
	# 固定支出
	var fixed := Economy.rent() * GameState.WEEKS + Economy.ps5_total()
	_check("3 周固定支出", fixed, 645)
	# 保底收入：初始 + 三周打工拉满
	var floor_income := BalanceLibrary.data().init_money \
			+ Economy.work_income() * BalanceLibrary.data().work_max_per_week * GameState.WEEKS
	_check("3 周保底收入", floor_income, 380)
	var gap := fixed - floor_income
	_check("必须靠片酬补的缺口", gap, 265)
	# 缺口换算成最便宜的 A 厂龙套
	var extra_payout := Economy.payout(CompanyLibrary.by_code("A"),
			CompanyLibrary.by_code("A").role_of(RoleRequirement.Tier.EXTRA))
	_check("A 厂龙套片酬", extra_payout, 40)
	_check("缺口 ÷ 龙套片酬 向上取整 = 7", ceili(float(gap) / float(extra_payout)), 7)
	# 投递上限够不够：3 周最多 12 次
	_check("12 次投递上限够不够 7 次成功", GameState.MAX_SUBMIT_PER_WEEK * GameState.WEEKS >= 7, true)
	# 反例：如果三周都上课，缺口涨到 565，需要 15 次 A 龙套 > 12 次上限 —— 数学上破产
	var with_class := gap + Economy.class_fee() * GameState.WEEKS
	_check("三周全上课的缺口", with_class, 565)
	_check("15 次 > 12 次投递上限（所以不能三周都上课）",
			ceili(float(with_class) / float(extra_payout)) > GameState.MAX_SUBMIT_PER_WEEK, true)
	print("   645 − 380 = 265 → 至少 7 次成功投递；三周全上课必破产")
	print("   投递 12 + 上课 3 + 打工 6 = 21 点，正好等于总行动点（零冗余）")
	var ap_used := GameState.MAX_SUBMIT_PER_WEEK * GameState.WEEKS \
			+ BalanceLibrary.data().class_max_per_week * GameState.WEEKS \
			+ BalanceLibrary.data().work_max_per_week * GameState.WEEKS
	_check("三项拉满正好吃掉全部行动点", ap_used, GameState.TOTAL_AP)


func _test_ps5() -> void:
	print("[5] PS5 分期")
	_check("第1周该交一期", Economy.ps5_due_for_week(1), 135)
	_check("第2周该交一期", Economy.ps5_due_for_week(2), 135)
	_check("第3周该交一期", Economy.ps5_due_for_week(3), 135)
	_check("第4周不再交（游戏已经结束了）", Economy.ps5_due_for_week(4), 0)
	_check("三期之和 = 总额",
			Economy.ps5_amount() * BalanceLibrary.data().ps5_installments, Economy.ps5_total())

	var s := GameState.new()
	_check("没付过钱 = 没凑齐", Economy.ps5_paid_off(s), false)
	_check("已付期数 0", Economy.ps5_installments_paid(s), 0)
	s.ps5_paid = 270
	_check("付了两期还没凑齐", Economy.ps5_paid_off(s), false)
	_check("已付期数 2", Economy.ps5_installments_paid(s), 2)
	s.ps5_paid = 405
	_check("付满三期 = 凑齐", Economy.ps5_paid_off(s), true)
	_check("到期日：第1周 → 第7天", WeekCycle.next_installment_day(_at_day(3)), 7)
	_check("到期日：第2周 → 第14天", WeekCycle.next_installment_day(_at_day(9)), 14)
	_check("付清后没有到期日", WeekCycle.next_installment_day(_paid(405)), 0)
	print("   3 期 × 135 = 405，第 7 / 14 / 21 天各一期")


func _at_day(d: int) -> GameState:
	var s := GameState.new()
	s.day = d
	return s


func _paid(n: int) -> GameState:
	var s := GameState.new()
	s.ps5_paid = n
	return s


## 【这条护栏是给设计者的】公司演技门槛一旦越过「一周之内能给到的演技」，那家公司就
## **永远进不去**，挂在它上面的结局随之变成死结局。
##
## Day 2 真踩过这个坑：E 门槛写 25，而演技能达到的上限是 21 ——
## 「影后」整整一轮不可达，直到数值模拟器把它跑出来才被发现（见 1.11 第 10 条）。
## 所以这里把上限算出来钉住，而不是等下一次模拟。
func _test_threshold_ceiling() -> void:
	print("[6] ★公司门槛必须落在「一周内能给到的演技」之下")
	var class_gain := Economy.class_gain()
	var submits_per_week := GameState.MAX_SUBMIT_PER_WEEK
	var extra_gain := CompanyLibrary.by_code("A").role_of(RoleRequirement.Tier.EXTRA).acting_gain
	var support_gain := CompanyLibrary.by_code("A").role_of(RoleRequirement.Tier.SUPPORTING).acting_gain

	# 【推导依据】演技的增量在**周末结算**时才兑现，只有表演课是即时的（当天交钱当天涨）。
	# 所以每周之内演技是冻结的，能演哪个档位由**上周结束时**的演技决定：
	#   第 1 周：进来是 0，只能演龙套 → 4×1 + 表演课 3
	#   第 2 周：进来是 7，够配角（≥5）、不够主角（≥15）→ 4×2 + 表演课 3
	#   第 3 周：进来是 18，表演课 +3 = 21，然后这一周就结束了
	var w1 := submits_per_week * extra_gain + class_gain
	var w2 := w1 + submits_per_week * support_gain + class_gain
	var ceiling := w2 + class_gain
	_check("第 1 周结束时的演技", w1, 7)
	_check("第 2 周结束时的演技", w2, 18)
	_check("★可投递时刻的演技上限", ceiling, 21)

	for code: String in ["A", "B", "C", "D", "E"]:
		var co := CompanyLibrary.by_code(code)
		_check("%s 门槛 %d 不超过上限 %d" % [code, co.acting_threshold, ceiling],
				co.acting_threshold <= ceiling, true)
	# 影后的门槛与 E 公司的门槛**刻意不同**，别把它们绑回去
	_check("影后要 25 点演技（它在第 21 天结算之后判，那时演技已到 30）",
			EndingResolver.ACTRESS_ACTING, 25)
	print("   上限 %d —— 任何公司门槛越过它，那家公司就永远进不去，挂它的结局变死结局" % ceiling)
