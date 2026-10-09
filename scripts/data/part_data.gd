class_name PartData
extends Resource
## 表情部件
##
## 32 张图 → 8(眼) × 10(嘴) × 8(眉) × 7(其他含空) = 4480 种脸。
## 拼贴法的全部价值就在这个组合爆炸上，所以部件池小完全没问题。
##
## 【美术约束】每类必须有**强度梯度**（眼：平静→睁大→瞪→含泪→眯笑），
## 否则玩家拼不出 3 帧内的情绪变化，多帧机制就废了。tier 字段记录梯度档位。

enum Slot { EYES, MOUTH, BROWS, EXTRA }

const SLOT_NAMES := {
	Slot.EYES: "眼",
	Slot.MOUTH: "嘴",
	Slot.BROWS: "眉",
	Slot.EXTRA: "其他",
}

@export var id: StringName = &""
@export var display_name: String = ""
@export var slot: Slot = Slot.EYES

## 梯度档位，同一 slot 内 0 起递增。用于校验「每类有梯度」这条美术约束。
@export var tier: int = 0

@export var texture: Texture2D

@export_group("情绪权重")
## 每个部件打 1~3 个情绪标签即可，不必每个都填。
@export_range(0.0, 5.0, 0.1) var joy: float = 0.0
@export_range(0.0, 5.0, 0.1) var anger: float = 0.0
@export_range(0.0, 5.0, 0.1) var sorrow: float = 0.0
@export_range(0.0, 5.0, 0.1) var shock: float = 0.0
@export_range(0.0, 5.0, 0.1) var charm: float = 0.0
@export_range(0.0, 5.0, 0.1) var awkward: float = 0.0


func emotion_vector() -> PackedFloat32Array:
	var v := Emotion.make_vector()
	v[Emotion.Kind.JOY] = joy
	v[Emotion.Kind.ANGER] = anger
	v[Emotion.Kind.SORROW] = sorrow
	v[Emotion.Kind.SHOCK] = shock
	v[Emotion.Kind.CHARM] = charm
	v[Emotion.Kind.AWKWARD] = awkward
	return v


## 给玩家看的部件标签，如「喜·魅」
func emotion_labels() -> String:
	var v := emotion_vector()
	var names: Array[String] = []
	for i in Emotion.COUNT:
		if v[i] > 0.0:
			names.append(Emotion.to_name(i))
	return "·".join(names)
