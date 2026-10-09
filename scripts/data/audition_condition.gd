class_name AuditionCondition
extends Resource
## 试镜条件
##
## 【核心设计】判定不用加权公式，用「布尔条件 + 权重」：
##     匹配度 = Σ(命中的条件权重) / Σ(全部条件权重)
## 全部条件是布尔判断，好写、好测、好平衡；算出的百分比直接对接
## 龙套 30% / 配角 50% / 主角 70% 三条匹配线。
##
## 【难度层次】层次来自条件在「质」上的不同，不是同一个数字变大：
##     L0 A 烂片厂  → 最低条件（无冲突情绪）
##     L1 B 小公司  → 单情绪命中
##     L2 C 商业片  → 情绪纯度（排除冲突）
##     L3 D 文艺片  → 情绪曲线形态（递减／递增／平稳）
##     L4 E 大厂    → 帧间反转
## 每一档教玩家一个表演概念，这才是玩家感受到的上升感。

enum Type {
	MIN_FRAMES,          ## 录满 N 帧
	HAS_EMOTION,         ## 任一帧该情绪 >= value
	NO_EMOTION,          ## 所有帧该情绪 <= value
	DOMINANT_EMOTION,    ## 平均情绪向量的主导情绪 == emotion
	PURITY_MIN,          ## 整体情绪纯度 >= value（看平均向量，不看单帧）
	LAST_FRAME_EMOTION,  ## 末帧主导情绪 == emotion
	VALENCE_TREND,       ## 效价曲线趋势 == trend
	VALENCE_REVERSAL,    ## 首末帧效价符号翻转
}

enum Trend { DECREASING, INCREASING, STABLE }

const TYPE_NAMES := {
	Type.MIN_FRAMES: "录满帧数",
	Type.HAS_EMOTION: "出现情绪",
	Type.NO_EMOTION: "排除情绪",
	Type.DOMINANT_EMOTION: "主导情绪",
	Type.PURITY_MIN: "情绪纯度",
	Type.LAST_FRAME_EMOTION: "末帧情绪",
	Type.VALENCE_TREND: "效价趋势",
	Type.VALENCE_REVERSAL: "帧间反转",
}

@export var type: Type = Type.MIN_FRAMES

## 仅 HAS_EMOTION / NO_EMOTION / DOMINANT_EMOTION / LAST_FRAME_EMOTION 使用
@export var emotion: Emotion.Kind = Emotion.Kind.JOY

## 阈值。MIN_FRAMES 用整数帧数；HAS/NO_EMOTION 用情绪阈值；PURITY_MIN 用 0~1；STABLE 用允许波动
@export var value: float = 0.0

## 仅 VALENCE_TREND 使用
@export var trend: Trend = Trend.DECREASING

## 命中时贡献的权重。默认 1.0；重要条件给 2.0
@export var weight: float = 1.0

## 关键条件：失败则匹配度**直接归零**（一票否决）。
##
## 【为什么需要】只有加权求和的话，关键条件失手仍能靠加分条件捞回 25%~50% 的分，
## 于是「平坦表达」在 E 大厂能拿 50%、「突然反转」在 D 文艺片能拿 33% ——
## 层次就漏了。给每家公司**唯一一个**定义性条件打上 required，难度才真正分层：
##     E 大厂要的就是反转，不会反转就是不行 → 0%
@export var required: bool = false

@export_multiline var description: String = ""


func describe() -> String:
	if description != "":
		return description
	match type:
		Type.MIN_FRAMES:
			return "录满 %d 帧" % int(value)
		Type.HAS_EMOTION:
			return "出现「%s」(≥%.1f)" % [Emotion.to_name(emotion), value]
		Type.NO_EMOTION:
			return "全程无「%s」(≤%.1f)" % [Emotion.to_name(emotion), value]
		Type.DOMINANT_EMOTION:
			return "主导情绪为「%s」" % Emotion.to_name(emotion)
		Type.PURITY_MIN:
			return "情绪纯度 ≥ %.0f%%" % (value * 100.0)
		Type.LAST_FRAME_EMOTION:
			return "末帧为「%s」" % Emotion.to_name(emotion)
		Type.VALENCE_TREND:
			return "情绪曲线%s" % ["递减", "递增", "平稳"][trend]
		Type.VALENCE_REVERSAL:
			return "帧间发生情绪反转"
	return "?"
