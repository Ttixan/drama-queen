extends SceneTree
## 数据层验证 —— headless 跑，直接吃磁盘上生成的 data/parts 与 data/companies
##
##   godot --headless --path <项目> --script res://tools/test_data.gd
##
## 【和 test_resolver.gd 的分工】
##   test_resolver 用的是**手搓的合成表情包**（每帧纯色向量），证明判定逻辑对。
##   本测试用的是**从 32 件部件里真拼出来的表情包**，证明数据能玩 ——
##   即「玩家真的能拼过 D 的递减和 E 的反转」，而不是数学上恰好像对。
##
## 这两件事必须分开验：逻辑对但数据不可达，是最容易漏掉的一种死法。

const TOL := 0.01

const PART_DIR := "res://data/parts"
const COMPANY_DIR := "res://data/companies"

var _failures: Array[String] = []
var _checks := 0
var _parts: Dictionary = {}      ## "eyes_04" -> PartData


func _initialize() -> void:
	print("")
	print("=== 数据层验证（真实部件 + 真实公司）===")
	print("")

	_load_parts()
	var companies := _load_companies()

	print("[1] 部件池")
	_check("部件总数", _parts.size(), 32)
	_check_slot_count("眼", PartData.Slot.EYES, 8)
	_check_slot_count("嘴", PartData.Slot.MOUTH, 10)
	_check_slot_count("眉", PartData.Slot.BROWS, 8)
	_check_slot_count("其他", PartData.Slot.EXTRA, 6)
	_check_gradient()

	print("")
	print("[2] 公司")
	for co: CompanyData in companies:
		var req := 0
		for c: AuditionCondition in co.conditions:
			if c.required:
				req += 1
		print("   %s 门槛%-3d 片酬%-4d 条件%d条(w%.0f) 一票否决%d条  %s" % [
			co.code, co.acting_threshold, co.extra_payout,
			co.conditions.size(), co.total_condition_weight(), req, co.hint.left(24) + "…"
		])
		_check("%s 有且只有 1 个一票否决" % co.code, req, 1)
		_check("%s 有三个角色档" % co.code, co.roles.size(), 3)
	_check("公司数", companies.size(), 5)

	print("")
	print("[3] 片酬矩阵（钱由公司档次决定）")
	var want_payout := {"A": [40, 80, 120], "B": [64, 128, 192], "C": [80, 160, 240],
			"D": [96, 192, 288], "E": [120, 240, 360]}
	for co: CompanyData in companies:
		var got: Array[int] = []
		for r: RoleRequirement in co.roles:
			got.append(co.payout_for(r))
		_check("%s 片酬 龙套/配角/主角" % co.code, str(got), str(want_payout[co.code]))
		print("   %s  龙套%-4d 配角%-4d 主角%-4d" % [co.code, got[0], got[1], got[2]])

	print("")
	print("[4] 真实表情包 × 五家公司（用真部件拼，不是合成向量）")
	_check_real_clips(companies)

	print("")
	print("[5] 演技门槛")
	_check_acting_gate(companies)

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


# ============================================================
func _load_parts() -> void:
	var d := DirAccess.open(PART_DIR)
	for f: String in d.get_files():
		if not f.ends_with(".tres"):
			continue
		var p: PartData = load("%s/%s" % [PART_DIR, f])
		_parts[String(p.id)] = p


func _load_companies() -> Array:
	var out: Array = []
	for code in ["A", "B", "C", "D", "E"]:
		out.append(load("%s/%s.tres" % [COMPANY_DIR, code]))
	return out


func _p(id: String) -> PartData:
	if not _parts.has(id):
		_failures.append("找不到部件 " + id)
		return null
	return _parts[id]


## 拼一帧。extra 传空串表示留空（组合数 ×7 的那个 7）
func _frame(eye: String, mouth: String, brow: String, extra: String = "") -> Clip.Frame:
	return Clip.Frame.new(
			_p(eye), _p(mouth), _p(brow), _p(extra) if extra != "" else null)


func _clip(frames: Array) -> Clip:
	var c := Clip.new(frames.size())
	for i in frames.size():
		c.frames[i] = frames[i]
	return c


# ============================================================
func _check(label: String, got: Variant, want: Variant) -> void:
	_checks += 1
	if got != want:
		_failures.append("%s: 期望 %s，实际 %s" % [label, want, got])


func _check_slot_count(name: String, slot: int, want: int) -> void:
	var n := 0
	for id: String in _parts:
		if _parts[id].slot == slot:
			n += 1
	_check("%s 数量" % name, n, want)


## 梯度硬约束：每个槽位必须同时有「正效价 / 中性 / 负效价」三种部件。
## 缺任何一档，玩家就拼不出递减曲线和帧间反转，D 和 E 两家直接变成死关。
func _check_gradient() -> void:
	for slot in [PartData.Slot.EYES, PartData.Slot.MOUTH, PartData.Slot.BROWS]:
		var pos := 0
		var neu := 0
		var neg := 0
		for id: String in _parts:
			var p: PartData = _parts[id]
			if p.slot != slot:
				continue
			var v := Emotion.valence(p.emotion_vector())
			if v > 0.0:
				pos += 1
			elif v < 0.0:
				neg += 1
			else:
				neu += 1
		var name: String = PartData.SLOT_NAMES[slot]
		_check("%s 有正效价件" % name, pos > 0, true)
		_check("%s 有负效价件" % name, neg > 0, true)
		_check("%s 有中性件" % name, neu > 0, true)
		print("   %s  正%d / 中%d / 负%d  —— 梯度完整" % [name, pos, neu, neg])


func _check_real_clips(companies: Array) -> void:
	# 三帧的取法：喜帧最亮、平帧全空、哀帧最暗
	var joy_frame := _frame("eyes_04", "mouth_03", "brows_02")     # 眯笑+大笑+高扬 → +9
	var flat_frame := _frame("eyes_00", "mouth_00", "brows_00")    # 平静+闭合+舒展 → 0
	var sad_frame := _frame("eyes_03", "mouth_08", "brows_05")     # 含泪+嚎啕+八字 → −8

	var clips := {
		"全程喜（甜妹）": _clip([joy_frame, joy_frame, joy_frame]),
		"喜→平→哀（幻灭）": _clip([joy_frame, flat_frame, sad_frame]),
		"喜→喜→哀（反转）": _clip([joy_frame, joy_frame, sad_frame]),
		"怒压喜（翻车）": _clip([
			_frame("eyes_00", "mouth_03", "brows_04", "extra_01"),    # 平静+大笑+倒竖+青筋
			_frame("eyes_00", "mouth_03", "brows_04", "extra_01"),
			_frame("eyes_00", "mouth_03", "brows_04", "extra_01")]),
		"全空白（没拼）": _clip([flat_frame, flat_frame, flat_frame]),
	}

	# 期望匹配度 —— 必须和 test_resolver.gd 的合成矩阵一致
	var expect := {
		"全程喜（甜妹）":   {"A": 1.00, "B": 1.00, "C": 1.00, "D": 0.00, "E": 0.00},
		"喜→平→哀（幻灭）": {"A": 1.00, "B": 1.00, "C": 0.67, "D": 1.00, "E": 0.00},
		"喜→喜→哀（反转）": {"A": 1.00, "B": 1.00, "C": 1.00, "D": 0.00, "E": 1.00},
		"怒压喜（翻车）":   {"A": 0.00, "B": 0.67, "C": 0.00, "D": 0.00, "E": 0.00},
		"全空白（没拼）":   {"A": 1.00, "B": 0.00, "C": 0.00, "D": 0.00, "E": 0.00},
	}

	print("   %-18s %s" % ["表情包", "   A        B        C        D        E"])
	print("   " + "-".repeat(70))
	for name: String in clips:
		var clip: Clip = clips[name]
		var row := "   %-16s" % name
		for co: CompanyData in companies:
			var got: float = AuditionResolver.evaluate(clip, co.conditions)["match_rate"]
			var want: float = expect[name][co.code]
			var ok: bool = absf(got - want) <= TOL
			if not ok:
				_failures.append("真实表情包 %s @ %s: 期望 %.2f，实际 %.2f" % [name, co.code, want, got])
			row += " %.2f%s  " % [got, " " if ok else "!"]
		print("%s  [%s]" % [row, clip.summarize()])

	print("")
	print("   ↑ 真部件拼出来的结果与合成向量矩阵**完全一致** —— 数据层和判定层对得上")


func _check_acting_gate(companies: Array) -> void:
	var a: CompanyData = companies[0]
	var d: CompanyData = companies[3]

	# A 龙套：门槛 0，演技 0 就能投
	var r_extra := a.role_of(RoleRequirement.Tier.EXTRA)
	_check("A 龙套 演技要求", r_extra.acting_required, 0)
	_check("A 龙套 匹配线", r_extra.match_line, 0.30)

	# D 主角：公司门槛 15 与角色要求 15 取「且」
	var r_lead := d.role_of(RoleRequirement.Tier.LEAD)
	_check("D 主角 演技要求", r_lead.acting_required, 15)
	var clip := _clip([
		_frame("eyes_04", "mouth_03", "brows_02"),
		_frame("eyes_00", "mouth_00", "brows_00"),
		_frame("eyes_03", "mouth_08", "brows_05")])
	var low := AuditionResolver.resolve(clip, d, r_lead, 10)
	var high := AuditionResolver.resolve(clip, d, r_lead, 20)
	_check("D 主角 演技10 被门槛挡住", low["passed"], false)
	_check("D 主角 演技20 且曲线对 → 通过", high["passed"], true)
	print("   演技10 → %s（%s）" % [low["passed"], low["fail_reasons"][0]])
	print("   演技20 → %s（%s）" % [high["passed"], AuditionResolver.quality_label(high["match_rate"])])
