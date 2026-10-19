extends SceneTree
## 把 `data/intro/intro.md` 解析成 `data/intro/intro.tres`
##
##   godot --headless --path <项目> --import
##   godot --headless --path <项目> --script res://tools/gen_intro.gd
##   godot --headless --path <项目> --import     # 再让 Godot 认识新 .tres
##
## 【为什么要转，不能运行时直接读 .md】与 `gen_mails.gd` 同一个原因：
## `.md` 不在 Godot 的导出白名单里，打包之后会**不存在**。转成 `.tres` 才能进包，
## 也才能让狗牙在检查器里通读开场文案。
##
## 【改文案的正确姿势】改 `data/intro/intro.md` → 重跑本脚本。直接改 `.tres` 会被覆盖。
##
## 【解析的前提】md 里必须是三个小节 `## A1 / ## A2 / ## A3`：
##   A1：每行 `键|值`（报头 / 版次 / 主标题 / 产品 / 副标题 / 正文 / 倒计时 / 落款）
##   A2 / A3：一行一句，空行忽略
## 任何一行认不出来就**报错退出**，而不是悄悄生成一份空开场 ——
## 「开场少了一句」在游戏里只是一次安静的黑屏，在测试里才炸得出来。

const MD_PATH := "res://data/intro/intro.md"
const OUT_PATH := "res://data/intro/intro.tres"
const INTRO_SCRIPT := preload("res://scripts/data/intro_data.gd")

const SECTIONS: Array[String] = ["A1", "A2", "A3"]

## A1 认识的字段。值可以带竖线，所以解析时只切第一个。
const A1_FIELDS: Array[String] = [
	"报头", "版次", "主标题", "产品", "副标题", "正文", "倒计时", "落款",
]

var _errors: Array[String] = []


func _initialize() -> void:
	print("")
	print("=== 生成开场导入 ===")
	print("")

	if not FileAccess.file_exists(MD_PATH):
		_errors.append("缺少源文件 " + MD_PATH)
		_finish(null)
		return

	var raw := FileAccess.get_file_as_string(MD_PATH)
	if raw.strip_edges().is_empty():
		_errors.append(MD_PATH + " 读出来是空的")
		_finish(null)
		return

	var sections := _split_sections(raw)
	for key: String in SECTIONS:
		if not sections.has(key):
			_errors.append("缺少小节「## %s」" % key)

	var data = INTRO_SCRIPT.new()
	_parse_a1(sections.get("A1", []), data)
	data.lines_a2.assign(_lines_of(sections.get("A2", [])))
	data.lines_a3.assign(_lines_of(sections.get("A3", [])))

	var errs: Array = data.validate()
	for e: String in errs:
		_errors.append(e)

	_finish(data)


func _finish(data: Variant) -> void:
	if _errors.is_empty() and data != null:
		var err := ResourceSaver.save(data, OUT_PATH)
		if err != OK:
			_errors.append("保存失败：%s（%s）" % [error_string(err), OUT_PATH])

	if not _errors.is_empty():
		print("❌ %d 项失败：" % _errors.size())
		for e: String in _errors:
			print("   - " + e)
		quit(1)
		return

	print("   报头：%s · %s" % [data.masthead, data.edition])
	print("   主标题：%s / %s" % [data.title, data.product])
	print("   正文 %d 段；A2 %d 句；A3 %d 句" % [
		data.body.split("\n").size(), data.lines_a2.size(), data.lines_a3.size()])
	print("")
	print("✅ 已生成 " + OUT_PATH)
	quit(0)


# ============================================================
# 解析
# ============================================================
## 切出 {小节名 -> [原始行]}。只认 `## ` 开头的行；`>` 引用块在第一个小节之前，
## 自然被跳过。
func _split_sections(raw: String) -> Dictionary:
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
		(sections[current] as Array).append(t)
	return sections


func _parse_a1(lines: Array, data: Variant) -> void:
	var body: Array[String] = []
	for raw: Variant in lines:
		var t := String(raw).strip_edges()
		if t.is_empty():
			continue
		var idx := t.find("|")
		if idx < 0:
			_errors.append("A1 有一行没有 `键|值`：" + t)
			continue
		var key := t.substr(0, idx).strip_edges()
		var val := t.substr(idx + 1).strip_edges()
		if not A1_FIELDS.has(key):
			_errors.append("A1 不认识的字段「%s」" % key)
			continue
		match key:
			"报头": data.masthead = val
			"版次": data.edition = val
			"主标题": data.title = val
			"产品": data.product = val
			"副标题": data.subtitle = val
			"正文": body.append(val)
			"倒计时": data.countdown = val
			"落款": data.footer = val
	data.body = "\n".join(body)


## A2 / A3：一行一句。原文里的空行是排版用的，不是一句台词，直接丢掉。
func _lines_of(lines: Array) -> Array[String]:
	var out: Array[String] = []
	for raw: Variant in lines:
		var t := String(raw).strip_edges()
		if not t.is_empty():
			out.append(t)
	return out
