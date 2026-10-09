class_name RoleRequirement
extends Resource
## 角色档位要求 —— 同一家公司内的三个难度档
##
## 【收益归属】演技收益由**角色难度**决定，钱由**公司档次**决定。互不交叉。

enum Tier { EXTRA, SUPPORTING, LEAD }  ## 龙套 / 配角 / 主角

const TIER_NAMES := {
	Tier.EXTRA: "龙套",
	Tier.SUPPORTING: "配角",
	Tier.LEAD: "主角",
}

@export var tier: Tier = Tier.EXTRA

## 该档位的演技值要求。与公司的演技门槛取「同时满足」（见 AuditionResolver）
@export var acting_required: int = 0

## 匹配线 0~1。文档值：龙套 30% / 配角 50% / 主角 70%
@export_range(0.0, 1.0, 0.01) var match_line: float = 0.30

## 成功后的演技收益。文档值：龙套 +1 / 配角 +2 / 主角 +5
@export var acting_gain: int = 1

## 片酬由「公司档次 × 角色档位」共同决定，数值在数值表里填
@export var payout_ratio: float = 1.0


func tier_name() -> String:
	return TIER_NAMES.get(tier, "?")
