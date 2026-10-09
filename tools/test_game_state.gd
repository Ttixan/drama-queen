extends SceneTree
## GameState 验证 —— headless 运行，不加载任何场景与 autoload
##
##   godot --headless --path <项目目录> --script res://tools/test_game_state.gd
##
## 【为什么要单独测】GameState 是纯 RefCounted，不依赖 EventBus / Game 单例。
## 这条独立性就是数值模拟器能跑几千局的前提 —— 本测试同时是这条架构约束的回归测试。

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	print("")
	print("=== GameState 验证 ===")
	print("")

	_test_constants()
	_test_ap()
	_test_week_boundary()
	_test_submission_counters()
	_test_dragon_extra_ending()
	_test_fired_ending()
	_test_save_roundtrip()

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
func _test_constants() -> void:
	print("[1] 常量")
	_check("总天数", GameState.TOTAL_DAYS, 21)
	_check("周数", GameState.WEEKS, 3)
	_check("总行动点", GameState.TOTAL_AP, 21)
	_check("每周投递上限", GameState.MAX_SUBMIT_PER_WEEK, 4)
	print("   21天 = 3周×7天，行动点 21 —— 全局最硬的资源")


func _test_ap() -> void:
	print("[2] 行动点")
	var s := GameState.new()
	_check("初始行动点", s.ap_left_today, 1)
	_check("第1次消耗", s.spend_ap(), true)
	_check("消耗后剩余", s.ap_left_today, 0)
	_check("同一天再消耗应失败", s.spend_ap(), false)

	s.advance_day()
	_check("次日行动点恢复", s.ap_left_today, 1)
	print("   一天 1 点，用了就没了")


func _test_week_boundary() -> void:
	print("[3] 跨周")
	var s := GameState.new()
	_check("第1天所在周", s.week(), 1)

	# 第 1~6 天推进都不该跨周
	for i in 6:
		var crossed := s.advance_day()
		_check("第%d天不跨周" % (i + 2), crossed, false)
	_check("推进到第7天", s.day, 7)
	_check("第7天是周末", s.is_week_end(), true)

	var crossed := s.advance_day()
	_check("第7→8天跨周", crossed, true)
	_check("进入第2周", s.week(), 2)
	_check("第2周第1天", s.day_of_week(), 1)

	# 一路推进到最后一天
	while not s.is_last_day():
		s.advance_day()
	_check("最终停在第21天", s.day, 21)
	_check("最终是第3周", s.week(), 3)
	print("   21 天推进正确，周末判定正确")


func _test_submission_counters() -> void:
	print("[4] 投递计数")
	var s := GameState.new()
	_check("初始可投递", s.can_submit(), true)

	# 本周投满 4 次
	for i in 4:
		s.record_submission(i == 0, {"company_code": "A", "role_tier": 0})
	_check("本周投递数", s.submissions_this_week, 4)
	_check("累计投递数", s.submissions_total, 4)
	_check("成功次数", s.successes_total, 1)
	_check("连续无成功天数", s.days_without_success, 3)
	_check("本周额度用尽后不可投", s.can_submit(), false)

	# 跨周后额度恢复
	s.advance_day()  # 第1天 → 第2天
	_check("未跨周时仍不可投", s.can_submit(), false)
	while not s.is_week_end():
		s.advance_day()
	s.advance_day()  # 跨周
	_check("跨周后本周计数清零", s.submissions_this_week, 0)
	_check("跨周后恢复可投", s.can_submit(), true)
	_check("累计投递数不清零", s.submissions_total, 4)
	print("   周额度会重置，累计数不会")


## 「龙套之王」与「烂片女王」的口径验证
##
## 这两个结局必须测【不同的东西】，否则玩家分不出它们的区别：
##   龙套之王 = 数量 —— 成功了 8 次，但全是龙套（演技上不去）
##   烂片女王 = 品质 —— 成功了 6 次，但全是 A/B 两家的烂片
##
## 另有一条数学死结要守住：演技单调递增，所以「成功演出 ≥ N」必然推出「演技 ≥ N」。
## 任何写成「成功 ≥ N 且 演技 ≤ M」的结局，必须有 M > N，否则条件自相矛盾。
func _test_dragon_extra_ending() -> void:
	print("[5] 龙套之王 / 烂片女王 口径")
	var s := GameState.new()
	# 演 8 次龙套，全在 A 烂片厂，演技 8
	for i in 8:
		s.acting += 1
		s.record_submission(true, {"company_code": "A", "role_tier": RoleRequirement.Tier.EXTRA})

	_check("成功次数", s.successes_total, 8)
	_check("龙套档成功次数", s.count_success_by_tier(RoleRequirement.Tier.EXTRA), 8)
	_check("A/B 公司成功次数", s.count_success_by_company(["A", "B"]), 8)
	_check("演技", s.acting, 8)

	var king := s.count_success_by_tier(RoleRequirement.Tier.EXTRA) >= 8 and s.acting <= 12
	_check("龙套之王达成（龙套≥8 且 演技≤12）", king, true)

	# 反证：8 次龙套成功必然带来 ≥8 点演技，旧口径「演技≤5」永远不可达 ——
	# 这正是原稿那个死结，涨到 12 才解得开。
	var dead := s.count_success_by_tier(RoleRequirement.Tier.EXTRA) >= 8 and s.acting <= 5
	_check("旧口径（演技≤5）不可达 —— 证明上限必须 >8", dead, false)

	# ---- 烂片女王走的是另一条路：成功次数够，但龙套不够多 ----
	var q := GameState.new()
	for i in 4:
		q.acting += 1
		q.record_submission(true, {"company_code": "A", "role_tier": RoleRequirement.Tier.EXTRA})
	for i in 2:
		q.acting += 2
		q.record_submission(true, {"company_code": "B", "role_tier": RoleRequirement.Tier.SUPPORTING})

	_check("烂片女王·成功次数", q.successes_total, 6)
	_check("烂片女王·龙套只演了 4 次", q.count_success_by_tier(RoleRequirement.Tier.EXTRA), 4)
	_check("龙套之王不成立（龙套不足 8）",
			q.count_success_by_tier(RoleRequirement.Tier.EXTRA) >= 8, false)
	_check("烂片女王成立（A/B 成功 6 次 且 演技 8≤12）",
			q.count_success_by_company(["A", "B"]) >= 6 and q.acting <= 12, true)
	print("   两个结局走不同的路 —— 一个看数量，一个看品质")


## 「被解雇」的口径验证
func _test_fired_ending() -> void:
	print("[6] 被解雇 / 欠债 口径")
	var s := GameState.new()
	for i in 9:
		s.record_submission(false, {"company_code": "A", "role_tier": 0})

	_check("投递次数", s.submissions_total, 9)
	_check("失败次数", s.failed_submissions(), 9)

	s.money = -10
	_check("被解雇达成（失败≥8 且 金钱<0）", s.failed_submissions() >= 8 and s.money < 0, true)
	s.money = 5
	_check("不欠债则不触发", s.failed_submissions() >= 8 and s.money < 0, false)
	print("   欠债 = 金钱为负，失败次数 = 投递数 − 成功数")


func _test_save_roundtrip() -> void:
	print("[7] 存档往返")
	var s := GameState.new()
	s.money = 1234
	s.acting = 17
	s.fame = 42
	s.reputation = -3
	s.negative_exposure = 8
	s.advance_day()
	s.advance_day()
	s.record_submission(true, {"company_code": "C", "role_tier": 2, "match_rate": 0.75})
	s.record_submission(false, {"company_code": "D", "role_tier": 1, "match_rate": 0.4})

	# 走一遍真实的序列化路径（JSON 会把整数变成浮点，这是最容易踩的坑）
	var blob := JSON.stringify(s.to_save_dict())
	var parsed: Variant = JSON.parse_string(blob)
	_check("存档可解析", typeof(parsed), TYPE_DICTIONARY)

	var r := GameState.new()
	r.from_save_dict(parsed)

	_check("存档·金钱", r.money, 1234)
	_check("存档·演技", r.acting, 17)
	_check("存档·知名度", r.fame, 42)
	_check("存档·风评", r.reputation, -3)
	_check("存档·负面曝光", r.negative_exposure, 8)
	_check("存档·天数", r.day, s.day)
	_check("存档·行动点", r.ap_left_today, s.ap_left_today)
	_check("存档·投递数", r.submissions_total, 2)
	_check("存档·成功数", r.successes_total, 1)
	_check("存档·履历条数", r.history.size(), 2)
	_check("存档·履历可查主角经历", r.has_ever_played(RoleRequirement.Tier.LEAD), true)
	print("   JSON 往返后属性与履历完整还原")
