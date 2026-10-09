extends SceneTree
## 生成 data/parts/*.tres 与 data/companies/*.tres
##
##   godot --headless --path <项目> --import        # 先让 Godot 认识占位图
##   godot --headless --path <项目> --script res://tools/gen_data.gd
##   godot --headless --path <项目> --import        # 再让 Godot 认识新 .tres
##
## 【为什么用脚本生成而不是手搓 .tres】37 个资源、每个十几个字段，手搓必然漂移。
## 这里生成的 .tres 是**产物**，定义源是 tools/part_catalog.gd 和本文件。
##
## 【公司条件直接取自 tools/test_resolver.gd 里验证过的那套】
## 不是数值表 sheet 4 的早期草案 —— 那份有两个坑（A 公司零条件、E-3 与 E-1 重复），
## 已在数值表校对时同步修正。

const Catalog := preload("res://tools/part_catalog.gd")

const PART_DIR := "res://data/parts"
const COMPANY_DIR := "res://data/companies"
const ART_DIR := "res://assets/parts"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PART_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(COMPANY_DIR))

	var n_parts := _gen_parts()
	var n_co := _gen_companies()

	print("")
	print("生成 %d 个部件 .tres → %s" % [n_parts, PART_DIR])
	print("生成 %d 个公司 .tres → %s" % [n_co, COMPANY_DIR])
	print("下一步：godot --headless --path <项目> --import")
	quit(0)


# ============================================================
# 部件
# ============================================================
func _gen_parts() -> int:
	var n := 0
	for p: Dictionary in Catalog.PARTS:
		var slot: int = p["slot"]
		var tier: int = p["tier"]
		var id := Catalog.part_id(slot, tier)

		var d := PartData.new()
		d.id = StringName(id)
		d.display_name = p["name"]
		d.slot = slot
		d.tier = tier

		var emo: Dictionary = p["emo"]
		d.joy = emo.get("joy", 0.0)
		d.anger = emo.get("anger", 0.0)
		d.sorrow = emo.get("sorrow", 0.0)
		d.shock = emo.get("shock", 0.0)
		d.charm = emo.get("charm", 0.0)
		d.awkward = emo.get("awkward", 0.0)

		var art := "%s/%s.png" % [ART_DIR, id]
		if ResourceLoader.exists(art):
			d.texture = load(art)
		else:
			push_warning("缺图，texture 留空：%s" % art)

		if _save(d, "%s/%s.tres" % [PART_DIR, id]):
			n += 1
	return n


# ============================================================
# 公司
# ============================================================
func _gen_companies() -> int:
	var n := 0
	for spec: Dictionary in _company_specs():
		var co := CompanyData.new()
		co.id = StringName(spec["code"])
		co.code = spec["code"]
		co.display_name = spec["display_name"]
		co.tier = spec["tier"]
		co.acting_threshold = spec["threshold"]
		co.ap_cost = 1
		co.weekly_limit = GameState.MAX_SUBMIT_PER_WEEK
		co.extra_payout = spec["extra_payout"]
		co.conditions = spec["conditions"]
		co.roles = _roles()
		co.hint = spec["hint"]
		co.hr_name = spec["hr_name"]
		co.hr_title = spec["hr_title"]

		if _save(co, "%s/%s.tres" % [COMPANY_DIR, spec["code"]]):
			n += 1
	return n


func _roles() -> Array[RoleRequirement]:
	# 演技收益由角色难度决定，钱由公司档次决定 —— 见决策记录 1.3
	var out: Array[RoleRequirement] = []
	out.append(_role(RoleRequirement.Tier.EXTRA, 0, 0.30, 1, 1.0))
	out.append(_role(RoleRequirement.Tier.SUPPORTING, 5, 0.50, 2, 2.0))
	out.append(_role(RoleRequirement.Tier.LEAD, 15, 0.70, 5, 3.0))
	return out


func _role(tier: int, need: int, line: float, gain: int, ratio: float) -> RoleRequirement:
	var r := RoleRequirement.new()
	r.tier = tier
	r.acting_required = need
	r.match_line = line
	r.acting_gain = gain
	r.payout_ratio = ratio
	return r


func _company_specs() -> Array[Dictionary]:
	return [
		{
			"code": "A", "display_name": "A 公司", "tier": CompanyData.Tier.A_LOW,
			"threshold": 0, "extra_payout": 40,
			"conditions": _conds([
				# L0 教学关：只要求「情绪别打架」。玩家在 A 学到的第一课是「一致」。
				_cond(AuditionCondition.Type.NO_EMOTION, Emotion.Kind.ANGER, 0.0, 1.0, 0, true),
			]),
			"hint": "A 厂什么都收。别全程一张臭脸就行 —— 他们自己也知道片子烂，不挑。",
			"hr_name": "王先生", "hr_title": "招聘负责人",
		},
		{
			"code": "B", "display_name": "B 公司", "tier": CompanyData.Tier.B_SMALL,
			"threshold": 3, "extra_payout": 64,
			"conditions": _conds([
				# L1 单情绪命中：教「情绪是能被识别的」
				_cond(AuditionCondition.Type.HAS_EMOTION, Emotion.Kind.JOY, 1.0, 2.0, 0, true),
				_cond(AuditionCondition.Type.NO_EMOTION, Emotion.Kind.ANGER, 0.0, 1.0),
			]),
			"hint": "B 公司要个讨喜的新人。笑一个就行 —— 但别笑里带火气。",
			"hr_name": "李女士", "hr_title": "人事兼行政",
		},
		{
			"code": "C", "display_name": "C 公司", "tier": CompanyData.Tier.C_COMMERCIAL,
			"threshold": 8, "extra_payout": 80,
			"conditions": _conds([
				# L2 情绪纯度：教「克制」。注意是纯，不是多。
				_cond(AuditionCondition.Type.DOMINANT_EMOTION, Emotion.Kind.JOY, 0.0, 2.0, 0, true),
				_cond(AuditionCondition.Type.PURITY_MIN, Emotion.Kind.JOY, 0.55, 1.0),
			]),
			"hint": "C 公司嘴上说「纯真」。重点在**纯** —— 掺一点别的情绪就不算数了。",
			"hr_name": "陈女士", "hr_title": "人事",
		},
		{
			"code": "D", "display_name": "D 公司", "tier": CompanyData.Tier.D_ARTHOUSE,
			"threshold": 15, "extra_payout": 96,
			"conditions": _conds([
				# L3 曲线形态：教「表演弧线」。要的是滑落，不是掉头。
				_cond(AuditionCondition.Type.VALENCE_TREND, Emotion.Kind.JOY, 0.0, 2.0,
						AuditionCondition.Trend.DECREASING, true),
				_cond(AuditionCondition.Type.LAST_FRAME_EMOTION, Emotion.Kind.SORROW, 0.0, 1.0),
			]),
			"hint": "D 公司要「幻灭」。第一帧还亮着，最后一帧得暗下去 —— 一路滑下来，不是中间掉头。",
			"hr_name": "徐女士", "hr_title": "制片人",
		},
		{
			"code": "E", "display_name": "E 公司", "tier": CompanyData.Tier.E_MAJOR,
			"threshold": 25, "extra_payout": 120,
			"conditions": _conds([
				# L4 帧间反转：教「转折」。中间必须掉头，慢慢滑下来的不算。
				_cond(AuditionCondition.Type.VALENCE_REVERSAL, Emotion.Kind.JOY, 1.0, 2.0, 0, true),
				_cond(AuditionCondition.Type.PURITY_MIN, Emotion.Kind.JOY, 0.55, 1.0),
				_cond(AuditionCondition.Type.NO_EMOTION, Emotion.Kind.ANGER, 0.0, 1.0),
			]),
			"hint": "E 厂要「反转」。中间那下得**掉头** —— D 家那种慢慢滑下来的，他们看不上。",
			"hr_name": "赵女士", "hr_title": "高级人才招聘专家",
		},
	]


# ============================================================
func _cond(type: int, emotion: int, value: float, weight: float,
		trend: int = 0, required: bool = false) -> AuditionCondition:
	var c := AuditionCondition.new()
	c.type = type
	c.emotion = emotion
	c.value = value
	c.weight = weight
	c.trend = trend
	c.required = required
	return c


func _conds(list: Array) -> Array[AuditionCondition]:
	var out: Array[AuditionCondition] = []
	for c: AuditionCondition in list:
		out.append(c)
	return out


func _save(res: Resource, path: String) -> bool:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("保存失败 %s (err %d)" % [path, err])
		return false
	return true
