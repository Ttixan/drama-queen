extends SceneTree
## 把 `data/events/events.md` 解析成 `data/events/events.tres`
##
##   godot --headless --path <项目> --script res://tools/gen_events.gd
##   godot --headless --path <项目> --import     # 再让 Godot 认识新 .tres
##
## 【为什么必须转，不能运行时直接读 .md】与 gen_mails / gen_headlines 同一个原因：
## `.md` 不在导出白名单里，打包之后会**不存在**。转成 `.tres` 才能进包，
## 也才能让狗牙在检查器里直接浏览全部事件。
##
## 【解析器和 md 格式是耦合的 —— 所以原则是「认不出来就报错退出」】
## 与 `gen_headlines.gd` 同一个顾虑：狗牙改格式、加个字段，如果解析器默默跳过，
## 表现是「这一周什么都没发生」——在游戏里只是一次空场，在测试里才炸得出来。
## 所以这里**没有一条静默失败路径**：不认识的字段名、不能转的整数、非法的代号，
## 全都会进 `_errors` 并让本脚本以非零码退出。
##
## 【md 里认什么】两种小节标题：`## 第 N 周`（专属，自动高优先级）与 `## 通用池`
## （不挑周次）。其余小节一律忽略。每个事件是 `### 标题` + 一张 `| 字段 | 内容 |` 表。
## 字段清单写在 `data/events/events.md` 的「格式说明」里，改格式要两边一起改。

const MD_PATH := "res://data/events/events.md"
const OUT_PATH := "res://data/events/events.tres"

const POOL_KEYWORD := "通用池"

## 选项字段：后缀 → `EventOption` 上的属性名。前缀 A / B 决定是第几个选项。
## 【为什么写成一张表】字段名要对得上资源属性，写错了 `set()` 会静默什么也不做 ——
## 有这张表就能在解析阶段把它拦成报错。
const OPTION_FIELDS := {
	"回话": "reply",
	"行动点": "ap_cost",
	"钱": "money",
	"演技": "acting",
	"知名度": "fame",
	"风评": "reputation",
	"结果": "note",
}

## 专属事件的优先级（通用池是 0）。见 `EventScheduler._top_priority`
const WEEK_PRIORITY := 10

var _errors: Array[String] = []


func _initialize() -> void:
	print("")
	print("=== 生成周初事件表 ===")
	print("")

	if not FileAccess.file_exists(MD_PATH):
		print("❌ 找不到源文件 " + MD_PATH)
		quit(1)
		return

	var book := _parse(FileAccess.get_file_as_string(MD_PATH))
	for e: String in book.validate():
		_errors.append(e)
	# 每一周都得有东西能演 —— 缺一周在编辑器里完全看不出来，
	# 要玩到那一周才会发现「这周什么也没发生」
	for w: int in book.missing_weeks(GameState.WEEKS):
		_errors.append("第 %d 周没有可用的事件（专属没写、通用池也是空的）" % w)

	var err := ResourceSaver.save(book, OUT_PATH)
	if err != OK:
		_errors.append("保存失败：%s" % error_string(err))

	print("")
	print("共 %d 个事件 → %s" % [book.entries.size(), OUT_PATH])
	print("   专属排期：%s" % _weeks_text(book))
	print("   通用池：%d 个" % book.any_week().size())
	print("")

	if _errors.is_empty():
		print("✅ 完成")
		quit(0)
	else:
		print("❌ %d 项问题：" % _errors.size())
		for e: String in _errors:
			print("   - " + e)
		quit(1)


func _weeks_text(book: EventBook) -> String:
	var weeks := book.scheduled_weeks()
	if weeks.is_empty():
		return "（无）"
	var parts: Array[String] = []
	for w: int in weeks:
		parts.append("第 %d 周" % w)
	return "、".join(parts)


# ============================================================
# 解析
# ============================================================
## `### 标题` 开一段，段内的 `| 字段 | 内容 |` 全收进 fields。
## 累积到字典里而不是立刻建资源 —— 因为字段在表里的顺序是不作保证的
## （狗牙补一个字段会插在中间），攒齐了再建。
func _parse(raw: String) -> EventBook:
	var book := EventBook.new()
	var week := -1
	var acc: Dictionary = {}
	for line: String in raw.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("## "):
			_flush(book, acc, week)
			acc = {}
			week = _week_of(t.substr(3).strip_edges())
			continue
		if t.begins_with("### "):
			_flush(book, acc, week)
			acc = {"title": t.substr(4).strip_edges(), "fields": {}}
			continue
		if acc.is_empty():
			continue
		var cells := _cells(t)
		if cells.is_empty():
			continue
		if cells.size() != 2:
			_errors.append("「%s」里有一行不是「| 字段 | 内容 |」两列：%s"
					% [acc["title"], t])
			continue
		# 【为什么只认字面的「字段」当表头】跳过表头本来是常规操作，但「跳过第一行」
		# 这种写法有个静默风险：谁要是没写表头，第一行真内容就被吃掉了。
		# 认关键词就没这个问题 —— 「字段」既不是合法字段名，也不会是任何一条内容。
		# 分隔线（|---|---|）在 _cells 里已经返回空数组，到不了这儿。
		if cells[0] == "字段":
			continue
		(acc["fields"] as Dictionary)[cells[0]] = cells[1]
	_flush(book, acc, week)
	return book


## `## 第 3 周` → 3；`## 通用池` → 0；其余（格式说明之类）→ -1（整节忽略）
func _week_of(heading: String) -> int:
	if heading.contains(POOL_KEYWORD):
		return 0
	if heading.contains("周"):
		var digits := ""
		for ch: String in heading:
			if ch >= "0" and ch <= "9":
				digits += ch
		if digits.is_empty():
			_errors.append("小节「%s」里找不到周次数字" % heading)
			return -1
		return int(digits)
	return -1


func _flush(book: EventBook, acc: Dictionary, week: int) -> void:
	if acc.is_empty() or week < 0:
		return
	book.entries.append(_build(acc, week))


func _build(acc: Dictionary, week: int) -> EventData:
	var title := String(acc["title"])
	var fields: Dictionary = acc["fields"]
	var e := EventData.new()
	e.week = week
	# 【专属事件为什么自动最高优先级】「第 N 周」那一节写的就是那一周该演的那一出；
	# 通用池只是没排到专属周次时的兜底。用优先级表达，就不用两套挑选机制。
	e.priority = WEEK_PRIORITY if week > 0 else 0

	var opts: Array[EventOption] = [EventOption.new(), EventOption.new()]
	for raw_key: String in fields:
		_apply(e, opts, title, raw_key, String(fields[raw_key]))
	e.options = opts

	if e.id.is_empty():
		_errors.append("「%s」没填 `事件代号`" % title)
	return e


func _apply(e: EventData, opts: Array[EventOption], title: String, key: String, value: String) -> void:
	match key:
		"事件代号":
			e.id = StringName(_slug(value, title, key))
		"说话人":
			e.speaker_name = value.strip_edges()
		"说话人代号":
			e.speaker = StringName(_slug(value, title, key))
		"开场白":
			e.intro = value
		"可重复":
			e.repeatable = _yes(value)
		"需钱":
			e.require_money_min = _num(value, title, key)
		"需演技":
			e.require_acting_min = _num(value, title, key)
		"选项A":
			opts[0].label = value.strip_edges()
		"选项B":
			opts[1].label = value.strip_edges()
		_:
			var idx := _option_index(key)
			if idx < 0:
				_errors.append("「%s」里有个不认识的字段「%s」（格式说明里没有它）"
						% [title, key])
				return
			var field: String = OPTION_FIELDS[key.substr(1)]
			if field == "reply" or field == "note":
				opts[idx].set(field, value)
			else:
				opts[idx].set(field, _num(value, title, key))


## `A钱` → 0、`B行动点` → 1、其余 → -1
func _option_index(key: String) -> int:
	if key.length() < 2 or not OPTION_FIELDS.has(key.substr(1)):
		return -1
	var head := key.substr(0, 1)
	if head == "A":
		return 0
	if head == "B":
		return 1
	return -1


# ============================================================
# 取值
# ============================================================
func _num(value: String, title: String, key: String) -> int:
	var v := value.strip_edges()
	if v.is_empty():
		return 0
	if not v.is_valid_int():
		_errors.append("「%s」的 `%s` 不是整数：「%s」" % [title, key, value])
		return 0
	return int(v)


func _yes(value: String) -> bool:
	var v := value.strip_edges().to_lower()
	return v == "是" or v == "true" or v == "1" or v == "yes"


## 代号只允许字母数字下划线：它要进存档，混进空格或中文迟早在某个平台上炸
func _slug(value: String, title: String, key: String) -> String:
	var v := value.strip_edges()
	if v.is_empty():
		_errors.append("「%s」的 `%s` 是空的" % [title, key])
		return ""
	for ch: String in v:
		var ok := (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") \
				or (ch >= "0" and ch <= "9") or ch == "_"
		if not ok:
			_errors.append("「%s」的 `%s` 只能用字母数字下划线：「%s」" % [title, key, v])
			return ""
	return v


## 一行 markdown 表格 → 单元格数组。不是表格行、或整行只是分隔线，返回空数组。
func _cells(line: String) -> Array[String]:
	var out: Array[String] = []
	if not line.begins_with("|"):
		return out
	for raw: String in line.split("|"):
		out.append(raw.strip_edges())
	while not out.is_empty() and out[0].is_empty():
		out.remove_at(0)
	while not out.is_empty() and out[out.size() - 1].is_empty():
		out.remove_at(out.size() - 1)
	if out.is_empty():
		return out
	for c: String in out:
		if not c.replace("-", "").replace(":", "").is_empty():
			return out
	out.clear()
	return out
