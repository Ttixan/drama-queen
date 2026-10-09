class_name Emotion
extends RefCounted
## 情绪维度定义（GDD 3.1）
##
## 【重要】这是**部件**使用的情绪词，与**公司偏好**的风格词不是同一套。
## 公司偏好里的「纯真 / 幻灭 / 反转」是风格而非情绪，需要靠 valence 曲线与
## 条件组合表达，不能直接与情绪词比对。见 AuditionCondition。

enum Kind { JOY, ANGER, SORROW, SHOCK, CHARM, AWKWARD }

const COUNT := 6

const NAMES := {
	Kind.JOY: "喜",
	Kind.ANGER: "怒",
	Kind.SORROW: "哀",
	Kind.SHOCK: "惊",
	Kind.CHARM: "魅",
	Kind.AWKWARD: "尬",
}

## 正向情绪 —— 参与 valence 计算
const POSITIVE: Array[int] = [Kind.JOY, Kind.CHARM]
## 负向情绪 —— 参与 valence 计算
const NEGATIVE: Array[int] = [Kind.ANGER, Kind.SORROW, Kind.AWKWARD]

static func to_name(k: int) -> String:
	return NAMES.get(k, "?")


## 空白帧/全零向量的显示标签。PPT 的情绪标签里出现过「平静」，沿用。
const NEUTRAL_LABEL := "平静"

static func make_vector() -> PackedFloat32Array:
	var v := PackedFloat32Array()
	v.resize(COUNT)
	return v


static func total(v: PackedFloat32Array) -> float:
	var t := 0.0
	for x: float in v:
		t += x
	return t


## 是否为空向量（该帧没有任何情绪部件）
static func is_empty(v: PackedFloat32Array) -> bool:
	return total(v) <= 0.0


## 情绪效价：正向情绪之和 − 负向情绪之和。
## 「纯真」= 全程高正价；「幻灭」= 正价递减转负；「反转」= 首末符号翻转。
static func valence(v: PackedFloat32Array) -> float:
	var pos := 0.0
	for k: int in POSITIVE:
		pos += v[k]
	var neg := 0.0
	for k: int in NEGATIVE:
		neg += v[k]
	return pos - neg


## 主导情绪的下标。全零时返回 JOY。
static func dominant(v: PackedFloat32Array) -> int:
	var best := 0
	for i in range(1, COUNT):
		if v[i] > v[best]:
			best = i
	return best


## 主导情绪的纯度 = 最大值 / 总和。用于「情绪纯度」类条件（C 公司）。
static func purity(v: PackedFloat32Array) -> float:
	var total := 0.0
	for x: float in v:
		total += x
	if total <= 0.0:
		return 0.0
	return v[dominant(v)] / total


## 归一化（不改变原向量）。总和为 0 时返回全零。
static func normalized(v: PackedFloat32Array) -> PackedFloat32Array:
	var total := 0.0
	for x: float in v:
		total += x
	var out := make_vector()
	if total <= 0.0:
		return out
	for i in COUNT:
		out[i] = v[i] / total
	return out


## 给玩家看的帧级情绪标签（隐藏公式下的唯一反馈出口）
##
## 【重要】空帧必须显示「平静」而不是「喜」——
## dominant() 在全零向量上默认返回 JOY，若不特判，
## 「喜→平→哀」会显示成「喜→喜→哀」，玩家看到的反馈是错的。
static func dominant_label(v: PackedFloat32Array) -> String:
	if is_empty(v):
		return NEUTRAL_LABEL
	return to_name(dominant(v))
