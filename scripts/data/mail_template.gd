class_name MailTemplate
extends Resource
## 一家公司的试镜邮件模板 = 成功一封 + 失败一封
##
## 【来源】由 `tools/gen_mails.gd` 从 `data/mails/{A..E}.md` 解析生成。
## 那两份 docx 是**内容源**，`.md` 是它的可读副本；改文案改 `.md` 然后重跑生成脚本。
## ⚠️ 不要直接手改 `data/mails/*.tres`，会被生成脚本覆盖。

@export var company_code: String = ""
@export var success: MailLetter
@export var fail: MailLetter


func letter(passed: bool) -> MailLetter:
	return success if passed else fail
