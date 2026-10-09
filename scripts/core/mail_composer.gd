class_name MailComposer
extends RefCounted
## 把模板里的【替换字段】填成真正能读的邮件
##
## 【纯逻辑】不继承 Node、不读文件 —— 数值模拟器要能直接调它生成几千封回信。
##
## 【为什么抽定角和填字段要分开】
## 抽签（剧名 / 角色名 / 地点）必须**只抽一次然后存进履历**。如果每次显示都重抽，
## 玩家读档回来会发现同一部戏改名了。所以：
##   roll_casting() 由调用方在**投递那一刻**调一次，结果写进 GameState.history；
##   compose()     是纯函数，只做字符串替换，同一份 ctx 永远得到同一封邮件。


## 游戏 Day 1 = 2026-10-09（见开发计划开头的工期）
const START_YEAR := 2026
const START_MONTH := 10
const START_DAY := 9
const MONTH_DAYS: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

## 进组 / 回复期限相对投递当天的偏移
const SHOOT_OFFSET := 3
const DEADLINE_OFFSET := 1

## 模板里真正会被替换的字段名。**新增字段必须同时在这里登记**，
## 否则 find_leftovers() 会把它当成「没填上」报出来 —— 这是故意的。
const FIELDS: Array[String] = [
	"玩家名", "公司名", "剧名", "角色名", "角色定位",
	"日期", "地点", "截止时间", "报道对象",
]


# ============================================================
# 定角抽签
# ============================================================

## 抽一次定角信息。同一个 seed 永远得到同一组结果（存进履历后可复现）。
## seed 建议用 `day * 1000 + submissions_total`，保证同一天不同次投递不撞车。
static func roll_casting(pool: CastingPool, seed_value: int, role_tier: int) -> Dictionary:
	if pool == null:
		push_error("[MailComposer] 定角池为空")
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return {
		"剧名": _one_of(rng, pool.play_titles),
		"角色名": _one_of(rng, pool.role_names_for(role_tier)),
		"地点": _one_of(rng, pool.places),
		"玩家名": pool.player_name,
	}


static func _one_of(rng: RandomNumberGenerator, bucket: Array[String]) -> String:
	if bucket.is_empty():
		return ""
	return bucket[rng.randi_range(0, bucket.size() - 1)]


# ============================================================
# 填字段
# ============================================================

## 把「一次投递」的全部已知信息拼成替换字段表。
##
## 【为什么放在这里而不是 Game 里】让 headless 测试和真实投递走**同一条代码路径**。
## 两边各拼一遍的话，测试通过但游戏里漏字段这种事迟早会发生。
##
## 【注意没有「报道对象」】那个字段是**电子报**用的（按知名度决定点名还是写「男主」），
## 邮件文案里一个都没用到。故意不在这里填：将来真有邮件用了它，find_leftovers()
## 会当场把它抓出来，而不是悄悄填成空字符串。做《有瓜有戏》时再补规则。
static func build_context(company: CompanyData, role: RoleRequirement,
		casting: Dictionary, day: int) -> Dictionary:
	var dates := date_labels(day)
	return {
		"玩家名": casting.get("玩家名", ""),
		"公司名": company.display_name,
		"剧名": casting.get("剧名", ""),
		"角色名": casting.get("角色名", ""),
		"角色定位": role.tier_name(),
		"日期": dates["日期"],
		"地点": casting.get("地点", ""),
		"截止时间": dates["截止时间"],
		# 署名里的裸公司名靠这两个键替换
		"code": company.code,
		"company_name": company.display_name,
	}


## 一次投递的回信 —— 取成败对应的那封信并填好字段
static func compose_reply(template: MailTemplate, company: CompanyData,
		role: RoleRequirement, casting: Dictionary, day: int, passed: bool) -> Dictionary:
	if template == null:
		return {"subject": "", "body": "", "signature": "", "text": ""}
	return compose(template.letter(passed), build_context(company, role, casting, day))


## 拼好一封可以直接显示的邮件。
## ctx 必须含有 FIELDS 里模板用到的字段（缺的会保留成【xx】并被 find_leftovers 抓到）。
static func compose(letter: MailLetter, ctx: Dictionary) -> Dictionary:
	if letter == null:
		return {"subject": "", "body": "", "signature": "", "text": ""}
	var out := {
		"subject": fill(letter.subject, ctx),
		"body": fill(letter.body, ctx),
		"signature": fill(letter.signature, ctx),
	}
	out["text"] = "%s\n\n%s\n\n%s" % [out["subject"], out["body"], out["signature"]]
	return out


## 单个字符串的字段替换。
##
## 【只替换 ctx 里真的有的键】缺字段时保留 `【xx】` 原样，好让 find_leftovers()
## 当场抓到，而不是悄悄替换成空字符串、把「没填上」伪装成「文案就是这样」。
static func fill(text: String, ctx: Dictionary) -> String:
	var out := text
	for key: String in FIELDS:
		if ctx.has(key):
			out = out.replace("【%s】" % key, str(ctx[key]))
	# 署名里的公司名是**裸写法**（`**A公司｜选角组**`，不在【】里），按代号补一刀。
	# 公司真名还没定（狗牙在填），所以 display_name 为空时跳过，保留「A公司」也不算错。
	var code := str(ctx.get("code", ""))
	var display := str(ctx.get("company_name", ""))
	if not code.is_empty() and not display.is_empty():
		out = out.replace("%s公司" % code, display)
	return out


## 还有哪些字段没被替换掉 —— 测试用它断言「没有漏网的方块」
static func find_leftovers(text: String) -> Array[String]:
	var out: Array[String] = []
	for key: String in FIELDS:
		if text.contains("【%s】" % key):
			out.append(key)
	return out


# ============================================================
# 日期
# ============================================================

## 投递当天 → 邮件里要写的进组日期 / 回复期限。
## 返回 {"日期": "10 月 12 日", "截止时间": "10 月 10 日"}
static func date_labels(day: int) -> Dictionary:
	return {
		"日期": date_label(day + SHOOT_OFFSET),
		"截止时间": date_label(day + DEADLINE_OFFSET),
	}


## 游戏内第 N 天（1 起）→「10 月 12 日」
static func date_label(day: int) -> String:
	var d := date_of(day)
	return "%d 月 %d 日" % [d["month"], d["day"]]


static func date_of(day: int) -> Dictionary:
	var doy := day_of_year(START_MONTH, START_DAY) + (day - 1)
	var month := 0
	while month < 12 and doy > MONTH_DAYS[month]:
		doy -= MONTH_DAYS[month]
		month += 1
	return {"year": START_YEAR, "month": month + 1, "day": maxi(doy, 1)}


static func day_of_year(month: int, day: int) -> int:
	var n := day
	for i in range(0, month - 1):
		n += MONTH_DAYS[i]
	return n
