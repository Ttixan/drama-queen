class_name CompanyData
extends Resource
## 影视公司
##
## 【难度层次】层次来自 conditions 里条件的**种类**，不是数字变大：
##     A L0 无要求 / B L1 单情绪 / C L2 情绪纯度 / D L3 情绪曲线 / L4 帧间反转
## 每一档教玩家一个表演概念。
##
## 【线索】隐藏公式下，玩家靠**经纪人邮件**学习偏好。
## hint 字段就是那条线索的文案（"C公司最近在找纯真路线的新人"），
## 条件越复杂，hint 必须越密 —— 这是机制的必需品，不是可选叙事。

enum Tier { A_LOW, B_SMALL, C_COMMERCIAL, D_ARTHOUSE, E_MAJOR }

@export var id: StringName = &""
@export var code: String = ""            ## "A"~"E"，内部代号
@export var display_name: String = ""    ## 虚构公司名（待狗牙补）
@export var tier: Tier = Tier.A_LOW

@export_group("门槛")
## 公司演技门槛。文档值：0 / 3 / 8 / 15 / 25
@export var acting_threshold: int = 0
## 投入本公司的每日行动点消耗
@export var ap_cost: int = 1
## 每周最多可投递次数（全局上限 4，见 GameState.MAX_SUBMIT_PER_WEEK）
@export var weekly_limit: int = 4

@export_group("偏好与条件")
## 试镜条件清单。匹配度 = Σ(命中权重) / Σ(全部权重)
@export var conditions: Array[AuditionCondition] = []
## 角色档位（龙套 / 配角 / 主角）
@export var roles: Array[RoleRequirement] = []

@export_group("经济")
## 该公司**龙套**档的片酬。配角/主角由 RoleRequirement.payout_ratio 乘上去。
##
## 【收益归属】钱由公司档次决定，演技由角色难度决定，互不交叉（决策记录 1.3）。
## 数值表值：A40 / B64 / C80 / D96 / E120；配角 ×2、主角 ×3。
@export var extra_payout: int = 0

@export_group("Boss直聘")
## 一句话定位，取自 md 标题「# A 公司｜流水线烂片小厂」的竖线后半段。
## 公司真名还没定（狗牙在编），所以列表里真正让五家区分开的是这个定位。
@export var tagline: String = ""
@export var industry: String = ""
@export var funding: String = ""
@export var scale: String = ""
## 【只展示一个代表性职位】见 data/companies/README.md —— 玩家不在这里求职，
## 所以职位卡是"公司长什么样"的一部分，不是可投递的岗位。
@export var position_title: String = ""
@export var salary: String = ""
@export var experience: String = ""
## 招聘页标签，渲染成一排小色块
@export var tags: Array[String] = []
## 职位详情正文（原文照搬，含它自带的风格线索）
@export_multiline var posting_text: String = ""
## 正文末尾那条「> 注：」的碎碎念，单独存是为了能排版成注脚而不是正文
@export_multiline var posting_note: String = ""

@export_group("叙事")
## 经纪人线索文案，每周漏一条给玩家
@export_multiline var hint: String = ""
## HR 姓名/职位，用于微信联系人
@export var hr_name: String = ""
@export var hr_title: String = ""


func role_of(tier_wanted: RoleRequirement.Tier) -> RoleRequirement:
	for r: RoleRequirement in roles:
		if r.tier == tier_wanted:
			return r
	return null


## 该公司全部条件的总权重 —— 用于校验匹配度换算
func total_condition_weight() -> float:
	var t := 0.0
	for c: AuditionCondition in conditions:
		t += c.weight
	return t


## 某角色的实际片酬。角色不存在时返回 0。
func payout_for(role: RoleRequirement) -> int:
	if role == null:
		return 0
	return int(round(float(extra_payout) * role.payout_ratio))
