extends SceneTree
## 表情包求解器验证 —— headless 运行，不加载任何场景与 autoload
##
##   godot --headless --path <项目目录> --script res://tools/test_clip_solver.gd
##
## 【为什么这条链值得单独立】它回答一个**只有搜过才知道**的问题：
## **「一个完全读懂了线索、手也不抖的玩家，能不能拼出过线的表演？」**
## 如果某家公司 × 某个档位连理想解都过不了线，那就是**死关** ——
## 玩家再努力也没用，而这件事在人工试玩时极难察觉（他只会以为是自己的问题）。
##
## 顺带钉住两件容易烂掉的事：
##   1. 求解器的**快速评分路径**不能和真实判定器分叉（否则模拟器的结论是错的）
##   2. 关键条件（required）**一条都不能失手** —— 失手时匹配度直接归零

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	print("")
	print("=== 表情包求解器验证 ===")
	print("")

	if PartLibrary.is_empty():
		print("❌ 部件库是空的 —— 先跑 tools/gen_data.gd")
		quit(1)
		return

	var t0 := Time.get_ticks_msec()
	_test_candidates()
	_test_pool()
	_report_matrix()
	print("")
	print("  搜索总耗时 %d ms（五家公司的理想解，含建池子）" % (Time.get_ticks_msec() - t0))
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


const CODES: Array[String] = ["A", "B", "C", "D", "E"]
const TIERS: Array[int] = [
	RoleRequirement.Tier.EXTRA,
	RoleRequirement.Tier.SUPPORTING,
	RoleRequirement.Tier.LEAD,
]


# ============================================================
func _test_candidates() -> void:
	print("[1] 候选池：必填的三槽能拼出多少种单帧（肤色不进判定，不算在内）")
	var eyes := PartLibrary.by_slot(PartData.Slot.EYES).size()
	var mouth := PartLibrary.by_slot(PartData.Slot.MOUTH).size()
	var brows := PartLibrary.by_slot(PartData.Slot.BROWS).size()
	# 「其他」的选项数要把「留空」这一种算进去
	var extra := PartLibrary.slot_options(PartData.Slot.EXTRA).size()
	_check("眼件数", eyes, 12)
	_check("嘴件数", mouth, 14)
	_check("眉件数", brows, 12)
	_check("其他选项数（含留空）", extra, 7)
	_check("单帧候选总数", ClipSolver.candidate_count(), eyes * mouth * brows * extra)
	_check("三帧全枚举的量级是天文数字", eyes * mouth * brows * extra > 4000, true)
	print("   %d 眼 × %d 嘴 × %d 眉 × %d 其他 = %d 种单帧；三帧全枚举 = %.1f 亿，必须缩小" % [
			eyes, mouth, brows, extra, ClipSolver.candidate_count(),
			pow(eyes * mouth * brows * extra, 3) / 100000000.0])


func _test_pool() -> void:
	print("[2] 通用池：与公司无关，五家共用")
	var n := ClipSolver.pool_size()
	_check("池子非空", n > 0, true)
	_check("池子不超过上限", n <= ClipSolver.MAX_POOL, true)
	# 【为什么直接测时间而不是测池子大小】池子大一点本身没错，**慢**才是问题。
	# 模拟器要跑几千局，每家公司的理想解只在第一次解时算，但那一秒也得忍得了。
	# 这条断言是「别把取材准则加到搜索跑不动」的护栏。
	ClipSolver.clear_cache()
	var t := Time.get_ticks_msec()
	ClipSolver.rate(CompanyLibrary.by_code("E").conditions)
	var cost := Time.get_ticks_msec() - t
	_check("单家公司的首次求解在 3 秒内（实测 %d ms）" % cost, cost < 3000, true)
	ClipSolver.clear_cache()

	# 缓存：同一组条件第二次应当直接命中
	ClipSolver.clear_cache()
	_check("清缓存后是空的", ClipSolver.cache_size(), 0)
	var conditions := CompanyLibrary.by_code("D").conditions
	ClipSolver.rate(conditions)
	_check("解过一次之后缓存里有一条", ClipSolver.cache_size(), 1)
	ClipSolver.rate(conditions)
	_check("同条件再解不会新增缓存", ClipSolver.cache_size(), 1)
	print("   池子 %d 帧 → %d 个有序三元组（含重复帧）" % [n, n * n * n])


## 五家 × 三档的「理想解 vs 匹配线」矩阵 —— **这张表就是这条链的产出**
func _report_matrix() -> void:
	print("[3] 理想玩家（读懂线索、手不抖）能不能过线")
	_check("公司数", CompanyLibrary.count(), 5)
	var all_passable := true
	for code: String in CODES:
		var co := CompanyLibrary.by_code(code)
		var cond := co.conditions
		var clip := ClipSolver.solve(cond)
		var solved_rate := ClipSolver.rate(cond)

		# ---- 防分叉：求解器的快速评分必须和真实判定器一致 ----
		var real := AuditionResolver.evaluate(clip, cond)
		_check("%s：求解器报的匹配度 == 真实判定器对这段剪辑的判定" % code,
				solved_rate, real["match_rate"])
		# ---- 关键条件一条都不能失手 ----
		_check("%s：理想解没有触发一票否决" % code, real["vetoed"], false)
		_check("%s：理想解必须完整（眼/嘴/眉齐全）" % code, clip.is_complete(), true)
		_check("%s：理想解是 3 帧" % code, clip.frame_count(), 3)

		var line := "   %s %-10s 理想 %3.0f%% ｜" % [
				code, co.display_name if not co.display_name.is_empty() else co.code,
				solved_rate * 100.0]
		for tier: int in TIERS:
			var role := co.role_of(tier)
			# 过线还要过演技门槛 —— 但这里只问**表演层**能不能过
			var ok: bool = solved_rate >= role.match_line
			if not ok:
				all_passable = false
			line += "  %s %s %.0f%%" % [
					RoleRequirement.TIER_NAMES[tier],
					"✅" if ok else "❌", role.match_line * 100.0]
			_check("%s 公司 %s 档：理想解必须过线（否则是死关）" % [code, RoleRequirement.TIER_NAMES[tier]],
					ok, true)
		print(line)
		print("      理想表演：%s" % clip.summarize())
	_check("★ 15 个「公司 × 档位」组合全部可过 —— 没有死关", all_passable, true)
