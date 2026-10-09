class_name MailLetter
extends Resource
## 一封邮件（主题 / 正文 / 署名）
##
## 【为什么拆成三级（公司 → 成败 → 主题/正文/署名）】
## 邮件文案是**内容**，狗牙要能独立改。拆到这一级之后，他在检查器里就能直接编辑，
## 不需要碰 `data/mails/*.md` 的解析规则，也不需要碰代码。
##
## 【为什么不用一个 String 装整封】电子报要按「主题」判标题档位，
## 钱包（投递结果卡片）只要正文。三者分开存，任何一处都不用做字符串切分。

@export var subject: String = ""
@export_multiline var body: String = ""
@export var signature: String = ""


## 拼成一条可见的纯文本（气泡里直接显示这个）
func to_text() -> String:
	var out := subject
	if not body.is_empty():
		out += "\n\n" + body
	if not signature.is_empty():
		out += "\n\n" + signature
	return out
