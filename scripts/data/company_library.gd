class_name CompanyLibrary
extends RefCounted
## 五家公司的**唯一读取入口**（与 PartLibrary / MailLibrary 同一套路数）
##
## 【为什么要有它】在这之前只有 `tools/test_data.gd` 会 `load("A.tres")`，
## 界面拿不到公司。Boss直聘、微信都要按 `code` 选公司，再抄一遍加载循环迟早会走岔。
##
## 【为什么显式按 code 排序】`DirAccess` 的列出顺序不保证稳定，
## 而联系人列表 / 公司列表的顺序一变，玩家的肌肉记忆就废了。


const COMPANY_DIR := "res://data/companies"
const CODES: Array[String] = ["A", "B", "C", "D", "E"]

static var _all: Array[CompanyData] = []
static var _by_code: Dictionary = {}
static var _loaded := false


static func all() -> Array[CompanyData]:
	_ensure()
	var out: Array[CompanyData] = []
	for c: CompanyData in _all:
		out.append(c)
	return out


static func by_code(code: String) -> CompanyData:
	_ensure()
	return _by_code.get(code, null)


static func count() -> int:
	_ensure()
	return _all.size()


static func reload() -> void:
	_all.clear()
	_by_code.clear()
	_loaded = false


# ============================================================
static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	for code: String in CODES:
		var res: Resource = load("%s/%s.tres" % [COMPANY_DIR, code])
		if res is CompanyData:
			var c := res as CompanyData
			_by_code[code] = c
			_all.append(c)
		else:
			push_error("[CompanyLibrary] %s.tres 不是 CompanyData 或不存在" % code)
