class_name EventOption
extends Resource
## 随机事件的一个选项（GDD 3.4 那张表里的「选项A / 选项B」）
##
## 【为什么效果做成「字段 + 增量」而不是一段脚本】
## 选项的效果是**纯数值加减**（GDD 只定义了 钱 / 时间 / 演技 三种），
## 一旦允许挂脚本，策划改文案就得碰代码，而且模拟器再也算不出「这个事件值不值得选」。
## 现在这一份字段同时喂给三处：判定（`EventActions`）、界面（按钮上的门槛提示）、
## 模拟器（评估事件对平衡的影响）—— 它们读同一份数据，不会各说各话。
##
## 【为什么把 ap_cost 单列出来】行动点是本作**唯一不能欠的资源**（数值表 sheet 1：
## 「钱能欠，行动点不能」）。所以它不能混在 money 里，界面也必须能单独把它显示成门槛。


## 按钮上的字。GDD 用的是「去 / 不去」「接 / 拒」这种短词 —— 保持短，按钮才放得下。
@export var label: String = ""
## 玩家选完之后，对方回的话（微信里紧接着玩家那条气泡出现）
@export_multiline var reply: String = ""
## 结果说明，给履历 / 结算界面用。留空则界面只显示数值变化。
@export_multiline var note: String = ""

@export_group("代价与收益")
## 消耗行动点。0 = 免费（「不去」「拒」「不买」这类拒绝项都是 0）
@export var ap_cost: int = 0
@export var money: int = 0
@export var acting: int = 0
@export var fame: int = 0
@export var reputation: int = 0


## 这个选项会改动哪些属性 —— 界面拿它决定「要不要显示一行变化」
func has_effect() -> bool:
	return money != 0 or acting != 0 or fame != 0 or reputation != 0


func describe() -> String:
	var parts: Array[String] = []
	if ap_cost != 0:
		parts.append("行动点 %+d" % -ap_cost)
	if money != 0:
		parts.append("钱 %+d" % money)
	if acting != 0:
		parts.append("演技 %+d" % acting)
	if fame != 0:
		parts.append("知名度 %+d" % fame)
	if reputation != 0:
		parts.append("风评 %+d" % reputation)
	return "、".join(parts) if not parts.is_empty() else "无消耗"
