class_name PartData
extends Resource
## 表情部件
##
## 42 张图 → 8(眼) × 11(嘴) × 8(眉) × 7(其他含空) × 9(肤色) = 44352 种脸。
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


## 给玩家看的部件标签，如「喜·魅」。一个标签都没打的（平静 / 舒展 / 眼镜…）返回「中性」——
## 直接回空串的话卡片上会留一行空白，看着像漏了图
func emotion_labels() -> String:
	var v := emotion_vector()
	var names: Array[String] = []
	for i in Emotion.COUNT:
		if v[i] > 0.0:
			names.append(Emotion.to_name(i))
	return "中性" if names.is_empty() else "·".join(names)
