class_name Broadcast
extends RefCounted
## 播出反馈 —— 本周投出去的戏，周末统一播出
##
## 【为什么投递瞬间不发钱、不发演技】决策 1.5：投递只出通过 / 失败。
## 钱、演技、知名度、风评、负面曝光全部留到周末 —— 这样「这一周的表演」是一个整体，
## 玩家在周末看到的是「我这周播出效果怎么样」，而不是投一次抖一下数字。
##
## 【二维判定】作品质量（公司档次）决定**背景**，玩家匹配度决定**是夸还是骂**。
## 一部烂剧里可以有演得出色的演员 —— 所以 A 厂的高分标题是「又出烂片，倒把演员捧红了」，
## 而不是「A 厂出了好片」。这两件事必须在数据里分开。

## 「这部戏本身是好剧还是烂剧」—— 只用来区分**龙套**标题的口吻（好剧中的龙套 / 烂剧中的龙套）。
##
## 【口径说明 · 需要狗牙确认】按**公司档次**定：A 烂片厂、B 草台班子 = 烂剧，C/D/E = 好剧。
## 依据是 `data/news/README.md` 的「作品质量（公司档次）决定标题的背景」。
## ⚠️ 同一份文档还有一句「好剧或烂剧仍应按本次项目的结果判定」，读起来像是要按匹配度判；
## 但那样的话「好剧 × 低分」这一格永远不会被取到，二维表会塌回一维。
## 所以这里按公司档次实现 —— 若狗牙的本意是按结果，改这一个常量即可。
const BAD_PLAY_CODES: Array[String] = ["A", "B"]


static func play_is_good(company_code: String) -> bool:
	return not BAD_PLAY_CODES.has(company_code)


## 一条作品播出后是什么反应。
##
## `fame_before` = **这一部播出之前**的知名度（不是本周开始时的），
## 因为「无知名度的龙套」是一个**动态**状态：同一周里先靠一部主角戏出了名，
## 后面那个龙套低分就会被观众注意到。按周开始时的知名度判，会把顺序抹掉。
static func evaluate(entry: Dictionary, fame_before: int) -> Dictionary:
	var bal := BalanceLibrary.data()
	var match_rate := float(entry.get("match_rate", 0.0))
	var cast := BalanceData.cast_of_role_tier(int(entry.get("role_tier", 0)))
	var grade := bal.grade_of(match_rate)
	var delta := bal.result_delta(grade)

	var fame := int(delta["fame"]) + bal.fame_for_cast(cast)
	var rep := int(delta["rep"])
	var neg := int(delta["neg"])

	# 数值表 5 明确区分的一件事：**低分龙套不必每次都成为新闻**。
	# 观众都没注意到你是谁，也就没有「个人负面讨论」可言。
	var unnoticed := cast == BalanceData.Cast.EXTRA \
			and grade == BalanceData.Grade.LOW \
			and fame_before < bal.fame_named_threshold
	if unnoticed:
		fame = 0
		rep = 0
		neg = 0

	return {
		"grade": grade,
		"grade_name": BalanceData.grade_name(grade),
		"match_rate": match_rate,
		"cast": cast,
		"unnoticed": unnoticed,
		"fame": fame,
		"rep": rep,
		"neg": neg,
		# 片酬与演技在**投递那一刻**就定了（存进履历），这里只是把它带进周报，
		# 不做二次计算 —— 否则中途改数值表会让旧存档的账目前后不一致
		"payout": int(entry.get("payout", 0)),
		"acting_gain": int(entry.get("acting_gain", 0)),
	}


## 把一串播出结果汇总成周报用的合计
static func total(plays: Array) -> Dictionary:
	var out := {"payout": 0, "acting": 0, "fame": 0, "rep": 0, "neg": 0}
	for p: Dictionary in plays:
		out["payout"] += int(p.get("payout", 0))
		out["acting"] += int(p.get("acting_gain", 0))
		out["fame"] += int(p.get("fame", 0))
		out["rep"] += int(p.get("rep", 0))
		out["neg"] += int(p.get("neg", 0))
	return out
