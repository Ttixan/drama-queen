class_name BalanceLibrary
extends RefCounted
## 数值镜像的**唯一读取入口**（与 PartLibrary / CompanyLibrary / MailLibrary 同一套路数）
##
## 【为什么不让各处直接 load()】数值是所有系统的公共输入，
## 散落的 `load("res://data/balance.tres")` 会让「谁在什么时候读了它」变成谜。
## 这里做一层静态缓存，顺带保证读到的确实是 `BalanceData` 而不是别的资源。

const PATH := "res://data/balance.tres"

static var _data: BalanceData


static func data() -> BalanceData:
	_ensure()
	return _data


static func reload() -> void:
	_data = null


# ============================================================
static func _ensure() -> void:
	if _data != null:
		return
	var res: Resource = load(PATH)
	if res is BalanceData:
		_data = res
	else:
		# 【为什么退回默认值而不是返回 null】调用方分布在 Economy / Broadcast / 订单界面，
		# 任何一处拿到 null 都会在玩家第一次打工时崩掉，而且崩得毫无线索。
		# 退回「与数值表一致的默认值」能继续玩，同时这条 push_error 会在启动时就喊出来。
		push_error("[BalanceLibrary] 读不到 %s，已退回默认数值 —— 请检查文件是否存在" % PATH)
		_data = BalanceData.new()
