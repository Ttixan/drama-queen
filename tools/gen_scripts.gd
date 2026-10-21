extends SceneTree
## 把 `data/scripts/剧本*.md` 解析成 `data/scripts/<角色代号>.tres`（九份）
##
##   godot --headless --path <项目> --script res://tools/gen_scripts.gd
##   godot --headless --path <项目> --import      # 让 Godot 认识新 .tres
##
## 【为什么必须转，不能运行时读 md】和邮件 / 招聘页同一个坑：
## `.md` 不在导出资源白名单里，打包成 exe 之后 `res://data/scripts/*.md` **不存在**——
## 那时候才发现 HR 发的剧本全是空的已经来不及。转成 `.tres` 才能进包。
##
## 【改文案的正确姿势】改 `data/scripts/剧本N_*.md` → 重跑本脚本。
## 直接改 `.tres` 会被覆盖。
##
## 【解析的前提】md 结构固定为：
##   # 剧本N、标题
##   ## 视角N：角色名
##   | 字段 | 内容 |   ← 角色代号 / 角色名 / 场景数
##   ### 场景 N · 场景头
##   > 正文…
## 结构不对时**报错退出**，而不是悄悄生成一份空剧本。
##
## ⚠️ 三份剧本的**来源 docx 还在改**（见 `docs/进度.md` 的内容待办）——
## 改完重跑本脚本即可，代码侧不用动。

const SCRIPT_DIR := "res://data/scripts"
const PREFIX := "剧本"

## 视角顺序 → 档位。**md 里没有这一列，这是 10-16 拍的口径**：
## 场景数是 1 / 2~3 / 4~5 地递增的，正好和「龙套 / 配角 / 主角」的戏份同构 ——
##   剧本1：嘉豪 1 场 / 女主 3 场 / 男主 5 场
##   剧本2：桂香 1 场 / 贵妃 3 场 / 贵人 4 场
##   剧本3：白月光 1 场 / 男友 2 场 / 女主 4 场
## 九份里的每一份（三个剧本 × 三个档）都要有，否则「抽一份配角剧本」会抽空。
const TIER_BY_VIEW: Array[int] = [
	RoleRequirement.Tier.EXTRA,       ## 视角1
	RoleRequirement.Tier.SUPPORTING,  ## 视角2
	RoleRequirement.Tier.LEAD,        ## 视角3
]

## 每场戏的拼贴需求 —— 源：`关键词表 (1).docx` 的「三个剧本 - 表情拼贴轮需求数值汇总」。
## 外层下标 = 场景号 - 1；内层是这场要**同时**演的几个复合情绪：
## `{"name": 复合名, "parts": {基础情绪: 分}}`，parts 值的和 = 这条需求的满分。
## 【「或」取主方案】男主场景 1 写着「信任50+期待50 或 痴呆100」—— 取前者，
## 玩家在录像机里只能同时看到一套明确的数字，别让他猜。
const DEMANDS := {
	"play1_v1": [
		[{"name": "支配", "parts": {"愤怒": 25, "信任": 25}},
		{"name": "傲慢", "parts": {"厌恶": 25, "愤怒": 25}}],
	],
	"play1_v2": [
		[{"name": "信任", "parts": {"信任": 50}}, {"name": "期待", "parts": {"期待": 50}}],
		[{"name": "信任", "parts": {"信任": 50}}, {"name": "喜悦", "parts": {"喜悦": 30}},
		{"name": "恐惧", "parts": {"恐惧": 20}}],
		[{"name": "害羞", "parts": {"喜悦": 25, "恐惧": 25}},
		{"name": "喜欢", "parts": {"喜悦": 25, "信任": 25}}],
	],
	"play1_v3": [
		[{"name": "信任", "parts": {"信任": 50}}, {"name": "期待", "parts": {"期待": 50}}],
		[{"name": "信任", "parts": {"信任": 40}}, {"name": "期待", "parts": {"期待": 30}},
		{"name": "痴呆", "parts": {"惊讶": 15, "厌恶": 15}}],
		[{"name": "恐惧", "parts": {"恐惧": 50}}, {"name": "暴怒", "parts": {"惊讶": 15, "愤怒": 15}},
		{"name": "绝望", "parts": {"恐惧": 10, "悲伤": 10}}],
		[{"name": "喜欢", "parts": {"喜悦": 20, "信任": 20}}, {"name": "期待", "parts": {"期待": 30}},
		{"name": "害羞", "parts": {"喜悦": 15, "恐惧": 15}}],
		[{"name": "破绷", "parts": {"喜悦": 50, "惊讶": 35, "期待": 15}}],
	],
	"play2_v1": [
		[{"name": "信任", "parts": {"信任": 50}}, {"name": "喜悦", "parts": {"喜悦": 50}}],
	],
	"play2_v2": [
		[{"name": "震怒", "parts": {"惊讶": 40, "愤怒": 40}},
		{"name": "轻蔑", "parts": {"厌恶": 10, "愤怒": 10}}],
		[{"name": "恐惧", "parts": {"恐惧": 50}}, {"name": "惊讶", "parts": {"惊讶": 50}}],
		[{"name": "轻蔑", "parts": {"厌恶": 40, "愤怒": 40}}, {"name": "喜悦", "parts": {"喜悦": 20}}],
	],
	"play2_v3": [
		[{"name": "魅惑", "parts": {"厌恶": 50, "喜悦": 50}}],
		[{"name": "好奇", "parts": {"信任": 30, "惊讶": 30}},
		{"name": "支配", "parts": {"愤怒": 20, "信任": 20}}],
		[{"name": "自信", "parts": {"信任": 35, "期待": 35}},
		{"name": "轻蔑", "parts": {"厌恶": 15, "愤怒": 15}}],
		[{"name": "释然", "parts": {"喜悦": 50, "信任": 50}}],
	],
	"play3_v1": [
		[{"name": "顺从", "parts": {"信任": 40, "恐惧": 40}},
		{"name": "支配", "parts": {"愤怒": 10, "信任": 10}}],
	],
	"play3_v2": [
		[{"name": "轻蔑", "parts": {"厌恶": 50, "愤怒": 50}}],
		[{"name": "绝望", "parts": {"恐惧": 50, "悲伤": 50}}],
	],
	"play3_v3": [
		[{"name": "宿命论", "parts": {"信任": 50, "期待": 50}}],
		[{"name": "乐观", "parts": {"喜悦": 50, "期待": 50}}],
		[{"name": "悲愤交加", "parts": {"悲伤": 40, "愤怒": 40}},
		{"name": "失望", "parts": {"惊讶": 10, "悲伤": 10}}],
		[{"name": "释然", "parts": {"喜悦": 50, "信任": 50}}],
	],
}

var _errors: Array[String] = []


func _initialize() -> void:
	print("")
	print("=== 生成剧本 .tres ===")
	print("")

	var sources := _sources()
	if sources.is_empty():
		_errors.append("%s 里没有 `%s*.md`" % [SCRIPT_DIR, PREFIX])

	var docs: Array[ScriptDoc] = []
	for path: String in sources:
		docs.append_array(_parse_file(path))

	# 每档都得有货：抽签是在「这一档的那几份」里抽的，空了就是 HR 发不出剧本
	for tier: int in TIER_BY_VIEW:
		var n := 0
		for d: ScriptDoc in docs:
			if d.tier == tier:
				n += 1
		if n != sources.size():
			_errors.append("档位「%s」只有 %d 份，应该有 %d 份（每份剧本一个视角）" % [
				String(RoleRequirement.TIER_NAMES[tier]), n, sources.size()])

	var written := 0
	for doc: ScriptDoc in docs:
		if String(doc.id).is_empty():
			continue
		if _save(doc, "%s/%s.tres" % [SCRIPT_DIR, doc.id]):
			written += 1
			print("   %s → %s（%s · %d 场 · %d 字）" % [
				doc.id, doc.file_name(), doc.tier_name(), doc.scene_count, doc.body.length()])

	print("")
	print("生成 %d 份剧本 → %s" % [written, SCRIPT_DIR])
	print("下一步：godot --headless --path <项目> --import")
	print("")

	if _errors.is_empty():
		print("✅ 完成")
		quit(0)
	else:
		print("❌ %d 项失败：" % _errors.size())
		for e: String in _errors:
			print("   - " + e)
		quit(1)


# ============================================================
# 解析
# ============================================================
## `res://data/scripts/剧本*.md`，按文件名排序（剧本1 / 2 / 3）
func _sources() -> Array[String]:
	var out: Array[String] = []
	var names := DirAccess.get_files_at(SCRIPT_DIR)
	names.sort()
	for n: String in names:
		if n.ends_with(".md") and n.begins_with(PREFIX):
			out.append("%s/%s" % [SCRIPT_DIR, n])
	return out


func _parse_file(path: String) -> Array[ScriptDoc]:
	var raw := FileAccess.get_file_as_string(path)
	if raw.is_empty():
		_errors.append("%s 读出来是空的" % path)
		return []

	var lines := raw.split("\n")
	var title := ""
	var play_index := 0
	for line: String in lines:
		var t := line.strip_edges()
		# 一级标题 `# 剧本1、青春嘉豪`（不能认成 `## 视角…`）
		if t.begins_with("# ") and not t.begins_with("## "):
			title = t.substr(2).strip_edges()
			break
	if title.is_empty():
		_errors.append("%s 里没找到一级标题「# 剧本N、标题」" % path)
		return []
	var parts := title.split("、")
	play_index = _int_of(parts[0]) if parts.size() > 0 else 0
	title = parts[parts.size() - 1].strip_edges()
	if play_index <= 0:
		_errors.append("%s 的标题「%s」里读不出剧本序号" % [path, title])
		return []

	var views := _views_of(lines)
	if views.is_empty():
		_errors.append("%s 里没找到「## 视角N：角色名」小节" % path)
		return []
	if views.size() != TIER_BY_VIEW.size():
		_errors.append("%s 有 %d 个视角，档位只有 %d 个 —— 对应不上" % [
			path, views.size(), TIER_BY_VIEW.size()])

	var out: Array[ScriptDoc] = []
	for i in views.size():
		var view: Dictionary = views[i]
		var body_lines: Array = view["lines"]
		var doc := ScriptDoc.new()
		doc.play_index = play_index
		doc.play_title = title
		doc.role_name = String(view["name"])
		doc.tier = TIER_BY_VIEW[i] if i < TIER_BY_VIEW.size() else RoleRequirement.Tier.EXTRA
		doc.id = StringName(_meta(body_lines, "角色代号"))
		doc.scene_count = _int_of(_meta(body_lines, "场景数"))
		if String(doc.id).is_empty():
			_errors.append("%s 的视角「%s」里没有「角色代号」那一行" % [path, doc.role_name])
			continue
		doc.body = _body_of(body_lines)
		if doc.body.strip_edges().is_empty():
			_errors.append("%s 的视角「%s」正文是空的" % [path, doc.role_name])
			continue
		# 每场需求：数量必须和「场景数」对齐 —— 错位的话录像机第 3 帧会读到空需求
		var demands: Array = DEMANDS.get(String(doc.id), [])
		if demands.size() != doc.scene_count:
			_errors.append("%s（%s）的需求数 %d ≠ 场景数 %d" % [
				doc.id, doc.role_name, demands.size(), doc.scene_count])
		doc.scene_demands = demands
		out.append(doc)
	return out


## 切成 [{name, lines}]。一个 `## 视角N：角色名` 到下一个 `## ` 之间算一节
func _views_of(lines: Array) -> Array:
	var out: Array = []
	var current := {}
	for line: String in lines:
		var t := line.strip_edges()
		if t.begins_with("## ") and t.contains("视角"):
			if not current.is_empty():
				out.append(current)
			var head := t.substr(3)
			var bits := head.split("：")
			current = {"name": bits[bits.size() - 1].strip_edges(), "lines": []}
			continue
		if current.is_empty():
			continue
		(current["lines"] as Array).append(line)
	if not current.is_empty():
		out.append(current)
	return out


## `| 角色代号 | \`play1_v1\` |` → `play1_v1`（找不到返回空串）
func _meta(lines: Array, key: String) -> String:
	for line: String in lines:
		var cells := _table_cells(line)
		if cells.size() >= 2 and cells[0] == key:
			return cells[1].replace("`", "").strip_edges()
	return ""


## 把这一节的正文拼出来：**原文照搬，只剥 markdown 的壳**
##   `> 正文`        → `正文`     （引用符号；Label 不认 markdown）
##   `| 键 | 值 |`   → `键：值`   （表格线；分隔行直接丢掉）
##   `### 场景 1 · …`→ `场景 1 · …`（标题的井号）
func _body_of(lines: Array) -> String:
	var out: Array[String] = []
	for line: String in lines:
		var t := line.rstrip(" \t\r")
		var s := t.strip_edges()
		if s.begins_with("|"):
			var cells := _table_cells(t)
			# 表头（`| 字段 | 内容 |`）不是内容，丢掉；分隔行由 _table_cells 返回空
			if cells.size() >= 2 and not (cells[0] == "字段" and cells[1] == "内容"):
				# 【代号是内部 id】分镜、调试、需求表都靠它对位，但玩家读的剧本里
				# 出现「角色代号：play2_v1」「场景代号：play2_v1_s1」只会莫名其妙 —— 不进正文
				if cells[0] != "场景代号" and cells[0] != "角色代号":
					out.append("%s：%s" % [cells[0], cells[1]])
			continue
		if s.begins_with(">"):
			out.append(_strip_codes(s.substr(1).strip_edges()))
			continue
		if s.begins_with("#"):
			out.append(s.lstrip("#").strip_edges())
			continue
		out.append(t)
	# 掐掉首尾空行；中间最多留一个空行（md 里常连着两三行空的）
	var cleaned: Array[String] = []
	for line: String in out:
		if line.strip_edges().is_empty() and (cleaned.is_empty() or cleaned[-1].is_empty()):
			continue
		cleaned.append(line)
	while not cleaned.is_empty() and cleaned[-1].strip_edges().is_empty():
		cleaned.remove_at(cleaned.size() - 1)
	return "\n".join(cleaned)


## 把正文里的内部代号洗掉：`【拼贴表情轮 → 条件见 `play1_v1_s1`】` → `【拼贴表情轮】`
##
## 【为什么要在生成这一层做】玩家不该看见 `play1_v1_s1` 这种东西；但策划写分镜时
## 又必须标出来（需求数值表靠它对位），所以留在 md 里、进正文前摘掉。
## 反引号里的一律当"内部引用"，去掉之后如果尾巴变成半句话（`条件见 】`），一起收拾干净。
func _strip_codes(text: String) -> String:
	var re := RegEx.new()
	re.compile("`[A-Za-z0-9_]+`")
	var s := re.sub(text, "", true)
	# 去掉代号后残下的半截提示语
	for junk: String in ["条件见 】", "条件见】", " → 】", "→】", "条件见 "]:
		s = s.replace(junk, "】" if junk.contains("】") else "")
	s = s.replace("  ", " ").strip_edges()
	# 「【X → 】」这种中间只剩箭头的，把箭头也去掉
	s = s.replace(" → 】", "】").replace("→】", "】")
	return s


## `| a | b |` → ["a", "b"]；分隔行（全是 - / :）返回空数组
func _table_cells(line: String) -> Array[String]:
	var out: Array[String] = []
	var t := line.strip_edges()
	if not t.begins_with("|"):
		return out
	var body := t.substr(1)
	if body.ends_with("|"):
		body = body.substr(0, body.length() - 1)
	var is_sep := true
	for cell: String in body.split("|"):
		var v := cell.strip_edges()
		out.append(v)
		if not v.is_empty() and not _is_sep_cell(v):
			is_sep = false
	if is_sep:
		return [] as Array[String]
	return out


func _is_sep_cell(v: String) -> bool:
	for i in v.length():
		var c := v[i]
		if c != "-" and c != ":":
			return false
	return true


func _int_of(text: String) -> int:
	var digits := ""
	for i in text.length():
		var c := text[i]
		if c >= "0" and c <= "9":
			digits += c
	return int(digits) if not digits.is_empty() else 0


func _save(res: Resource, path: String) -> bool:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		_errors.append("保存 %s 失败：%s" % [path, error_string(err)])
		return false
	return true
