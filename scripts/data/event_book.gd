class_name EventBook
extends Resource
## 一整本周初事件（`data/events/events.md` 转出来的那本）
##
## 【为什么是一本而不是一堆 .tres】事件是一张**表**（M3 管它叫「事件表」）：
## 「第 1 周演哪一出」只有在能按周横着看的时候才看得出节奏对不对。
## 一个数组装整本，狗牙在检查器里能滚动浏览。
##
## 【这里只回答「有哪些事件」】哪一条该出现在这一周、条件够不够、抽签怎么抽，
## 都是**规则**，在 `scripts/core/event_scheduler.gd`。与 HeadlineBook / HeadlineComposer
## 的分工同一个道理。

@export var entries: Array[EventData] = []


func is_empty() -> bool:
	return entries.is_empty()


func find(id: StringName) -> EventData:
	for e: EventData in entries:
		if e.id == id:
			return e
	return null


## 某一周的专属事件（`week` 字段正好等于它）
func for_week(week: int) -> Array[EventData]:
	var out: Array[EventData] = []
	for e: EventData in entries:
		if e.week == week:
			out.append(e)
	return out


## 通用池：不挑周次（`week == 0`），任何一周都可以被抽中
func any_week() -> Array[EventData]:
	return for_week(0)


## 已经排了专属事件的周次（升序）。界面/测试拿它看「排期铺到第几周了」
func scheduled_weeks() -> PackedInt32Array:
	var seen := {}
	for e: EventData in entries:
		if e.week > 0:
			seen[e.week] = true
	var out := PackedInt32Array()
	for w: int in seen.keys():
		out.append(w)
	out.sort()
	return out


## 前 total_weeks 周里，哪几周**既没有专属事件、也没有通用池**可用。
## 【为什么这条要单独检】少一周的专属事件在编辑器里完全看不出来 ——
## 要玩到那一周才会发现「这周什么也没发生」。测试拿它当场断言。
func missing_weeks(total_weeks: int) -> Array[int]:
	var out: Array[int] = []
	# 有通用池兜底时，每周都排得出事件，就不存在「缺」——
	# 只是那几周没有「专属」的安排（排期铺够没有，由 scheduled_weeks() 回答）。
	if not any_week().is_empty():
		return out
	for w in range(1, total_weeks + 1):
		if for_week(w).is_empty():
			out.append(w)
	return out


## 内容自检。测试直接断言它为空数组 —— 空白文案要在这里当场炸，
## 而不是等玩家在微信里点开一条空的会话。
func validate() -> Array[String]:
	var out: Array[String] = []
	var ids := {}
	for e: EventData in entries:
		if e == null:
			out.append("（事件表里有一个空条目）")
			continue
		out.append_array(e.validate())
		if ids.has(e.id):
			out.append("%s：id 重复" % e.id)
		ids[e.id] = true
		if e.week < 0:
			out.append("%s：week 不能是负数（0 表示通用池）" % e.id)
	return out
