class_name PartData
extends Resource
## 表情部件
##
## 53 张图 → 12(眼) × 14(嘴) × 12(眉) × 7(其他含空) × 9(肤色) = 127008 种脸。
## 拼贴法的全部价值就在这个组合爆炸上，所以部件池小完全没问题。
##
## 【美术约束】每类必须有**强度梯度**（眼：信任→惊讶→愤怒→悲伤忧愁→喜悦…），
## 否则玩家拼不出 3 帧内的情绪变化，多帧机制就废了。tier 字段记录梯度档位。
##
## 【SKIN 为什么排在枚举最后】`.tres` 里存的是枚举的数值（extra = 3）。
## 插在中间会让所有已有资源的 slot 值整体错位 —— 旧档读回来眼睛变嘴。
## 新槽位一律往后追加。

enum Slot { EYES, MOUTH, BROWS, EXTRA, SKIN }

const SLOT_NAMES := {
	Slot.EYES: "眼",
	Slot.MOUTH: "嘴",
	Slot.BROWS: "眉",
	Slot.EXTRA: "其他",
	Slot.SKIN: "肤色",
}

@export var id: StringName = &""
@export var display_name: String = ""
@export var slot: Slot = Slot.EYES

## 梯度档位，同一 slot 内 0 起递增。用于校验「每类有梯度」这条美术约束。
@export var tier: int = 0

@export var texture: Texture2D

## 第几周起可用。**1 = 开局就有**；2 / 3 = 那一周开始时解锁。
##
## 【为什么是周次，不是天数 / 条件】整局只有 3 周，周是玩家唯一认的时间刻度；
## 写在天数上界面还得再换算一次，写成一堆条件（钱 / 演技 / 知名度）则会让
## 「第 2 周能演什么」变成一道隐函数，策划讲故事时说不动。
## 【为什么不进存档】天数在存档里，周次由天数派生 —— 解锁状态跟着一起派生，
## 于是老存档读回来不会缺任何一件（也就没有迁移表）。
@export var unlock_week: int = 1

## 属于哪一套「复杂表情」（`ExpressionSets` 的 id）。空 = 开局就有的普通部件。
##
## 【和 unlock_week 是两条路，别混】带 `set_id` 的部件不看周次，
## 只看玩家有没有通过周结算翻牌拿到那一套（`GameState.owned_sets`）。
## 一套三件（眼/嘴/眉）必须同 id —— 半套可用会拼出画面上打架的脸。
@export var set_id: StringName = &""

## 关键词表里标的展示属性：8 种基础情绪 → 分值（喜悦 40 / 期待 10 …）。
## **只给界面标注用**，不参与判定 —— 判定走下面那 6 个权重，两套体系别混。
@export var attributes: Dictionary = {}

@export_group("情绪权重")
## 每个部件打 1~3 个情绪标签即可，不必每个都填。
@export_range(0.0, 5.0, 0.1) var joy: float = 0.0
@export_range(0.0, 5.0, 0.1) var anger: float = 0.0
@export_range(0.0, 5.0, 0.1) var sorrow: float = 0.0
@export_range(0.0, 5.0, 0.1) var shock: float = 0.0
@export_range(0.0, 5.0, 0.1) var charm: float = 0.0
@export_range(0.0, 5.0, 0.1) var awkward: float = 0.0


## 第 `week` 周这件能不能用。**1 起算**（第 1 周就是开局那周）。
func is_unlocked_at(week: int) -> bool:
	return unlock_week <= week


func emotion_vector() -> PackedFloat32Array:
	var v := Emotion.make_vector()
	v[Emotion.Kind.JOY] = joy
	v[Emotion.Kind.ANGER] = anger
	v[Emotion.Kind.SORROW] = sorrow
	v[Emotion.Kind.SHOCK] = shock
	v[Emotion.Kind.CHARM] = charm
	v[Emotion.Kind.AWKWARD] = awkward
	return v


## 给玩家看的部件标签，如「喜·魅」。一个标签都没打的（平静 / 舒展 / 眼镜…）返回「中性」——
## 直接回空串的话卡片上会留一行空白，看着像漏了图
func emotion_labels() -> String:
	var v := emotion_vector()
	var names: Array[String] = []
	for i in Emotion.COUNT:
		if v[i] > 0.0:
			names.append(Emotion.to_name(i))
	return "中性" if names.is_empty() else "·".join(names)
