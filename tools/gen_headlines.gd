extends SceneTree
## 把 `data/news/headlines.md` 解析成 `data/news/headlines.tres`
##
##   godot --headless --path <项目> --import
##   godot --headless --path <项目> --script res://tools/gen_headlines.gd
##   godot --headless --path <项目> --import     # 再让 Godot 认识新 .tres
##
## 【为什么要转，不能运行时直接读 .md】与 `gen_mails.gd` 同一个原因：
## `.md` 不在导出白名单里，打包之后会**不存在**。转成 `.tres` 才能进包，
## 也才能让狗牙在检查器里直接浏览全部标题。
##
## 【改文案的正确姿势】改 `data/news/headlines.md` → 重跑本脚本。直接改 `.tres` 会被覆盖。
##
## 【解析的前提】md 里必须是四张**标准 markdown 表**，所在小节分别是：
##   一、主要角色标题   → 3 列：公司 | 结果 | 标题
##   二、龙套标题       → 3 列：表现 | 好剧中的龙套 | 烂剧中的龙套
##   三、首次出圈与黑红 → 2 列：触发情况 | 标题
##   四、通用备选标题   → 2 列：替换用途 | 标题
## 任何一行认不出来就**报错退出**，而不是悄悄少一条标题 ——
## 「周末结算少了一条头条」在游戏里只是一次安静的空场，在测试里才炸得出来。
##
## 【已知的取舍】md 里「二、龙套标题」表格下方那段 bullet 备选
## （「龙套还在加戏」用于用力过猛…）不是表格，本轮解析不到。
## 它属于「未细分演法」那一类兜底说辞，等履历标记系统做出来再补。

const MD_PATH := "res://data/news/headlines.md"
const OUT_PATH := "res://data/news/headlines.tres"

## 段落关键词 —— 只认这几个词，而不是「第几段」。
## 狗牙在 md 里给某段加一句话、调整顺序，这里都不会跟着错位。
const KEY_MAIN := "主要角色"
const KEY_EXTRA := "龙套标题"
const KEY_SPECIAL := "出圈"
const KEY_FALLBACK := "通用备选"

const CODES: Array[String] = ["A", "B", "C", "D", "E"]

const GRADE_BY_LABEL := {
	"高分": BalanceData.Grade.HIGH,
	"普通": BalanceData.Grade.NORMAL,
	"低分": BalanceData.Grade.LOW,
}
const GRADE_SLUG := {
	BalanceData.Grade.HIGH: "high",
	BalanceData.Grade.NORMAL: "normal",
	BalanceData.Grade.LOW: "low",
}

## 「触发情况」/「替换用途」一栏的原文 → 常量。
## 【为什么用原文当键而不是行号】狗牙改 md 时改的正是这几个词，
## 对不上就当场报错，比按行号猜要安全得多。
const KIND_BY_LABEL := {
	"龙套首次出圈": Headline.KIND_EXTRA_STAR,
	"黑红条件触发": Headline.KIND_BLACK_FAME,
	"黑红后的重复曝光": Headline.KIND_BLACK_FAME_REPEAT,
	"D 高分且无烂剧经历": Headline.KIND_FALLBACK_D_HIGH,
	"D 低分且无霸总经历": Headline.KIND_FALLBACK_D_LOW,
	"烂剧中低分且未细分演法": Headline.KIND_FALLBACK_LOW_BAD,
	"B 低分需明确指向玩家": Headline.KIND_FALLBACK_B_LOW,
}

var _errors: Array[String] = []


func _initialize() -> void:
	print("")
	print("=== 生成电子报标题库 ===")
	print("")

	if not FileAccess.file_exists(MD_PATH):
		print("❌ 找不到源文件 " + MD_PATH)
		quit(1)
		return

	var sections := _split_sections(FileAccess.get_file_as_string(MD_PATH))
	var book := HeadlineBook.new()

	_parse_main(_section(sections, KEY_MAIN), book)
	_parse_extra(_section(sections, KEY_EXTRA), book)
	_parse_special(_section(sections, KEY_SPECIAL), book)
	_parse_special(_section(sections, KEY_FALLBACK), book)

	# 自检：五家 × 三档 + 龙套六条 + 三条特殊，一条都不能少
	for m: String in book.missing_slots():
		_errors.append("缺标题：" + m)

	var err := ResourceSaver.save(book, OUT_PATH)
	if err != OK:
		_errors.append("保存失败：%s" % error_string(err))

	print("")
	print("共 %d 条标题 → %s" % [book.entries.size(), OUT_PATH])
	print("")

	if _errors.is_empty():
		print("✅ 完成")
		quit(0)
	else:
		print("❌ %d 项问题：" % _errors.size())
		for e: String in _errors:
			print("   - " + e)
		quit(1)


# ============================================================
# 分段
# ============================================================
## 返回 {小节标题 -> [单元格数组]}。
## **每个小节的第一行表格行是 markdown 表头，直接丢掉** —— 不靠词表去认表头，
## 因为表头文案（「公司」「表现」「触发情况」…）本身就是内容，将来可能被改。
func _split_sections(raw: String) -> Dictionary:
	var sections := {}
	var current := ""
	var header_skipped := false
	for line: String in raw.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("## "):
			current = t.substr(3).strip_edges()
			sections[current] = []
			header_skipped = false
			continue
		if current.is_empty():
			continue
		var cells := _table_cells(t)
		if cells.is_empty():
			continue
		if not header_skipped:
			header_skipped = true   # 表头行
			continue
		(sections[current] as Array).append(cells)
	return sections


func _section(sections: Dictionary, keyword: String) -> Array:
	for name: String in sections:
		if name.contains(keyword):
			return sections[name]
	_errors.append("md 里找不到含「%s」的小节" % keyword)
	return []


## 一行 markdown 表格 → 单元格数组。不是表格行、或是只由短横线组成的分隔线，返回空数组。
func _table_cells(line: String) -> Array[String]:
	var out: Array[String] = []
	if not line.begins_with("|"):
		return out
	for raw_cell: String in line.split("|"):
		out.append(raw_cell.strip_edges())
	while not out.is_empty() and out[0].is_empty():
		out.remove_at(0)
	while not out.is_empty() and out[out.size() - 1].is_empty():
		out.remove_at(out.size() - 1)
	if out.is_empty():
		return []
	for c: String in out:
		if not c.replace("-", "").replace(":", "").is_empty():
			return out
	out.clear()
	return out


# ============================================================
# 四张表
# ============================================================
## 一、主要角色：公司 × 结果档
func _parse_main(rows: Array, book: HeadlineBook) -> void:
	for row: Array in rows:
		if row.size() != 3:
			_errors.append("主要角色表：一行有 %d 列，应该是 3 列 —— %s" % [row.size(), row])
			continue
		var code := String(row[0])
		var label := String(row[1])
		if not CODES.has(code) or not GRADE_BY_LABEL.has(label):
			_errors.append("主要角色表：认不出「%s / %s」这一行" % [code, label])
			continue
		var grade: int = GRADE_BY_LABEL[label]
		var h := Headline.new()
		h.id = StringName("main_%s_%s" % [code, GRADE_SLUG[grade]])
		h.group = Headline.Group.MAIN
		h.company_code = code
		h.grade = grade
		h.text = String(row[2])
		book.entries.append(h)


## 二、龙套：结果档 × 剧好不好。一行出两条标题。
func _parse_extra(rows: Array, book: HeadlineBook) -> void:
	for row: Array in rows:
		if row.size() != 3:
			_errors.append("龙套表：一行有 %d 列，应该是 3 列 —— %s" % [row.size(), row])
			continue
		var label := String(row[0])
		if not GRADE_BY_LABEL.has(label):
			_errors.append("龙套表：认不出表现档「%s」" % label)
			continue
		var grade: int = GRADE_BY_LABEL[label]
		for i in 2:
			var good := 1 - i   # 第 2 列 = 好剧中，第 3 列 = 烂剧中
			var h := Headline.new()
			h.id = StringName("extra_%s_%s" % [GRADE_SLUG[grade], "good" if good == 1 else "bad"])
			h.group = Headline.Group.EXTRA
			h.grade = grade
			h.play_good = good
			h.text = String(row[i + 1])
			book.entries.append(h)


## 三、四：特殊触发 / 通用备选。两张表结构相同，按「标签 → 常量」映射。
func _parse_special(rows: Array, book: HeadlineBook) -> void:
	for row: Array in rows:
		if row.size() != 2:
			_errors.append("特殊表：一行有 %d 列，应该是 2 列 —— %s" % [row.size(), row])
			continue
		var label := String(row[0])
		if not KIND_BY_LABEL.has(label):
			_errors.append("特殊表：认不出的触发条件「%s」（新加的条目要同时登记进 KIND_BY_LABEL）" % label)
			continue
		var kind: StringName = KIND_BY_LABEL[label]
		var h := Headline.new()
		h.id = StringName("special_" + String(kind))
		h.group = Headline.Group.SPECIAL
		h.kind = kind
		h.text = String(row[1])
		book.entries.append(h)
