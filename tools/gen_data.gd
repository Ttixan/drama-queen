extends SceneTree
## 生成 data/parts/*.tres 与 data/companies/*.tres
##
##   godot --headless --path <项目> --import        # 先让 Godot 认识占位图
##   godot --headless --path <项目> --script res://tools/gen_data.gd
##   godot --headless --path <项目> --import        # 再让 Godot 认识新 .tres
##
## 【为什么用脚本生成而不是手搓 .tres】37 个资源、每个十几个字段，手搓必然漂移。
## 这里生成的 .tres 是**产物**，定义源是：
##   - 部件  → `tools/part_catalog.gd`（纯代码定义）
##   - 公司  → **本文件**（数值 / 条件 / 门槛）+ `data/companies/{代号}_*.md`（招聘页文案）
##
## 【公司文案为什么也要走生成】`data/companies/*.md` 是 docx 的可读副本，也是内容源，
## 但 **md 进不了 Godot 的导出包** —— 打包后读不到，招聘页会整页空。
## 所以真值一律落进 `.tres`：md 只当可读副本，改完文案重跑本脚本。
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
		# 线索文案里写了 `**纯**` 这种强调。Label 不认 markdown，星号会原样显示出来，
		# 于是玩家看到的是「重点在**纯**」—— 去掉星号，字还是那几个字。
		co.hint = String(spec["hint"]).replace("**", "")
		co.hr_name = spec["hr_name"]
		co.hr_title = spec["hr_title"]

		# 招聘页那批字段来自 data/companies/{代号}_*.md（docx 的可读副本）
		var posting := _load_posting(spec["code"])
		co.tagline = posting.get("tagline", "")
		co.industry = posting.get("industry", "")
		co.funding = posting.get("funding", "")
		co.scale = posting.get("scale", "")
		co.position_title = posting.get("position_title", "")
		co.salary = posting.get("salary", "")
		co.experience = posting.get("experience", "")
		co.tags.assign(posting.get("tags", []))
		co.posting_text = posting.get("posting_text", "")
		co.posting_note = posting.get("posting_note", "")

		if _save(co, "%s/%s.tres" % [COMPANY_DIR, spec["code"]]):
			n += 1
	return n


# ============================================================
# 招聘页文案（data/companies/{代号}_*.md）
# ============================================================
## 从 md 里抠出招聘页字段。
##
## 【为什么必须按小节切，不能逐行 grep】职位详情正文里也有 `**薪资**：`、
## `**上班时间**：` 这类行。逐行 grep 会把正文里的字当成招聘页头部字段，
## 于是「薪资」一栏变成「底薪＋过稿提成」—— 看着还挺像对的，最麻烦的那种错。
## 所以状态机只认「## 公司信息 / ## 招聘页 / ### 职位详情」三个小节。
func _load_posting(code: String) -> Dictionary:
	var out := {}
	var path := _find_company_md(code)
	if path.is_empty():
		push_warning("找不到 %s 公司的招聘文案 md，招聘页会空着" % code)
		return out

	var info := {}
	var head := {}
	var detail: Array[String] = []
	var note := ""
	var state := ""

	for raw: String in FileAccess.get_file_as_string(path).split("\n"):
		var t := raw.strip_edges()
		if t.begins_with("### "):
			# 「## 招聘页」底下的**任何** ### 都是详情正文的小标题。
			# 【别写死成 `### 职位详情`】五家公司的分节各不相同：
			# A 用「职位详情」，C 拆成「岗位职责 / 任职要求 / 福利待遇」，
			# D 还多一个「关于我们」。只认一个标题名会把 C、D 的正文整段丢掉 ——
			# 而且不会报错，只是招聘页上正文凭空消失。
			if state == "posting":
				state = "detail"
				var heading := t.substr(4).strip_edges()
				# 「职位详情」是**容器标题**，不是正文的小标题 —— 页面自己已经有一行
				# 「职位详情」了，再收进正文就变成同一句话连出现两次。
				# 但「岗位职责 / 任职要求 / 关于我们」这些是真·分节标题，必须留着。
				if heading != "职位详情":
					detail.append(heading)
			else:
				state = ""
			continue
		if t.begins_with("## "):
			var name := t.substr(3).strip_edges()
			if name == "公司信息":
				state = "info"
			elif name == "招聘页":
				state = "posting"
			else:
				state = ""
			continue
		if t.begins_with("# "):
			var parts := t.substr(2).split("｜")
			if parts.size() >= 2:
				out["tagline"] = parts[1].strip_edges()
			continue
		if t.is_empty():
			continue

		match state:
			"info":
				var row := _table_row(t)
				if row.size() >= 2:
					info[row[0]] = row[1]
			"posting":
				var kv := _bold_kv(t)
				if kv.size() >= 2:
					head[kv[0]] = kv[1]
			"detail":
				if t.begins_with(">"):
					note = t.substr(1).strip_edges().trim_prefix("注：").strip_edges()
				else:
					# 正文里还有 `**薪资**：` 这类小标题。Label 不认 markdown，
					# 留着星号会原样显示成「**薪资**」—— 去掉星号，字还是那几个字。
					detail.append(t.replace("**", ""))

	out["industry"] = info.get("行业", "")
	out["funding"] = info.get("融资", "")
	out["scale"] = info.get("规模", "")
	out["position_title"] = head.get("职位", "")
	out["salary"] = head.get("薪资", "")
	out["experience"] = head.get("经验", "")
	out["tags"] = _split_tags(str(head.get("标签", "")))
	out["posting_text"] = "\n".join(detail)
	out["posting_note"] = note
	return out


func _find_company_md(code: String) -> String:
	var dir := DirAccess.open(COMPANY_DIR)
	if dir == null:
		return ""
	for f: String in dir.get_files():
		if f.begins_with(code + "_") and f.ends_with(".md"):
			return "%s/%s" % [COMPANY_DIR, f]
	return ""


## `| 行业 | 广播／影视 |` → ["行业", "广播／影视"]
func _table_row(line: String) -> Array:
	if not line.begins_with("|"):
		return []
	var out: Array = []
	for c: String in line.split("|"):
		var s := c.strip_edges()
		if not s.is_empty() and not s.begins_with("---"):
			out.append(s)
	if out.size() < 2:
		return []
	return [out[0], out[1]]


## `**职位**：短剧编剧` → ["职位", "短剧编剧"]
func _bold_kv(line: String) -> Array:
	if not line.begins_with("**"):
		return []
	var close := line.find("**", 2)
	if close < 0:
		return []
	var key := line.substr(2, close - 2).strip_edges()
	var value := line.substr(close + 2).strip_edges()
	while value.begins_with("：") or value.begins_with(":"):
		value = value.substr(1).strip_edges()
	return [key, value]


## 标签之间用全角空格分隔（`短剧　小说改编`），顺手兼容半角
func _split_tags(text: String) -> Array[String]:
	var out: Array[String] = []
	for t: String in text.replace("　", " ").split(" "):
		var s := t.strip_edges()
		if not s.is_empty():
			out.append(s)
	return out


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
