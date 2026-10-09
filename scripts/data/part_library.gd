class_name PartLibrary
extends RefCounted
## 运行时部件库 —— 32 件 PartData 的**唯一读取入口**
##
## 【为什么需要它】
## 在这之前，只有 `tools/test_data.gd` 里的私有方法会读 `data/parts`。那是测试脚本，
## 界面拿不到部件。UI 要列部件就必须有个正式入口，否则每个 App 都要自己抄一遍
## `DirAccess + load` 的循环 —— 而且一定会漏掉「其他可以留空」这条规则。
##
## 【为什么是 static 缓存，不是 autoload】
## 32 个 Resource 加载一次就够，进程内复用。做成 autoload 等于往全局命名空间里
## 塞一个只有两个界面会用到的东西；`data/` 这一层本来就不该有生命周期。
##
## 【为什么放 scripts/data/ 而不是 scripts/core/】
## `core/` 是纯判定逻辑，必须能在数值模拟器里 headless 跑、不碰文件系统。
## 读目录属于 IO，不属于判定。


const PART_DIR := "res://data/parts"

## 页签顺序 —— 必须与 PartData.Slot 的枚举顺序一致，UI 直接用它排页签。
const TAB_ORDER: Array[int] = [
	PartData.Slot.EYES,
	PartData.Slot.MOUTH,
	PartData.Slot.BROWS,
	PartData.Slot.EXTRA,
]

## 「其他」槽位的留空选项。
## 【为什么用 null 而不是造一件「空部件」】造空部件就要给它情绪向量，而「没有情绪」
## 和「情绪为零的部件」是两回事 —— 前者是玩家表达里的一种选择，后者是数据。
## 另外 Clip.Frame.extra 本来就允许 null，UI 直接用 null 才不会多一层转换。
const EMPTY_EXTRA: PartData = null

static var _all: Array[PartData] = []
static var _by_id: Dictionary = {}  ## String -> PartData
static var _loaded := false


# ============================================================
# 读取
# ============================================================

## 全量部件，按「槽位顺序 → tier 升序」排好。
## 返回副本 —— UI 拿到的是自己的数组，乱改不会污染缓存。
static func all() -> Array[PartData]:
	_ensure()
	var out: Array[PartData] = []
	for p: PartData in _all:
		out.append(p)
	return out


## 某个槽位的部件，tier 升序。
static func by_slot(slot: int) -> Array[PartData]:
	_ensure()
	var out: Array[PartData] = []
	for p: PartData in _all:
		if p.slot == slot:
			out.append(p)
	return out


## 某个槽位在 UI 里的全部选项。
## 【与 by_slot 的唯一区别】EXTRA 的选项列表**首位固定是 null**（留空）。
## 组合数 8×10×8×7 里的那个 7 = 6 件「其他」+ 1 种留空。
static func slot_options(slot: int) -> Array:
	if slot == PartData.Slot.EXTRA:
		var out: Array = [EMPTY_EXTRA]
		out.append_array(by_slot(slot))
		return out
	return by_slot(slot)


static func by_id(id: String) -> PartData:
	_ensure()
	return _by_id.get(id, null)


static func count() -> int:
	_ensure()
	return _all.size()


static func is_empty() -> bool:
	return count() == 0


## 清空缓存。只给测试与「策划改了 .tres 想在编辑器里立刻看到」用。
static func reload() -> void:
	_all.clear()
	_by_id.clear()
	_loaded = false


# ============================================================
# 内部
# ============================================================

static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true

	var raw := _read_dir()
	if raw.is_empty():
		push_error("[PartLibrary] %s 里一个部件都没读到 —— 是不是忘了跑 tools/gen_data.gd？" % PART_DIR)
		return

	# 按槽位顺序装进 _all，这样 by_slot() 直接过滤就天然是 tier 升序。
	# 【为什么不用 sort_custom】static 上下文里传比较器 Callable 容易踩坑，
	# 而每组最多 10 个元素，手写插入排序更直白。
	for slot: int in TAB_ORDER:
		var bucket: Array[PartData] = []
		for p: PartData in raw:
			if p.slot == slot:
				bucket.append(p)
		_sort_by_tier(bucket)
		for p: PartData in bucket:
			var key := String(p.id)
			if _by_id.has(key):
				push_error("[PartLibrary] 部件 id 重复：%s（后一件被忽略）" % key)
				continue
			_by_id[key] = p
			_all.append(p)


static func _read_dir() -> Array[PartData]:
	var out: Array[PartData] = []
	var dir := DirAccess.open(PART_DIR)
	if dir == null:
		push_error("[PartLibrary] 打不开目录 " + PART_DIR)
		return out
	for f: String in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var res: Resource = load("%s/%s" % [PART_DIR, f])
		if res is PartData:
			out.append(res as PartData)
		else:
			push_error("[PartLibrary] %s 不是 PartData，已跳过" % f)
	return out


static func _sort_by_tier(arr: Array[PartData]) -> void:
	for i in range(1, arr.size()):
		var cur := arr[i]
		var j := i - 1
		while j >= 0 and arr[j].tier > cur.tier:
			arr[j + 1] = arr[j]
			j -= 1
		arr[j + 1] = cur
