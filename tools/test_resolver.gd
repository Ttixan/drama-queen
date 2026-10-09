extends SceneTree
## 判定引擎验证 —— headless 运行，不依赖任何场景
##
##   godot --headless --path <项目目录> --script res://tools/test_resolver.gd
##
## 验证目标：L0~L4 五档难度是否真的分层 ——
## 一段表情包应该**只能**通过它对应那一档，而不是所有档都过或都不过。

const TOL := 0.01

var _failures: Array[String] = []


func _initialize() -> void:
	print("")
	print("=== 判定引擎验证 ===")
	print("")

	var companies := _build_companies()
	var clips := _build_clips()

	print("条件清单：")
	for co: CompanyData in companies:
		var parts: Array[String] = []
		for c: AuditionCondition in co.conditions:
			parts.append("%s%s(w%.0f)" % ["★" if c.required else "", c.describe(), c.weight])
		print("  %s  门槛%d  总权重%.0f  →  %s" % [
			co.code, co.acting_threshold, co.total_condition_weight(), " | ".join(parts)
		])
	print("")

	# clip 名称 → 各公司期望匹配度
	var expected := {
		"全程喜（平坦）":   {"A": 1.00, "B": 1.00, "C": 1.00, "D": 0.00, "E": 0.00},
		"喜→平→哀（滑落）": {"A": 1.00, "B": 1.00, "C": 0.67, "D": 1.00, "E": 0.00},
		"喜→喜→哀（突转）": {"A": 1.00, "B": 1.00, "C": 1.00, "D": 0.00, "E": 1.00},
		"喜+怒（杂情绪）":  {"A": 0.00, "B": 0.67, "C": 0.00, "D": 0.00, "E": 0.00},
		"全空白（未拼装）": {"A": 1.00, "B": 0.00, "C": 0.00, "D": 0.00, "E": 0.00},
	}

	print("匹配度矩阵（括号内为期望值）")
	print("%-20s %s" % ["表情包", "   A        B        C        D        E"])
	print("-".repeat(74))

	for clip_name: String in clips:
		var clip: Clip = clips[clip_name]
		var row := "%-18s" % clip_name
		for co: CompanyData in companies:
			var res := AuditionResolver.evaluate(clip, co.conditions)
			var got: float = res["match_rate"]
			var want: float = expected[clip_name][co.code]
			var mark := " " if absf(got - want) <= TOL else "!"
			if mark == "!":
				_failures.append("%s @ %s: 期望 %.2f，实际 %.2f" % [clip_name, co.code, want, got])
			row += " %.2f%s  " % [got, mark]
		print("%s   [%s]" % [row, "→".join(clip.all_labels())])
	print("")

	# ---- 分层是否成立 ----
	_check_layering(clips, companies)

	# ---- 演技门槛 ----
	_check_acting_gate(clips["喜→平→哀（滑落）"], companies)

	print("")
	if _failures.is_empty():
		print("✅ 全部通过")
		quit(0)
	else:
		print("❌ %d 项失败：" % _failures.size())
		for f: String in _failures:
			print("   - " + f)
		quit(1)


# ============================================================
func _build_companies() -> Array:
	var out: Array = []

	# L0 A 烂片厂 —— 最低条件：无冲突情绪（教学关，让玩家第一档就学到「情绪要一致」）
	var a := _company("A", 0)
	a.conditions = _conds([
		_cond(AuditionCondition.Type.NO_EMOTION, 1.0, Emotion.Kind.ANGER, 0.0, 0, true),
	])

	# L1 B 小公司 —— 单情绪命中
	var b := _company("B", 3)
	b.conditions = _conds([
		_cond(AuditionCondition.Type.HAS_EMOTION, 2.0, Emotion.Kind.JOY, 1.0, 0, true),
		_cond(AuditionCondition.Type.NO_EMOTION, 1.0, Emotion.Kind.ANGER, 0.0),
	])

	# L2 C 商业片 —— 情绪纯度（克制，不能有杂情绪）
	var c := _company("C", 8)
	c.conditions = _conds([
		_cond(AuditionCondition.Type.DOMINANT_EMOTION, 2.0, Emotion.Kind.JOY, 0.0, 0, true),
		_cond(AuditionCondition.Type.PURITY_MIN, 1.0, Emotion.Kind.JOY, 0.55),
	])

	# L3 D 文艺片 —— 情绪曲线形态（表演弧线：逐渐滑落 = 幻灭）
	var d := _company("D", 15)
	d.conditions = _conds([
		_cond(AuditionCondition.Type.VALENCE_TREND, 2.0, Emotion.Kind.JOY, 0.0,
				AuditionCondition.Trend.DECREASING, true),
		_cond(AuditionCondition.Type.LAST_FRAME_EMOTION, 1.0, Emotion.Kind.SORROW),
	])

	# L4 E 大厂 —— 帧间反转（转折，不是滑落）
	var e := _company("E", 25)
	e.conditions = _conds([
		_cond(AuditionCondition.Type.VALENCE_REVERSAL, 2.0, Emotion.Kind.JOY, 1.0, 0, true),
		_cond(AuditionCondition.Type.PURITY_MIN, 1.0, Emotion.Kind.JOY, 0.55),
		_cond(AuditionCondition.Type.NO_EMOTION, 1.0, Emotion.Kind.ANGER, 0.0),
	])

	out.append_array([a, b, c, d, e])
	return out


func _build_clips() -> Dictionary:
	# 杂情绪：眼=喜、嘴=怒、眉=怒 → 向量为 喜3 / 怒6，主导情绪是「怒」
	var chaos := Clip.new(3)
	for i in 3:
		chaos.frames[i] = Clip.Frame.new(
				_part(PartData.Slot.EYES, Emotion.Kind.JOY, 3.0),
				_part(PartData.Slot.MOUTH, Emotion.Kind.ANGER, 3.0),
				_part(PartData.Slot.BROWS, Emotion.Kind.ANGER, 3.0),
				null)

	return {
		"全程喜（平坦）": _clip([Emotion.Kind.JOY, Emotion.Kind.JOY, Emotion.Kind.JOY]),
		"喜→平→哀（滑落）": _clip([Emotion.Kind.JOY, -1, Emotion.Kind.SORROW]),
		"喜→喜→哀（突转）": _clip([Emotion.Kind.JOY, Emotion.Kind.JOY, Emotion.Kind.SORROW]),
		"喜+怒（杂情绪）": chaos,
		"全空白（未拼装）": _clip([-1, -1, -1]),
	}


## 每帧眼/嘴/眉同情绪。emotions 里传 -1 表示该帧用「空白部件」（全零向量）
func _clip(emotions: Array) -> Clip:
	var c := Clip.new(emotions.size())
	for i in emotions.size():
		var e: int = emotions[i]
		var amount := 0.0 if e == -1 else 3.0
		c.frames[i] = Clip.Frame.new(
				_part(PartData.Slot.EYES, e, amount),
				_part(PartData.Slot.MOUTH, e, amount),
				_part(PartData.Slot.BROWS, e, amount),
				null)
	return c


func _part(slot: int, emotion: int, amount: float) -> PartData:
	var p := PartData.new()
	p.slot = slot
	match emotion:
		Emotion.Kind.JOY: p.joy = amount
		Emotion.Kind.ANGER: p.anger = amount
		Emotion.Kind.SORROW: p.sorrow = amount
		Emotion.Kind.SHOCK: p.shock = amount
		Emotion.Kind.CHARM: p.charm = amount
		Emotion.Kind.AWKWARD: p.awkward = amount
	return p


func _company(code: String, threshold: int) -> CompanyData:
	var co := CompanyData.new()
	co.code = code
	co.acting_threshold = threshold
	return co


func _conds(list: Array) -> Array[AuditionCondition]:
	var out: Array[AuditionCondition] = []
	for c: AuditionCondition in list:
		out.append(c)
	return out


func _cond(type: int, weight: float, emotion: int, value: float = 0.0,
		trend: int = 0, required: bool = false) -> AuditionCondition:
	var c := AuditionCondition.new()
	c.type = type
	c.weight = weight
	c.emotion = emotion
	c.value = value
	c.trend = trend
	c.required = required
	return c


# ============================================================
## 核心命题：一段表情包只能命中它「对应的那一档」
func _check_layering(clips: Dictionary, companies: Array) -> void:
	print("分层校验（用龙套匹配线 30% 判定）")
	var line := 0.30
	var expect_pass := {
		"全程喜（平坦）":   ["A", "B", "C"],
		"喜→平→哀（滑落）": ["A", "B", "C", "D"],
		"喜→喜→哀（突转）": ["A", "B", "C", "E"],
		"喜+怒（杂情绪）":  ["B"],
		"全空白（未拼装）": ["A"],
	}
	print("%-20s %s" % ["表情包", "通过的公司"])
	print("-".repeat(74))
	for clip_name: String in clips:
		var passed: Array[String] = []
		for co: CompanyData in companies:
			var r := AuditionResolver.evaluate(clips[clip_name], co.conditions)
			if r["match_rate"] >= line:
				passed.append(co.code)
		var want: Array = expect_pass[clip_name]
		var ok := passed == want
		if not ok:
			_failures.append("分层 %s: 期望通过 %s，实际 %s" % [clip_name, want, passed])
		print("%-18s %s  %s" % [clip_name, passed, "OK" if ok else "✗ 期望 " + str(want)])
	print("")
	print("  ↑ 关键看点：滑落型只过 D 不过 E，突转型只过 E 不过 D —— L3/L4 确实互斥")
	print("")


## 演技门槛与匹配度是「且」的关系
func _check_acting_gate(clip: Clip, companies: Array) -> void:
	print("演技门槛校验（用 D 公司，它的条件对『滑落型』是满分）")
	var d: CompanyData = companies[3]
	var role := RoleRequirement.new()
	role.tier = RoleRequirement.Tier.LEAD
	role.acting_required = 15
	role.match_line = 0.70

	var low := AuditionResolver.resolve(clip, d, role, 10)
	var high := AuditionResolver.resolve(clip, d, role, 20)
	print("  演技10 → 通过=%s  原因=%s" % [low["passed"], low["fail_reasons"]])
	print("  演技20 → 通过=%s  模糊评价=%s" % [high["passed"], AuditionResolver.quality_label(high["match_rate"])])
	print("")

	if low["passed"]:
		_failures.append("演技门槛失效：演技 10 不该通过 D 公司主角（要求 15）")
	if not high["passed"]:
		_failures.append("演技 20 应通过 D 公司主角")
