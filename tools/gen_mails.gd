extends SceneTree
## 把 `data/mails/{A..E}.md` 解析成 `data/mails/{A..E}.tres`，并生成定角池
##
##   godot --headless --path <项目> --import
##   godot --headless --path <项目> --script res://tools/gen_mails.gd
##   godot --headless --path <项目> --import      # 再让 Godot 认识新 .tres
##
## 【为什么要转，不能运行时直接读 .md】
## `.md` 不在 Godot 的导出资源白名单里 —— 打包成 exe 之后 `res://data/mails/A.md`
## 会**不存在**，那时候才发现邮件全空已经来不及了。转成 `.tres` 才能进包，
## 也才能让狗牙在检查器里直接改文案。
##
## 【改文案的正确姿势】改 `data/mails/*.md` → 重跑本脚本。
## 直接改 `.tres` 会被覆盖。
##
## 【解析的前提】md 结构固定为：
##   ## 试镜成功 / ## 试镜失败
##   **主题**：xxx
##   ---
##   正文（可多段）
##   **署名**
## 结构不对时本脚本会**报错退出**，而不是悄悄生成一封空邮件。

const MAIL_DIR := "res://data/mails"
const POOL_PATH := "res://data/casting_pool.tres"
const CODES: Array[String] = ["A", "B", "C", "D", "E"]

const SECTION_SUCCESS := "试镜成功"
const SECTION_FAIL := "试镜失败"

## 定角池的**占位内容** —— 真值是狗牙的活，这里只保证管道能跑通。
## 他改 `data/casting_pool.tres`（检查器里直接编辑）即可，不必重跑本脚本。
const PLACEHOLDER_POOL := {
	"player_name": "林小满",
	"play_titles": [
		"赘婿归来", "神医下山", "战神无双", "重生之豪门千金", "真假千金", "总裁的替身新娘",
		"我的霸道前妻", "八零年代小娇妻", "逆袭从离婚开始", "退婚后我成了首富",
		"闪婚老公是首富", "九零年代暴富记",
	],
	"places": [
		"横店影视城", "象山影视基地", "城郊老厂房摄影棚", "影视城 3 号棚", "郊区实景基地", "南郊民国街",
	],
	"role_names_extra": ["保安", "前台", "服务员", "路人甲", "快递小哥", "群演"],
	"role_names_support": ["王管家", "林秘书", "张医生", "李助理", "赵老板", "陈经理"],
	"role_names_lead": ["沈砚清", "陆慕白", "顾向南", "江晚吟", "苏离", "傅司晏"],
}

var _errors: Array[String] = []


func _initialize() -> void:
	print("")
	print("=== 生成邮件模板 + 定角池 ===")
	print("")

	var n := 0
	for code: String in CODES:
		var path := "%s/%s.md" % [MAIL_DIR, code]
		if not FileAccess.file_exists(path):
			_errors.append("缺少源文件 " + path)
			continue
		var t := _parse(path, code)
		if t == null:
			continue
		var err := ResourceSaver.save(t, "%s/%s.tres" % [MAIL_DIR, code])
		if err != OK:
			_errors.append("保存 %s.tres 失败：%s" % [code, error_string(err)])
			continue
		n += 1
		print("   %s 成功《%s》/ 失败《%s》" % [
			code, t.success.subject, t.fail.subject])

	var pool := _build_pool()
	var perr := ResourceSaver.save(pool, POOL_PATH)
	if perr != OK:
		_errors.append("保存定角池失败：%s" % error_string(perr))

	print("")
	print("生成 %d 封模板 → %s" % [n, MAIL_DIR])
	print("定角池 → %s" % POOL_PATH)
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
func _parse(path: String, code: String) -> MailTemplate:
	var raw := FileAccess.get_file_as_string(path)
	if raw.is_empty():
		_errors.append("%s 读出来是空的" % path)
		return null

	var sections := _split_sections(raw, code)
	if sections.is_empty():
		_errors.append("%s 里没找到「## %s」小节" % [path, SECTION_SUCCESS])
		return null
	for key in [SECTION_SUCCESS, SECTION_FAIL]:
		if not sections.has(key):
			_errors.append("%s 缺少小节「## %s」" % [path, key])

	var t := MailTemplate.new()
	t.company_code = code
	t.success = _letter_of(sections.get(SECTION_SUCCESS, {}), code, SECTION_SUCCESS)
	t.fail = _letter_of(sections.get(SECTION_FAIL, {}), code, SECTION_FAIL)
	if t.success == null or t.fail == null:
		return null
	return t


## 切出 {小节名 -> [行]}。用「## 」作为分隔，`---` 留在小节内部交给 _letter_of 处理。
func _split_sections(raw: String, code: String) -> Dictionary:
	var sections := {}
	var current := ""
	for line: String in raw.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("## "):
			current = t.substr(3).strip_edges()
			sections[current] = []
			continue
		if current.is_empty():
			continue
		(sections[current] as Array).append(line.rstrip(" \t\r"))
	return sections


func _letter_of(lines: Variant, code: String, section: String) -> MailLetter:
	var body_lines: Array = lines
	var subject := ""
	var body_start := -1

	for i in body_lines.size():
		var t := String(body_lines[i]).strip_edges()
		if t.begins_with("**主题**"):
			subject = t.replace("**主题**", "").strip_edges().lstrip("：:")
		elif t == "---":
			body_start = i + 1
			break

	# 《》 里带《》 的主题才是有效主题 —— B 公司的失败信主题是「试镜结果」，
	# 不带剧名，所以这里只校验非空，不校验格式。
	if subject.is_empty():
		_errors.append("%s 的「%s」小节里没有 `**主题**：` 行" % [code, section])
		return null
	if body_start < 0:
		_errors.append("%s 的「%s」小节里没有 `---` 分隔线" % [code, section])
		return null

	var body: Array[String] = []
	for i in range(body_start, body_lines.size()):
		body.append(String(body_lines[i]))
	# 掐掉首尾空行
	while not body.is_empty() and body[0].strip_edges().is_empty():
		body.remove_at(0)
	while not body.is_empty() and body[body.size() - 1].strip_edges().is_empty():
		body.remove_at(body.size() - 1)
	if body.is_empty():
		_errors.append("%s 的「%s」小节正文是空的" % [code, section])
		return null

	# 末行是署名（粗体），从正文里摘出去
	var signature := body[body.size() - 1].strip_edges().trim_prefix("**").trim_suffix("**")
	body.remove_at(body.size() - 1)
	while not body.is_empty() and body[body.size() - 1].strip_edges().is_empty():
		body.remove_at(body.size() - 1)

	var letter := MailLetter.new()
	letter.subject = subject
	letter.body = "\n".join(body)
	letter.signature = signature
	return letter


func _build_pool() -> CastingPool:
	var pool := CastingPool.new()
	pool.player_name = PLACEHOLDER_POOL["player_name"]
	pool.play_titles.assign(PLACEHOLDER_POOL["play_titles"])
	pool.places.assign(PLACEHOLDER_POOL["places"])
	pool.role_names_extra.assign(PLACEHOLDER_POOL["role_names_extra"])
	pool.role_names_support.assign(PLACEHOLDER_POOL["role_names_support"])
	pool.role_names_lead.assign(PLACEHOLDER_POOL["role_names_lead"])
	return pool
