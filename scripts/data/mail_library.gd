class_name MailLibrary
extends RefCounted
## 邮件模板 / 定角池的**唯一读取入口**
##
## 【和 PartLibrary 是同一套思路】静态缓存、不放 autoload、不继承 Node。
## 读目录属于 IO，不属于判定层，所以放 `scripts/data/`。
##
## 【为什么模板按公司代号约定文件名】`data/mails/A.tres` ↔ 公司 `code == "A"`。
## 不额外维护映射表；`tools/test_mail.gd` 会断言「五家公司一一对应」，
## 少一封会在测试里当场炸，而不是等玩家点了发送才发现没回信。


const MAIL_DIR := "res://data/mails"
const POOL_PATH := "res://data/casting_pool.tres"

static var _by_code: Dictionary = {}   ## "A" -> MailTemplate
static var _pool: CastingPool
static var _loaded := false


static func for_company(code: String) -> MailTemplate:
	_ensure()
	return _by_code.get(code, null)


static func all() -> Array[MailTemplate]:
	_ensure()
	var out: Array[MailTemplate] = []
	for t: MailTemplate in _by_code.values():
		out.append(t)
	return out


static func casting_pool() -> CastingPool:
	_ensure()
	return _pool


static func count() -> int:
	_ensure()
	return _by_code.size()


static func reload() -> void:
	_by_code.clear()
	_pool = null
	_loaded = false


# ============================================================
static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true

	# 【必须走 ResourceDir】与 PartLibrary 同病：导出包里是 `A.tres.remap`，
	# 手写后缀判断会让五封邮件模板全读不到 —— 发送表情包投递后收不到回信。
	for path: String in ResourceDir.list_tres(MAIL_DIR):
		var res: Resource = load(path)
		if res is MailTemplate:
			var t := res as MailTemplate
			_by_code[t.company_code] = t
		else:
			push_error("[MailLibrary] %s 不是 MailTemplate，已跳过" % path)

	var pool_res: Resource = load(POOL_PATH)
	if pool_res is CastingPool:
		_pool = pool_res as CastingPool
	else:
		push_error("[MailLibrary] 读不到定角池 " + POOL_PATH)
