class_name CastingPool
extends Resource
## 定角信息池 —— 邮件里那些【剧名】【角色名】从哪来
##
## 【为什么单独成为一个资源】它们是**内容**不是程序：狗牙要能不改代码就换一批剧名。
## 现在里面装的是占位值（短剧题材按 GDD 的赘婿／战神／重生那一挂），
## 他直接在 `data/casting_pool.tres` 的检查器里替换即可，程序侧一个字都不用动。
##
## 【为什么按档位分角色名】龙套演「保安」「前台」，主角演「沈家二少爷」——
## 混在一个池子里会让龙套戏出现主角名，玩家一眼看出破绽。

@export var player_name: String = ""

@export_group("剧名")
@export var play_titles: Array[String] = []

@export_group("地点")
@export var places: Array[String] = []

@export_group("角色名（按戏份分档）")
@export var role_names_extra: Array[String] = []
@export var role_names_support: Array[String] = []
@export var role_names_lead: Array[String] = []


func role_names_for(tier: int) -> Array[String]:
	match tier:
		RoleRequirement.Tier.SUPPORTING:
			return role_names_support
		RoleRequirement.Tier.LEAD:
			return role_names_lead
	return role_names_extra


## 数据是否够用 —— 缺池子会让邮件填出空字段，宁可在测试里当场炸掉
func missing_buckets() -> Array[String]:
	var out: Array[String] = []
	if player_name.strip_edges().is_empty():
		out.append("player_name")
	if play_titles.is_empty():
		out.append("play_titles")
	if places.is_empty():
		out.append("places")
	if role_names_extra.is_empty():
		out.append("role_names_extra")
	if role_names_support.is_empty():
		out.append("role_names_support")
	if role_names_lead.is_empty():
		out.append("role_names_lead")
	return out
