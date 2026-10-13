class_name HeadlineLibrary
extends RefCounted
## 电子报标题库的**唯一读取入口**（与 PartLibrary / CompanyLibrary / MailLibrary 同一套路数）
##
## 【为什么标题也要转 .tres 而不是运行时读 md】和邮件同一个原因：
## `.md` 不在 Godot 的导出白名单里，打包之后 `res://data/news/headlines.md` 会不存在，
## 那时候才发现「周末结算一条标题都没有」已经来不及了。

const PATH := "res://data/news/headlines.tres"

static var _book: HeadlineBook


static func book() -> HeadlineBook:
	_ensure()
	return _book


static func all() -> Array[Headline]:
	_ensure()
	return _book.entries


static func count() -> int:
	_ensure()
	return _book.entries.size()


static func find_main(code: String, grade: int) -> Headline:
	_ensure()
	return _book.find_main(code, grade)


static func find_extra(grade: int, play_good: int) -> Headline:
	_ensure()
	return _book.find_extra(grade, play_good)


static func find_kind(kind: StringName) -> Headline:
	_ensure()
	return _book.find_kind(kind)


static func reload() -> void:
	_book = null


# ============================================================
static func _ensure() -> void:
	if _book != null:
		return
	var res: Resource = load(PATH)
	if res is HeadlineBook:
		_book = res
	else:
		# 退回空本而不是 null：周末结算会因此少几张头条（难看但不崩），
		# 而这行 push_error 会在启动时就把它喊出来。
		push_error("[HeadlineLibrary] 读不到 %s，已退回空标题本 —— 请重跑 tools/gen_headlines.gd" % PATH)
		_book = HeadlineBook.new()
