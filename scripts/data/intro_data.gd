class_name IntroData
extends Resource
## 开场导入（A1~A3）的全部文案
##
## 【为什么是 Resource 而不是写在场景脚本里】开场是**内容**，和邮件 / 事件 / 头条一样，
## 应该由狗牙改 `.md`、重跑生成器得到 `.tres`。写死在 `intro.gd` 里的话，
## 改一句台词要改代码，也没法在检查器里通读全文。
##
## 【`.md` 进不了导出包】与 `gen_mails.gd` / `gen_headlines.gd` 同一个原因：
## 导出包里只有资源白名单，`.md` 会消失。源文件是 `data/intro/intro.md`，
## 生成器是 `tools/gen_intro.gd`，产物是本资源。
##
## 【A1 拆成字段而不是一整段】报纸版面上「报头 / 主标题 / 产品 / 倒计时」各有各的位置，
## 拆开才能各就各位；`body` 是正文，界面按段落整块排。

@export_group("A1 · 报纸整版广告")
## 报头：左上角最大的一行
@export var masthead: String = ""
## 版次：右上角的小字（第 0 期 / 增刊）
@export var edition: String = ""
## 左侧大块的广告主标题
@export var title: String = ""
## 产品名：左侧大块最重要的那一行
@export var product: String = ""
## 产品名下面的一句定性
@export var subtitle: String = ""
## 广告正文。段落之间用空行隔开，界面原样换行
@export_multiline var body: String = ""
## 倒计时，格式约定为「距离发售：21 天」（冒号前是标签、后是数字）
@export var countdown: String = ""
## 版面底部的小字（广告署名）
@export var footer: String = ""

@export_group("A2 / A3 · 独白")
## A2「回到现实」：一句一屏，点击推进
@export var lines_a2: Array[String] = []
## A3「转折：目标」：一句一屏，点击推进
@export var lines_a3: Array[String] = []


## 内容自检。测试直接断言它为空数组 —— 空文案不能等到玩家看见一块空报纸才发现。
func validate() -> Array[String]:
	var out: Array[String] = []
	for item: Array in [
		["报头", masthead], ["版次", edition], ["主标题", title],
		["产品", product], ["副标题", subtitle], ["倒计时", countdown],
	]:
		if String(item[1]).strip_edges().is_empty():
			out.append("A1 的「%s」是空的" % item[0])
	if body.strip_edges().is_empty():
		out.append("A1 的广告正文是空的")

	for i: int in lines_a2.size():
		if lines_a2[i].strip_edges().is_empty():
			out.append("A2 第 %d 句是空的" % (i + 1))
	if lines_a2.is_empty():
		out.append("A2 一句台词都没有")
	for i: int in lines_a3.size():
		if lines_a3[i].strip_edges().is_empty():
			out.append("A3 第 %d 句是空的" % (i + 1))
	if lines_a3.is_empty():
		out.append("A3 一句台词都没有")
	return out


## 两句独白拼成一条播放序列。说话人统一「旁白」—— 原文是第二人称叙事，
## 不是角色对白；对话框的名字牌只负责告诉玩家「这句话是谁在说」。
func narration() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t: String in lines_a2:
		out.append({"speaker": "旁白", "text": t})
	for t: String in lines_a3:
		out.append({"speaker": "旁白", "text": t})
	return out
