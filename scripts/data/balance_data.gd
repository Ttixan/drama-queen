class_name BalanceData
extends Resource
## 数值表（`docs/数值表_v1.xlsx`）的**运行时镜像** —— 所有「可调数值」的唯一来源
##
## 【为什么要有这个文件】在此之前数值表只是两份 md 里的一句「见数值表」，
## 房租、PS5 分期、播出反馈的增量全都没有落到代码里。写死进 `Economy` / `Broadcast`
## 之后，提提要平衡就只能改代码、再重跑测试。放进 `.tres` 就能在检查器里直接调，
## 而 `tools/test_economy.gd` 会断言「这里的值 == 数值表里写的值」——
## 谁偷偷改了一个数，测试当场炸，而不是等三周后发现经济崩了。
##
## 【什么不在这里】三类数值刻意留在别处，**不要在这里重复定义**：
##   · 骨架：3 周 / 7 天 / 1 行动点每天 / 每周投递上限 4 —— 在 `GameState` 的常量里。
##     它们定义的是「21 天」这个骨架本身，改动会同时牵动判定、界面与结局，
##     不是能在检查器里随手拖的东西。
##   · 公司相关：片酬基数、演技门槛、角色档位要求 —— 在 `data/companies/*.tres`
##   · 部件相关：情绪权重 —— 在 `data/parts/*.tres`
##
## 【为什么钱是 int】金钱可以欠成负数（见「被解雇」结局），但不需要小数。
## 片酬矩阵 40 / 64 / 80 / 96 / 120 与租金 80、PS5 分期 135 全是整数，
## 用 int 能避免「−0.0000001 元」这种读起来像 bug 的显示。

## 播出反馈的档位。数值越大越好，用 int 是为了能直接当数组下标。
enum Grade { LOW, NORMAL, HIGH }

const GRADE_NAMES := {
	Grade.LOW: "低分",
	Grade.NORMAL: "普通",
	Grade.HIGH: "高分",
}

## 戏份档位（与 RoleRequirement.Tier 对齐，但这里不 import 那个类 ——
## 数据资源不该依赖另一个数据资源的常量，否则改一处会连锁）。
enum Cast { EXTRA, SUPPORTING, LEAD }


@export_group("起始")
## 初始金钱。数值表：200 —— 要够撑过前 1~2 周，否则开局第一天就被迫打工
@export var init_money: int = 200
@export var init_acting: int = 0
## 演技上限。数值表：30 —— 影后只要 25，留 5 点冗余，不会顶到天花板
@export var acting_cap: int = 30

@export_group("取值范围")
## 知名度 0~100、风评 −50~+50（数值表 5）。
## 【为什么要夹】这三项会被反复加减（低分 −2、逾期 −5），不夹的话
## 一个三周全在挨骂的玩家能把风评刷到 −80，界面上的进度条就没法画了。
@export var fame_max: int = 100
@export var rep_min: int = -50
@export var rep_max: int = 50


@export_group("经济 · 固定支出")
## 房租 / 周。**扣成负数也算欠**，这就是「欠债 = 金钱 < 0」的来源
@export var rent_per_week: int = 80


@export_group("经济 · 打工")
@export var work_income: int = 30
@export var work_max_per_week: int = 2


@export_group("经济 · 表演课")
@export var class_price: int = 100
@export var class_gain: int = 3
@export var class_max_per_week: int = 1


@export_group("经济 · PS5 分期")
## 整个游戏的核心目标。★405 = 135 × 3（原文档填 400 与分期对不上，已校正）
@export var ps5_total: int = 405
@export var ps5_installments: int = 3
@export var ps5_amount_per: int = 135
## 到截止日付不出当期时扣的风评。数值表：风评 −5
@export var ps5_overdue_rep_penalty: int = 5


@export_group("播出反馈 · 分档线")
## 匹配度 ≥ 0.70 → 高分；≥ 0.40 → 普通；否则低分。
## 【为什么用同一份匹配度】「能不能过」和「播出后是夸是骂」是同一件事的两面
## —— 匹配线（龙套 30% / 配角 50% / 主角 70%）在角色资源里，这里是播出口径。
@export var grade_high_line: float = 0.70
@export var grade_normal_line: float = 0.40


@export_group("播出反馈 · 结果档增量（知名度 / 风评 / 负面曝光）")
@export var high_fame: int = 2
@export var high_rep: int = 2
@export var high_neg: int = 0
@export var normal_fame: int = 1
@export var normal_rep: int = 0
@export var normal_neg: int = 0
## 低分**也涨知名度** —— 「负面新闻出现后，不应把更多人认识你等同于口碑变好」
@export var low_fame: int = 1
@export var low_rep: int = -2
@export var low_neg: int = 1


@export_group("播出反馈 · 戏份档知名度增量")
## 知名度是**两个来源相加**：结果档（上）+ 戏份档（这里）。
## 一次「主角 + 高分」= 3 + 2 = 5。数值表原先没写清楚，已补。
@export var fame_per_extra: int = 1
@export var fame_per_supporting: int = 2
@export var fame_per_lead: int = 3


@export_group("播出反馈 · 点名与黑红")
## 知名度到这个门槛，电子报才直呼玩家名；不到就写「男主 / 演保安的那位」
@export var fame_named_threshold: int = 20
## 负面曝光累计到这个门槛，微博出现一条「黑红」标题（**不是成就系统**）
@export var black_fame_threshold: int = 5


# ============================================================
# 查表
# ============================================================
## 匹配度 → 档位。判定与界面共用，避免两边各写一套阈值。
func grade_of(match_rate: float) -> Grade:
	if match_rate >= grade_high_line:
		return Grade.HIGH
	if match_rate >= grade_normal_line:
		return Grade.NORMAL
	return Grade.LOW


static func grade_name(grade: int) -> String:
	return GRADE_NAMES.get(grade, "?")


## 结果档 → {fame, rep, neg}
func result_delta(grade: int) -> Dictionary:
	match grade:
		Grade.HIGH:
			return {"fame": high_fame, "rep": high_rep, "neg": high_neg}
		Grade.NORMAL:
			return {"fame": normal_fame, "rep": normal_rep, "neg": normal_neg}
	return {"fame": low_fame, "rep": low_rep, "neg": low_neg}


## 戏份档 → 知名度增量
func fame_for_cast(cast: int) -> int:
	match cast:
		Cast.LEAD:
			return fame_per_lead
		Cast.SUPPORTING:
			return fame_per_supporting
	return fame_per_extra


## 角色档位（RoleRequirement.Tier）→ 戏份档（Cast）。
## 【为什么要转换】`RoleRequirement` 是数据资源，`BalanceData` 不该 import 它的枚举；
## 转换只在这一个地方做，两边枚举值当前一一对应（0/1/2）。
static func cast_of_role_tier(role_tier: int) -> int:
	return clampi(role_tier, Cast.EXTRA, Cast.LEAD)


# ============================================================
# 自检
# ============================================================
## 数值表内部是否自相矛盾。测试与启动时会调用；
## 返回非空 = 有硬伤（分期加不出总额、门槛倒挂这类），必须在平衡调参前修掉。
func validate() -> Array[String]:
	var out: Array[String] = []
	if ps5_amount_per * ps5_installments != ps5_total:
		out.append("PS5：%d × %d ≠ %d（数值表原填 400 就是因为这里对不上才被改成 405）"
				% [ps5_amount_per, ps5_installments, ps5_total])
	if ps5_installments != GameState.WEEKS:
		out.append("PS5 分期数 %d ≠ 游戏周数 %d —— 每期截止日按「每周最后一天」算，两者必须一致"
				% [ps5_installments, GameState.WEEKS])
	if grade_normal_line >= grade_high_line:
		out.append("播出反馈分档线倒挂：普通线 %.2f 不低于 高分线 %.2f"
				% [grade_normal_line, grade_high_line])
	if class_gain <= 0:
		out.append("表演课收益必须为正，否则上课毫无意义")
	if rent_per_week < 0 or work_income < 0 or class_price < 0:
		out.append("经济数值不该出现负数（欠债是「金钱余额」的属性，不是价格）")
	if acting_cap < 25:
		out.append("演技上限 %d 挡住了「影后」需要的 25" % acting_cap)
	if fame_max <= 0 or rep_min >= rep_max:
		out.append("取值范围不合法：知名度上限 %d，风评 %d~%d" % [fame_max, rep_min, rep_max])
	if fame_named_threshold > fame_max:
		out.append("点名门槛 %d 高于知名度上限 %d —— 电子报永远不会直呼玩家名"
				% [fame_named_threshold, fame_max])
	return out
