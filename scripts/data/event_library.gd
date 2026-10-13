class_name EventLibrary
extends RefCounted
## 周初事件的**唯一读取入口**（与 HeadlineLibrary / PartLibrary 同一套路数）
##
## 【为什么读不到也要给一本空本而不是 null】M3 的内容还没到位时，
## 游戏必须能照常开局、照常跑完 21 天，只是「这周什么也没发生」。
## 空本让调用点不用到处判 null，而 `push_error` 会在启动时把缺内容喊出来。
##
## 【单文件而不是扫目录】事件是一张表（`events.tres`），
## 不是按公司/槽位分文件的一堆资源 —— 所以走固定路径 `load`，
## 和 HeadlineLibrary 一样，不经过 `ResourceDir`。

const PATH := "res://data/events/events.tres"

static var _book: EventBook


static func book() -> EventBook:
	_ensure()
	return _book


static func all() -> Array[EventData]:
	_ensure()
	return _book.entries


static func count() -> int:
	_ensure()
	return _book.entries.size()


static func find(id: StringName) -> EventData:
	_ensure()
	return _book.find(id)


static func is_empty() -> bool:
	return count() == 0


static func reload() -> void:
	_book = null


# ============================================================
static func _ensure() -> void:
	if _book != null:
		return
	var res: Resource = load(PATH)
	if res is EventBook:
		_book = res
	else:
		push_error("[EventLibrary] 读不到 %s，已退回空事件本 —— 周初事件会全部跳过"
				% PATH)
		_book = EventBook.new()
