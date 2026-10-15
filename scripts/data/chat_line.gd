class_name ChatLine
extends Resource
## 一条聊天消息（Boss直聘 的「初次沟通」对话用）
##
## 【为什么是资源而不是两个字符串】对话是**内容**，狗牙要改；而它挂在公司数据上。
## 与 `AuditionCondition` 同一个做法：md 里写字，`tools/gen_data.gd` 转成 `.tres`。
##
## `who` 只有三个取值（md 里也照这三个写）：
##   `"hr"`     HR 说的 —— 左边灰泡
##   `"me"`     玩家说的 —— 右边绿泡（就是「你」那一侧）
##   `"system"` 系统提示 —— 居中一行小字。**这一种游戏自己会发**（「已加进微信」之类），
##              所以正常不该出现在 md 里；留着是为了让文案也能加旁白
@export var who: String = "hr"
@export_multiline var text: String = ""


## 给界面用的一行话（顺便挡掉空行与多余空白 —— md 里手写表格很容易多打空格）
func display_text() -> String:
	return text.strip_edges()


## 是不是「游戏发的」那一类
func is_system() -> bool:
	return who == "system"


## 是不是玩家自己说的
func is_mine() -> bool:
	return who == "me"


## 是不是「给玩家挑」的一句 —— 连着几条 `choice` 就是一组选项（md 里写 `选`）。
## 界面上把它们竖排成几个按钮；玩家点了哪句，哪句就作为他自己发的消息出现。
## 【为什么选项要占几条数据、而不是一条带三个子项】这样 md 里就是一张平表，
## 狗牙加一句、删一句都只是改一行；连着的 `choice` 自然成一组，不用另外编号。
func is_choice() -> bool:
	return who == "choice"
