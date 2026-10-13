class_name EventData
extends Resource
## 一个周初随机事件
##
## 【它在流程里的位置】GDD 3.5「阶段1：周初（事件推送）」—— 每周开头触发一个，
## 玩家在**微信**里读，可能做出选择（GDD 四、系统划分：微信 =「联系其他人（随机事件）」）。
## 所以事件不是弹窗，是**一条会话**：有说话的人、有他说的话、有玩家回的那一句。
##
## 【为什么说话人是一整组字段而不是一个联系人 id】
## 事件之间不复用说话人（导演 / 熟人 / 朋友 / 培训班各说各的），
## 造一层「联系人表」只会多一张要维护的表，而且文案里本来就带称呼。
##
## 【为什么周次是数据而不是代码里的 switch】
## M3 写的是「21 周事件表：前 10 周手写，后 11 周模板 + 条件差分」，
## 但游戏实际是 21 **天** = 3 周（数值表 sheet 1 `total_days=21`）。
## 两种读法差了 7 倍的内容量，这事要狗牙确认 —— 在此之前，
## **周次只能从数据里来**，代码不许假设一共几周，改周数不该动一行代码。

## 事件 id。存进履历与「已出现过」列表，改名等于改存档，慎重。
@export var id: StringName = &""

@export_group("说话的人")
## 联系人代号。同一个人的多条事件共用它 —— 微信按它归并会话。
@export var speaker: StringName = &""
## 微信会话列表里显示的名字（「王导」「老同学」）
@export var speaker_name: String = ""
## 开场白。可以带替换字段（【玩家名】【公司名】等），走 MailComposer.fill()
@export_multiline var intro: String = ""

@export_group("排期")
## 出现在第几周。0 = 任何一周都可以（进候选池由抽签决定）
@export var week: int = 0
## 同一周有多个候选时，数字大的优先；同分才抽签。
## 【为什么要这个】手写的那几周是**指定内容**（那一周就该演那一出），
## 而模板事件是池子。用优先级就把「指定」与「随机」装进同一个字段，不用两套机制。
@export var priority: int = 0
## 同一局里能不能重复出现
@export var repeatable: bool = false

@export_group("出现条件（负数 = 不设门槛）")
## 手里至少有多少钱。`朋友借钱` 没钱可借就不该出现。
## 【为什么默认 -1 而不是 0】钱可以是负的（房租能扣成欠债，见决策），
## 所以「≥ 0」不是无条件，而是「不许欠债玩家看见这条」—— 一条隐藏门槛。
@export var require_money_min: int = -1
## 演技至少多少。够不着门槛的机会事件不该撩玩家。
@export var require_acting_min: int = -1

@export_group("选项")
## 固定两个（GDD 的选项A / 选项B）。
## 【为什么正好两个】GDD 那张表就是二选一，界面也按两列排。
## 但这里不写成 a_/b_ 两组独立字段 —— 用数组，将来加第三个不用动判定与界面。
@export var options: Array[EventOption] = []


## 给界面与履历用的标题（会话列表里那行摘要）
func display_title() -> String:
	if not speaker_name.is_empty():
		return speaker_name
	return String(id)


## 选项够不够、说话人填没填 —— 内容没配好时在测试里当场炸，而不是等玩家点到空白
func validate() -> Array[String]:
	var out: Array[String] = []
	if id.is_empty():
		out.append("（有个事件没填 id）")
		return out
	if speaker.is_empty():
		out.append("%s：没填说话人代号" % id)
	if speaker_name.is_empty():
		out.append("%s：没填说话人名字（微信里会显示成空）" % id)
	if intro.strip_edges().is_empty():
		out.append("%s：开场白是空的" % id)
	if options.size() != 2:
		out.append("%s：选项应该是 2 个，实际 %d 个" % [id, options.size()])
	for i in options.size():
		var o: EventOption = options[i]
		if o == null:
			out.append("%s：选项 %d 是空的" % [id, i + 1])
		elif o.label.strip_edges().is_empty():
			out.append("%s：选项 %d 没填按钮文字" % [id, i + 1])
	if options.size() == 2 and not has_free_option():
		# 【为什么这条是硬约束】行动点是唯一不能欠的资源，而玩家可能把当天的点
		# 花光了才来看事件。若两个选项都收行动点，这一周就会被卡死。
		# GDD 本来就给了出路：每个事件的拒绝项（不去 / 拒 / 不买）都是免费的。
		out.append("%s：两个选项都要行动点 —— 玩家没点时会被卡住，至少留一个免费的" % id)
	return out


func has_free_option() -> bool:
	for o: EventOption in options:
		if o != null and o.ap_cost <= 0:
			return true
	return false
