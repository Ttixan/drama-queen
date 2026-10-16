class_name ScriptLibrary
extends RefCounted
## 剧本库 —— 微信里 HR 发的那几份 `.docx` 的**唯一读取入口**
##
## 【和 MailLibrary 同一套】静态缓存、不放 autoload、不继承 Node ——
## 读目录属于 IO，不属于判定层，所以放 `scripts/data/`。
##
## 【为什么按 (剧本, 档位) 取】一份剧本 = 三个视角 = 三个档位各一份文档。
## 玩家点「配角」，抽的是**三份剧本里某一个的配角视角**；
## 存档里只记 (play_index, tier) 这两个数 —— 文案怎么改、id 怎么变，读档都还原得回来。

const SCRIPT_DIR := "res://data/scripts"

static var _by_id: Dictionary = {}     ## "play1_v3" -> ScriptDoc
static var _loaded := false


static func all() -> Array[ScriptDoc]:
	_ensure()
	var out: Array[ScriptDoc] = []
	for doc: ScriptDoc in _by_id.values():
		out.append(doc)
	# 字典顺序 = 目录顺序，不稳定。按 id 排一遍，抽签与测试才有可复现的顺序
	out.sort_custom(func(a: ScriptDoc, b: ScriptDoc) -> bool:
		return String(a.id) < String(b.id))
	return out


static func count() -> int:
	_ensure()
	return _by_id.size()


static func by_id(id: String) -> ScriptDoc:
	_ensure()
	return _by_id.get(id, null)


## 指定剧本 + 档位的那一份。**读档走这条路**（存档记的是 play_index 与 tier）。
static func for_play_tier(play_index: int, tier: int) -> ScriptDoc:
	_ensure()
	for doc: ScriptDoc in _by_id.values():
		if doc.play_index == play_index and doc.tier == tier:
			return doc
	return null


## 抽一份：从「三份剧本里这一档的那三份」中挑。`seed_value` 固定 → 抽到同一份。
##
## 【为什么要抽而不是全给】「剧本从我们写的三个里面抽取」（提提 10-16）——
## 玩家每要一次剧本会拿到不同的一本，这是内容量被反复利用的方式。
static func pick_for_tier(tier: int, seed_value: int) -> ScriptDoc:
	_ensure()
	var pool: Array[ScriptDoc] = []
	for doc: ScriptDoc in all():
		if doc.tier == tier:
			pool.append(doc)
	if pool.is_empty():
		push_error("[ScriptLibrary] 没有档位 %d 的剧本 —— 跑过 tools/gen_scripts.gd 了吗？" % tier)
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return pool[rng.randi_range(0, pool.size() - 1)]


static func reload() -> void:
	_by_id.clear()
	_loaded = false


# ============================================================
static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true

	# 【必须走 ResourceDir】与 MailLibrary 同病：导出包里是 `play1_v1.tres.remap`，
	# 手写后缀判断会让九份剧本全读不到 —— 玩家要剧本时 HR 那边一声不响
	# （`data/scripts/` 里还躺着 md 源文件，它们不是资源，本来就不该被列出来）。
	for path: String in ResourceDir.list_tres(SCRIPT_DIR):
		var res: Resource = load(path)
		if res is ScriptDoc:
			var doc := res as ScriptDoc
			_by_id[String(doc.id)] = doc
		else:
			push_error("[ScriptLibrary] %s 不是 ScriptDoc，已跳过" % path)
