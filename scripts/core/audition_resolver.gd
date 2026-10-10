class_name AuditionResolver
extends RefCounted
## 试镜判定引擎
##
## 【纯逻辑】本类不继承 Node、不碰场景树 —— 这是数值模拟器能 headless 跑的前提。
## 场景脚本只负责读结果、画出来。
##
## 判定分两步，两者是「且」的关系：
##   1. 演技门槛：max(公司演技门槛, 角色演技要求)
##   2. 匹配度：Σ(命中条件权重) / Σ(全部条件权重) >= 角色匹配线
##
## 【隐藏公式】玩家看不到匹配度数字，只看到帧级情绪标签 + 通过/失败 + 模糊评价。
## 学习通道是公司招聘页上的口味线索（CompanyData.hint），在 Boss直聘 里看。


## 判定一次投递
## acting: 玩家当前演技值（显式传入，避免依赖 GameState，方便模拟器构造）
## 返回 Dictionary：passed / match_rate / match_line / acting_ok / details / fail_reasons
static func resolve(clip: Clip, company: CompanyData, role: RoleRequirement, acting: int) -> Dictionary:
	var result := {
		"passed": false,
		"match_rate": 0.0,
		"match_line": role.match_line if role != null else 0.0,
		"hit_weight": 0.0,
		"total_weight": 0.0,
		"acting_required": 0,
		"acting_ok": false,
		"details": [],
		"fail_reasons": [],
		"clip_summary": clip.summarize() if clip != null else "",
	}

	if clip == null or company == null or role == null:
		result["fail_reasons"].append("参数不完整")
		return result

	# ---- 1. 演技门槛 ----
	var required: int = maxi(company.acting_threshold, role.acting_required)
	result["acting_required"] = required
	result["acting_ok"] = acting >= required
	if not result["acting_ok"]:
		result["fail_reasons"].append("演技值 %d < 要求 %d" % [acting, required])

	# ---- 2. 匹配度 ----
	var eval_result := evaluate(clip, company.conditions)
	result["match_rate"] = eval_result["match_rate"]
	result["hit_weight"] = eval_result["hit_weight"]
	result["total_weight"] = eval_result["total_weight"]
	result["details"] = eval_result["details"]

	if eval_result["vetoed"]:
		result["fail_reasons"].append("关键条件未满足：%s" % eval_result["veto_reason"])

	if result["match_rate"] < role.match_line:
		result["fail_reasons"].append(
			"匹配度 %.0f%% < 要求 %.0f%%" % [result["match_rate"] * 100.0, role.match_line * 100.0]
		)

	result["passed"] = result["acting_ok"] and result["match_rate"] >= role.match_line
	return result


## 纯匹配度计算：Σ(命中权重) / Σ(全部权重)
## 但只要有**关键条件(required)**失手，匹配度直接归零 —— 见 AuditionCondition.required
## 边界：无条件清单时返回 1.0（A 烂片厂这类无门槛公司直接通过）
static func evaluate(clip: Clip, conditions: Array) -> Dictionary:
	var total := 0.0
	var hit := 0.0
	var details: Array[Dictionary] = []
	var vetoed := false
	var veto_reason := ""

	for c: AuditionCondition in conditions:
		total += c.weight
		var ok := check(clip, c)
		if ok:
			hit += c.weight
		elif c.required and not vetoed:
			vetoed = true
			veto_reason = c.describe()
		details.append({
			"condition": c,
			"description": c.describe(),
			"passed": ok,
			"weight": c.weight,
			"required": c.required,
		})

	var rate := 1.0
	if vetoed:
		rate = 0.0
	elif total > 0.0:
		rate = hit / total

	return {
		"match_rate": rate,
		"hit_weight": hit,
		"total_weight": total,
		"vetoed": vetoed,
		"veto_reason": veto_reason,
		"details": details,
	}


## 单条件判定
static func check(clip: Clip, c: AuditionCondition) -> bool:
	if clip == null or c == null:
		return false
	var n := clip.frame_count()

	match c.type:
		AuditionCondition.Type.MIN_FRAMES:
			return n >= int(c.value)

		AuditionCondition.Type.HAS_EMOTION:
			for i in n:
				if clip.frame_vector(i)[c.emotion] >= c.value:
					return true
			return false

		AuditionCondition.Type.NO_EMOTION:
			for i in n:
				if clip.frame_vector(i)[c.emotion] > c.value:
					return false
			return true

		AuditionCondition.Type.DOMINANT_EMOTION:
			# 空向量必须判否 —— dominant() 在全零上默认返回 JOY，
			# 不特判的话「整段空白」会冒充成「主导情绪为喜」而通过。
			var mean := clip.mean_vector()
			if Emotion.is_empty(mean):
				return false
			return Emotion.dominant(mean) == c.emotion

		AuditionCondition.Type.PURITY_MIN:
			# 看**整体**纯度（平均向量），不看单帧 ——
			# 单帧判定会被中间的空白帧（全零 → 纯度 0）误伤，「情绪纯度」的本意是整体纯粹。
			return Emotion.purity(clip.mean_vector()) >= c.value

		AuditionCondition.Type.LAST_FRAME_EMOTION:
			if n == 0:
				return false
			var last := clip.last_vector()
			if Emotion.is_empty(last):
				return false
			return Emotion.dominant(last) == c.emotion

		AuditionCondition.Type.VALENCE_TREND:
			return _check_trend(clip.valence_track(), c.trend, c.value)

		AuditionCondition.Type.VALENCE_REVERSAL:
			return _check_reversal(clip.valence_track(), c.value)

	return false


## 效价曲线趋势。严格单调 —— 不接受「持平」。
## value 仅 STABLE 用，表示允许的波动幅度。
static func _check_trend(track: PackedFloat32Array, trend: int, tolerance: float) -> bool:
	var n := track.size()
	if n < 2:
		return false

	match trend:
		AuditionCondition.Trend.DECREASING:
			for i in range(1, n):
				if track[i] >= track[i - 1]:
					return false
			return true

		AuditionCondition.Trend.INCREASING:
			for i in range(1, n):
				if track[i] <= track[i - 1]:
					return false
			return true

		AuditionCondition.Trend.STABLE:
			var lo := track[0]
			var hi := track[0]
			for x: float in track:
				lo = minf(lo, x)
				hi = maxf(hi, x)
			return (hi - lo) <= tolerance

	return false


## 帧间反转：首末帧效价符号翻转，且两端都要有足够强度
## （否则「全零 → 微弱正值」也算反转，太廉价）
##
## 【关键】还要排除**单调滑落** —— 否则 `喜→平→哀` 这种平滑递减会同时满足
## D 的「曲线递减」和 E 的「帧间反转」，L3 与 L4 两档难度就分不开了。
## 分界：
##     `喜→平→哀`（单调滑落，渐进）= **D 幻灭**
##     `喜→喜→哀`（中途掉头，突转）= **E 反转**
static func _check_reversal(track: PackedFloat32Array, min_abs: float) -> bool:
	if track.size() < 2:
		return false
	var first := track[0]
	var last := track[track.size() - 1]
	if absf(first) <= min_abs or absf(last) <= min_abs:
		return false
	if signf(first) == signf(last):
		return false
	return not _is_monotonic(track)


static func _is_monotonic(track: PackedFloat32Array) -> bool:
	var n := track.size()
	if n < 2:
		return true
	var up := true
	var down := true
	for i in range(1, n):
		if track[i] <= track[i - 1]:
			up = false
		if track[i] >= track[i - 1]:
			down = false
	return up or down


## 给玩家的模糊评价（隐藏公式下不暴露百分比）
static func quality_label(match_rate: float) -> String:
	if match_rate >= 0.85:
		return "很契合"
	elif match_rate >= 0.55:
		return "还行"
	return "不对味"
