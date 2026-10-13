extends SceneTree
## 数值模拟器 —— 让几种「玩家」把 21 天各跑几千遍
##
##   godot --headless --path <项目> --script res://tools/simulate.gd
##   godot --headless --path <项目> --script res://tools/simulate.gd -- 500
##
## 【它为什么能这么跑】`scripts/core/` 下除了 `EventBus` / `Game` 全是纯 `RefCounted` ——
## 这是 M0 就定下的架构约束，一路守到了现在。本脚本**不加载任何场景树**，
## 直接 `GameState.new()` + `DailyActions` + `WeekCycle.settle()` 就能跑完一局。
## 哪天有人往 core 里塞了个 Node，这个脚本会第一个跑不起来。
##
## 【它回答三个只有跑得出来才有答案的问题】
##   1. **21 点行动点被用在哪里、还剩不剩给随机事件**
##      （待拍板 13 的遗留风险：投递 12 + 上课 3 + 打工 6 刚好占满，零冗余）
##   2. **「影后」那条线紧不紧** —— 数值表 3 推演说三周都压在演技上刚好到 28
##   3. **六个结局的分布** —— 尤其「平庸」是不是变成了绝大多数人的归宿
##
## 【它不能回答什么】它测不出**好不好玩**。随机事件还剩 0 点是个事实，
## 该不该由此把打工上限降到 1 次/周，仍然要人拍板。

const CODES: Array[String] = ["A", "B", "C", "D", "E"]
const DEFAULT_GAMES := 300

## 要跑的配置。sloppiness = 每帧被挑错一个部件的概率。
static var CONFIGS: Array[Dictionary] = [
	{"name": "随机（什么都不学）", "kind": "random", "sloppiness": 0.0},
	{"name": "贪心 · 手不抖", "kind": "greedy", "sloppiness": 0.0},
	{"name": "贪心 · 每帧 25% 挑错", "kind": "greedy", "sloppiness": 0.25},
	{"name": "贪心 · 每帧 50% 挑错", "kind": "greedy", "sloppiness": 0.5},
	{"name": "贪心 · 每帧 75% 挑错", "kind": "greedy", "sloppiness": 0.75},
]

var _games := DEFAULT_GAMES


func _initialize() -> void:
	print("")
	print("=== 数值模拟器 ===")
	print("")

	if PartLibrary.is_empty() or CompanyLibrary.count() == 0:
		print("❌ 数据没就位 —— 先跑 tools/gen_data.gd")
		quit(1)
		return

	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_int():
		_games = maxi(1, args[0].to_int())
	print("每种配置 %d 局，每局 21 天" % _games)
	print("")

	# 预热：把五家公司的理想解先解出来，免得把搜索耗时算进第一局的统计
	var t0 := Time.get_ticks_msec()
	for code: String in CODES:
		ClipSolver.rate(CompanyLibrary.by_code(code).conditions)
	print("五家公司的理想解已解出（%d ms），池子 %d 帧" % [
			Time.get_ticks_msec() - t0, ClipSolver.pool_size()])

	var results: Array[Dictionary] = []
	for cfg: Dictionary in CONFIGS:
		var t := Time.get_ticks_msec()
		var agg := _run_config(cfg)
		print("  %-24s %d 局跑了 %d ms" % [cfg["name"], _games, Time.get_ticks_msec() - t])
		results.append(agg)

	_report_endings(results)
	_report_survival(results)
	_report_companies(results)
	_report_headroom(results)
	_report_acting_ceiling(results)
	_report_threshold_sweep()

	quit(0)


# ============================================================
# 跑
# ============================================================
func _run_config(cfg: Dictionary, count: int = -1) -> Dictionary:
	var n := count if count > 0 else _games
	var agg := {
		"name": cfg["name"],
		"games": n,
		"max_acting_at_submit": 0,
		"endings": {},
		"bankrupt": 0,
		"ps5_off": 0,
		"ap": {SimAgent.Action.SUBMIT: 0, SimAgent.Action.WORK: 0,
				SimAgent.Action.CLASS: 0, SimAgent.Action.IDLE: 0},
		"by_company": {},
		"sum": {"money": 0, "acting": 0, "fame": 0, "rep": 0, "successes": 0},
	}
	for i in n:
		var agent := _make_agent(cfg, 1000 + i)
		var one := SimRunner.run_one(agent)
		agg["max_acting_at_submit"] = maxi(int(agg["max_acting_at_submit"]),
				int(one["max_acting_at_submit"]))
		var ending := String(one["ending"])
		agg["endings"][ending] = int(agg["endings"].get(ending, 0)) + 1
		if int(one["money"]) < 0:
			agg["bankrupt"] += 1
		if bool(one["ps5_off"]):
			agg["ps5_off"] += 1
		for k: int in (one["ap"] as Dictionary):
			agg["ap"][k] += one["ap"][k]
		for key: String in (one["by_company"] as Dictionary):
			var src: Dictionary = one["by_company"][key]
			if not (agg["by_company"] as Dictionary).has(key):
				agg["by_company"][key] = {"n": 0, "pass": 0}
			agg["by_company"][key]["n"] += src["n"]
			agg["by_company"][key]["pass"] += src["pass"]
		agg["sum"]["money"] += int(one["money"])
		agg["sum"]["acting"] += int(one["acting"])
		agg["sum"]["fame"] += int(one["fame"])
		agg["sum"]["rep"] += int(one["rep"])
		agg["sum"]["successes"] += int(one["successes"])
	return agg


func _make_agent(cfg: Dictionary, seed_value: int) -> SimAgent:
	if cfg["kind"] == "random":
		return SimAgent.RandomPlayer.new(seed_value, 0.0)
	return SimAgent.GreedyPlayer.new(seed_value, cfg["sloppiness"])


## 【跑一局在哪】`tools/sim/runner.gd` 的 `SimRunner.run_one()` ——
## 模拟器与它的测试共用那一份，免得测试跑的是"另一套跑法"。


# ============================================================
# 报告
# ============================================================
func _report_endings(results: Array[Dictionary]) -> void:
	print("")
	print("[1] 结局分布")
	var ids: Array[String] = []
	for e: Dictionary in EndingResolver.all():
		ids.append(String(e["id"]))
	var head := "%-26s" % "配置"
	for id: String in ids:
		head += "%10s" % String(EndingResolver.by_id(StringName(id))["name"])
	print(head)
	for r: Dictionary in results:
		var line := "%-26s" % r["name"]
		for id: String in ids:
			line += "%9.1f%%" % (100.0 * float(r["endings"].get(id, 0)) / float(r["games"]))
		print(line)
	print("  （共 %d 个结局；「文案待补」的三个判定已生效，只是结语还是占位）" % ids.size())


func _report_survival(results: Array[Dictionary]) -> void:
	print("")
	print("[2] 生存与行动点（21 点都花在哪）")
	print("%-26s%9s%11s%11s   %s" % ["配置", "破产", "PS5付清", "平均成功", "投递/打工/上课/闲置"])
	for r: Dictionary in results:
		var g := float(r["games"])
		var ap: Dictionary = r["ap"]
		var line := "%-26s%8.1f%%%10.1f%%%11.1f   " % [
				r["name"],
				100.0 * float(r["bankrupt"]) / g,
				100.0 * float(r["ps5_off"]) / g,
				float(r["sum"]["successes"]) / g]
		var parts: Array[String] = []
		for k: int in [SimAgent.Action.SUBMIT, SimAgent.Action.WORK,
				SimAgent.Action.CLASS, SimAgent.Action.IDLE]:
			parts.append("%5.1f" % (float(ap[k]) / g))
		print(line + " / ".join(parts))


func _report_companies(results: Array[Dictionary]) -> void:
	print("")
	print("[3] 各公司 × 档位的投递成功率")
	# 用「贪心 · 手不抖」那一档 —— 它代表一个把线索读透了的玩家
	var ref: Dictionary = results[1]
	var keys: Array[String] = []
	for k: String in (ref["by_company"] as Dictionary):
		keys.append(k)
	keys.sort()
	var line := "  "
	for k: String in keys:
		var d: Dictionary = ref["by_company"][k]
		if int(d["n"]) == 0:
			continue
		line += "%s %.0f%%(%d)  " % [k, 100.0 * float(d["pass"]) / float(d["n"]), d["n"]]
	print(line)
	print("  ↑ 括号里是投递次数。命中率低于 100% 说明「手不抖」这一档也有失手 —— 检查 sloppiness。")


func _report_headroom(results: Array[Dictionary]) -> void:
	print("")
	print("[4] 随机事件还剩不剩行动点")
	var g := float(results[1]["games"])
	var idle: float = float((results[1]["ap"] as Dictionary)[SimAgent.Action.IDLE]) / g
	var per_week := idle / float(GameState.WEEKS)
	print("  贪心玩家平均每局闲置 %.1f 点（每周 %.2f 点）" % [idle, per_week])
	if per_week < 0.5:
		print("  → **几乎不剩**：他把行动点压满了。随机事件想挤进来，只能从别处让 ——")
		print("     降打工上限 / 降每周投递上限，或者干脆让事件不占行动点（见待拍板 13）")
	else:
		print("  → 还有余量，随机事件抢得到点")


## 【这是模拟器最值钱的产出之一】它把「数值表 3 的推演」与「决策 1.5 的时序」
## 之间那条矛盾，从一句隐约的担心变成了一组数。
func _report_acting_ceiling(results: Array[Dictionary]) -> void:
	var threshold: int = CompanyLibrary.by_code("E").acting_threshold
	print("")
	print("[5] 演技的门槛卡在哪 —— E 大厂（门槛 %d）摸得到吗" % threshold)
	var ceiling := 0
	for r: Dictionary in results:
		ceiling = maxi(ceiling, int(r["max_acting_at_submit"]))
	print("  所有配置里，玩家在**投递那一刻**见过的最高演技：%d" % ceiling)
	print("")
	print("  机制原因：演技的增量在**周末结算**时才兑现（决策 1.5），所以每一周**之内**")
	print("  演技是冻结的 —— 本周投的戏，要到周末才把它换来的演技发下来。")
	print("  于是「进入第 3 周时手上最多有多少」就是天花板：")
	print("    第 1 周：表演课 +3，龙套 ×4（+1）→ 7")
	print("    第 2 周：表演课 +3，配角 ×4（+2）→ 18")
	print("    第 3 周：表演课 +3 → **21**，然后这一周就结束了")
	if ceiling < threshold:
		print("")
		print("  ❌ %d < %d —— E 公司在任何时刻都投不进去，**「影后」不可达**。" % [ceiling, threshold])
		print("     数值表 3 那句「第 3 周练到 25 之后，当周还剩 1 次投递额度正好投 E 主角」，")
		print("     默认了演技**当周生效** —— 与决策 1.5 的「周末统一结算」冲突。")
	else:
		print("  ✅ 摸得到 %d —— E 公司可投，「影后」在表演层没问题" % threshold)


## 把 E 的门槛往下扫，看「影后」在哪一个数上第一次出现。
##
## 【为什么要扫而不是直接改】门槛该定多少是**策划决定**，不是程序能单方面定的。
## 模拟器的职责是把「改成 N 会发生什么」摊开，让拍板的人看着数定。
## 【为什么改得动】`CompanyLibrary.by_code()` 返回的是缓存里的那一个实例，
## 直接改它的 `acting_threshold` 就影响全局 —— 扫完必须还原。
func _report_threshold_sweep() -> void:
	print("")
	print("[6] E 公司门槛敏感性 —— 「影后」卡在哪一个数上")
	var e := CompanyLibrary.by_code("E")
	var current: int = e.acting_threshold
	var n := maxi(50, _games / 3)
	# 扫的档位里永远包含「当前值」，用 ← 标出来 —— 否则这张表看不出在看什么
	var values: Array[int] = [25, 23, 21, 20, 18]
	if not values.has(current):
		values.append(current)
	values.sort()
	values.reverse()
	print("  每档 %d 局（贪心 · 手不抖）｜ ← 是当前值" % n)
	print("  %-8s%10s%14s%12s" % ["E 门槛", "影后", "文艺片女神", "平均成功"])
	for t: int in values:
		e.acting_threshold = t
		var agg := _run_config({"name": "门槛 %d" % t, "kind": "greedy", "sloppiness": 0.0}, n)
		var endings: Dictionary = agg["endings"]
		print("  %-6d%s%9.1f%%%13.1f%%%12.1f" % [t, "←" if t == current else " ",
				100.0 * float(endings.get("actress", 0)) / float(n),
				100.0 * float(endings.get("arthouse_goddess", 0)) / float(n),
				float((agg["sum"] as Dictionary)["successes"]) / float(n)])
	e.acting_threshold = current
	print("  ↑ 门槛越过「第 3 周内能给到的演技（21）」时，「影后」直接归零")
