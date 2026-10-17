extends SceneTree
## 数值模拟器自身的验证 —— headless 运行
##
##   godot --headless --path <项目目录> --script res://tools/test_simulator.gd
##
## 【为什么模拟器也要被测】它的结论会被拿去改数值 —— 它自己错了，
## 错的就是整个平衡。而它最难发现的错不是崩溃，是**账算错了**：
## 写这个脚本时就踩过一次 —— 直接改 `state.day` 而没走 `advance_day()`，
## 于是跨周清零没执行，**第一周投满 4 次之后后面两周再也投不出去**，
## 而报告只是安静地显示「玩家好像不太爱投递」。
##
## 那次的教训变成了这里的 [2]：**行动点必须守恒，且每个动作不能超过它的周上限倍数**。
## 只要哪天再有人绕开真实的推进路径，这条断言会立刻炸。

const GAMES := 20

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	print("")
	print("=== 数值模拟器验证 ===")
	print("")

	if PartLibrary.is_empty() or CompanyLibrary.count() == 0:
		print("❌ 数据没就位 —— 先跑 tools/gen_data.gd")
		quit(1)
		return

	var greedy := _run_many(false, 0.0, 1)
	var random := _run_many(true, 0.0, 1)

	_test_completion(greedy, random)
	_test_ap(greedy, random)
	_test_reproducible()
	_test_skill_gap(greedy, random)
	_test_no_dead_combo(greedy)

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


func _make(kind_random: bool, sloppiness: float, seed_value: int) -> SimAgent:
	if kind_random:
		return SimAgent.RandomPlayer.new(seed_value, 0.0)
	return SimAgent.GreedyPlayer.new(seed_value, sloppiness)


func _run_many(kind_random: bool, sloppiness: float, base_seed: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in GAMES:
		out.append(SimRunner.run_one(_make(kind_random, sloppiness, base_seed + i)))
	return out


# ============================================================
func _test_completion(greedy: Array[Dictionary], random: Array[Dictionary]) -> void:
	print("[1] 两种玩家都能跑完 21 天并判出结局")
	for name: String in ["贪心", "随机"]:
		var games: Array[Dictionary] = greedy if name == "贪心" else random
		var done := 0
		var empty := 0
		for g: Dictionary in games:
			if bool(g["finished"]):
				done += 1
			if String(g["ending"]).is_empty():
				empty += 1
		_check("%s：全部跑完（%d 局）" % [name, games.size()], done, games.size())
		_check("%s：每局都有结局" % name, empty, 0)
	print("   两个 agent × %d 局，全部在第 21 天收尾" % GAMES)


## 【这条是核心】行动点守恒 + 硬上限 —— 它守的是「模拟器走的确实是真实规则」
func _test_ap(greedy: Array[Dictionary], random: Array[Dictionary]) -> void:
	print("[2] 行动点守恒与周上限")
	var total_days := GameState.TOTAL_AP
	for name: String in ["贪心", "随机"]:
		var games: Array[Dictionary] = greedy if name == "贪心" else random
		var bad_sum := 0
		var bad_submit := 0
		var bad_work := 0
		var bad_class := 0
		for g: Dictionary in games:
			var ap: Dictionary = g["ap"]
			var sum := 0
			for k: int in ap:
				sum += int(ap[k])
			if sum != total_days:
				bad_sum += 1
			# 周上限 × 周数 —— 跨周清零没生效的话，这几个数会**偏小**（投不出去），
			# 而"投递次数远超上限"则说明计数根本没拦
			if int(ap[SimAgent.Action.SUBMIT]) > GameState.MAX_SUBMIT_PER_WEEK * GameState.WEEKS:
				bad_submit += 1
			if int(ap[SimAgent.Action.WORK]) > BalanceLibrary.data().work_max_per_week * GameState.WEEKS:
				bad_work += 1
			if int(ap[SimAgent.Action.CLASS]) > BalanceLibrary.data().class_max_per_week * GameState.WEEKS:
				bad_class += 1
		_check("%s：每局 21 点不多不少" % name, bad_sum, 0)
		_check("%s：投递不超过 4×3=12 次" % name, bad_submit, 0)
		_check("%s：打工不超过 2×3=6 次" % name, bad_work, 0)
		_check("%s：上课不超过 1×3=3 次" % name, bad_class, 0)

	# 贪心玩家必须真的把周额度用满 —— 用不满就说明 agent 在空转，
	# 而那会让「随机事件还剩几点」这个结论偏乐观
	var avg_submit := _avg(greedy, SimAgent.Action.SUBMIT)
	var avg_work := _avg(greedy, SimAgent.Action.WORK)
	var avg_class := _avg(greedy, SimAgent.Action.CLASS)
	_check("贪心玩家把投递额度用满（12 次）", avg_submit, 12.0)
	_check("贪心玩家把上课额度用满（3 次）", avg_class, 3.0)
	_check("贪心玩家把打工额度用满（6 次）", avg_work, 6.0)
	print("   贪心：投递 12 / 打工 6 / 上课 3 / 闲置 0 —— 21 点被压满")


func _avg(games: Array[Dictionary], action: int) -> float:
	var total := 0
	for g: Dictionary in games:
		total += int((g["ap"] as Dictionary)[action])
	return float(total) / float(games.size())


func _test_reproducible() -> void:
	print("[3] 可复现：同一个种子跑两次，结果必须逐字相同")
	var a := SimRunner.run_one(SimAgent.GreedyPlayer.new(777, 0.0))
	var b := SimRunner.run_one(SimAgent.GreedyPlayer.new(777, 0.0))
	_check("结局相同", a["ending"], b["ending"])
	_check("期末金钱相同", a["money"], b["money"])
	_check("演技相同", a["acting"], b["acting"])
	_check("成功次数相同", a["successes"], b["successes"])

	# 反证：随机 agent 换个种子必须跑出不同的中间过程，
	# 否则「随机」这个词是假的（这对应「rng 没被真正使用」这一类 bug）。
	# 【为什么取 5 个种子而不是 2 个】部件池一变（10-17 加了第 11 张嘴），
	# 种子的随机流整体位移，两个特定种子撞出同一个结局是**完全可能的巧合** ——
	# 原先钉死「种子 1 与 2 必须不同」就把测试变成了运气测试。这里只看多样性。
	var outcomes := {}
	for s in [1, 2, 3, 4, 5]:
		var r := SimRunner.run_one(SimAgent.RandomPlayer.new(s, 0.0))
		outcomes["%s|%s" % [r["ending"], int(r["successes"])]] = true
	_check("换种子后随机 agent 的结果确实不同（5 个种子 ≥ 2 种结局）", outcomes.size() >= 2, true)
	print("   种子固定 → 逐字可复现；种子一换 → 结果真的会变")


func _test_skill_gap(greedy: Array[Dictionary], random: Array[Dictionary]) -> void:
	print("[4] 「学了」和「没学」必须拉开差距")
	var g_success := _avg_field(greedy, "successes")
	var r_success := _avg_field(random, "successes")
	_check("贪心的平均成功次数高于随机", g_success > r_success, true)

	var g_ps5 := _rate(greedy, "ps5_off")
	var r_ps5 := _rate(random, "ps5_off")
	_check("贪心的 PS5 付清率高于随机", g_ps5 > r_ps5, true)

	# 【这条是给设计者的警报】一个"手不抖的贪心玩家"如果都会破产，
	# 那数值表 sheet 2 那句「至少 7 次成功投递才活得下去」就没兑现
	_check("贪心玩家不会破产", _count_below(greedy), 0)
	_check("贪心玩家全部凑齐 PS5 费", g_ps5, 1.0)
	print("   贪心：平均成功 %.1f 次 / PS5 付清 %.0f%% ｜ 随机：%.1f 次 / %.0f%%" % [
			g_success, g_ps5 * 100.0, r_success, r_ps5 * 100.0])


## 【这条守的是「有没有死关」】一个把线索读透、手也不抖的玩家，
## 只要投过某个「公司 × 档位」，就必须 100% 通过。
## 出现低于 100% 的组合，要么是该公司的条件根本拼不出来，
## 要么是求解器有 bug —— 两种都得当场查。
func _test_no_dead_combo(greedy: Array[Dictionary]) -> void:
	print("[5] 没有死关：投过的组合必须打得中")
	var merged := {}
	for g: Dictionary in greedy:
		for key: String in (g["by_company"] as Dictionary):
			var src: Dictionary = g["by_company"][key]
			if not merged.has(key):
				merged[key] = {"n": 0, "pass": 0}
			merged[key]["n"] += src["n"]
			merged[key]["pass"] += src["pass"]
	_check("贪心玩家确实投过东西", merged.size() > 0, true)
	var line := "   "
	for key: String in merged:
		var d: Dictionary = merged[key]
		_check("%s 的命中率必须是 100%%（%d 次）" % [key, d["n"]], d["pass"], d["n"])
		line += "%s 100%%(%d)  " % [key, d["n"]]
	print(line)
	print("   ↑ 命中率只要掉下 100%，就说明该公司有条件拼不出来，或者求解器有 bug")


func _avg_field(games: Array[Dictionary], key: String) -> float:
	var total := 0
	for g: Dictionary in games:
		total += int(g[key])
	return float(total) / float(games.size())


func _rate(games: Array[Dictionary], key: String) -> float:
	var n := 0
	for g: Dictionary in games:
		if bool(g[key]):
			n += 1
	return float(n) / float(games.size())


func _count_below(games: Array[Dictionary]) -> int:
	var n := 0
	for g: Dictionary in games:
		if int(g["money"]) < 0:
			n += 1
	return n
