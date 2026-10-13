class_name Headline
extends Resource
## 一条电子报《有瓜有戏》标题
##
## 【为什么拆成资源而不是一个字符串表】标题里有【公司名】【剧名】【报道对象】【玩家名】
## 四种替换字段，同一句文案在不同玩家身上填出来的东西完全不同。
## 拆成资源之后，狗牙在 `data/news/headlines.md` 里改文案、重跑 `tools/gen_headlines.gd`，
## 程序侧一个字不动。
##
## 【三种分组，对应 md 里的四张表】
##   MAIN    —— 主要角色（配角 / 主角）：同一家公司，夸还是骂取决于结果档
##   EXTRA   —— 龙套：还要再分「好剧中的龙套 / 烂剧中的龙套」，因为同一句夸龙套的话
##              放在烂片厂和放在大厂里读起来不是一回事
##   SPECIAL —— 特殊触发（首次出圈 / 黑红 / 通用备选），不按公司挑，按**事件**挑
##
## 【不在这个文件里做选择】哪一条该被选中是**规则**，在 `scripts/core/headline_composer.gd`；
## 这里只描述「有哪些标题」。

enum Group { MAIN, EXTRA, SPECIAL }

## SPECIAL 的触发种类 —— 字符串而不是枚举，是为了让 md 里的「触发情况」一栏能直接映射，
## 也为了让 `headline_composer.gd` 的调用点读起来像人话（`find_kind(&"black_fame")`）。
const KIND_EXTRA_STAR := &"extra_star"                  ## 龙套首次出圈（找人标题）
const KIND_BLACK_FAME := &"black_fame"                  ## 负面曝光首次跨过门槛
const KIND_BLACK_FAME_REPEAT := &"black_fame_repeat"    ## 黑红之后的重复曝光
const KIND_FALLBACK_D_HIGH := &"fallback_d_high"        ## D 高分但没演过烂剧
const KIND_FALLBACK_D_LOW := &"fallback_d_low"          ## D 低分但不是霸总（本轮未启用）
const KIND_FALLBACK_LOW_BAD := &"fallback_low_bad"      ## 烂剧低分且未细分演法（本轮未启用）
const KIND_FALLBACK_B_LOW := &"fallback_b_low"          ## B 低分且该点名了

@export var id: StringName = &""
@export var group: Group = Group.MAIN

@export_group("MAIN 用")
## 公司代号 A~E。空 = 不限公司
@export var company_code: String = ""

@export_group("MAIN / EXTRA 用")
## 结果档（对齐 BalanceData.Grade）。-1 = 不限
@export var grade: int = -1

@export_group("EXTRA 用")
## 1 = 好剧中的龙套，0 = 烂剧中的龙套。判断口径见 headline_composer.gd
@export var play_good: int = -1

@export_group("SPECIAL 用")
@export var kind: StringName = &""

@export_group("文案")
## 【公司名】【剧名】【报道对象】【玩家名】由 MailComposer.fill() 替换
@export_multiline var text: String = ""


func describe() -> String:
	match group:
		Group.MAIN:
			return "MAIN %s/%s" % [company_code, BalanceData.grade_name(grade)]
		Group.EXTRA:
			return "EXTRA %s/%s" % [BalanceData.grade_name(grade),
					"好剧中" if play_good == 1 else "烂剧中"]
	return "SPECIAL " + String(kind)
