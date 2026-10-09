class_name Clip
extends RefCounted
## 一段表情包 = 3 帧，每帧由 眼/嘴/眉/其他 四个部件拼成（「其他」可为空）
##
## 为什么是多帧：GDD 的公司偏好里，「反转」这个风格**单帧根本表达不出来** ——
## 只有看帧与帧之间的情绪变化才能算。多帧机制让 E 大厂成立。

const DEFAULT_FRAME_COUNT := 3

## 一帧
class Frame extends RefCounted:
	var eyes: PartData
	var mouth: PartData
	var brows: PartData
	var extra: PartData  ## 可为 null

	func _init(p_eyes: PartData = null, p_mouth: PartData = null,
			p_brows: PartData = null, p_extra: PartData = null) -> void:
		eyes = p_eyes
		mouth = p_mouth
		brows = p_brows
		extra = p_extra

	func parts() -> Array[PartData]:
		var out: Array[PartData] = []
		if eyes != null:
			out.append(eyes)
		if mouth != null:
			out.append(mouth)
		if brows != null:
			out.append(brows)
		if extra != null:
			out.append(extra)
		return out

	## 帧情绪向量 = 该帧所选部件向量之和（未归一化）
	func emotion_vector() -> PackedFloat32Array:
		var v := Emotion.make_vector()
		for p: PartData in parts():
			var pv := p.emotion_vector()
			for i in Emotion.COUNT:
				v[i] += pv[i]
		return v

	## 必填部件是否齐全（眼/嘴/眉）
	func is_complete() -> bool:
		return eyes != null and mouth != null and brows != null


var frames: Array = []  ## Array[Frame]


func _init(frame_count: int = DEFAULT_FRAME_COUNT) -> void:
	for i in frame_count:
		frames.append(Frame.new())


func frame_count() -> int:
	return frames.size()


func is_complete() -> bool:
	if frames.is_empty():
		return false
	for f: Frame in frames:
		if not f.is_complete():
			return false
	return true


func frame_vector(i: int) -> PackedFloat32Array:
	if i < 0 or i >= frames.size():
		return Emotion.make_vector()
	return (frames[i] as Frame).emotion_vector()


## 情绪均值向量 —— 代表「整段表演的整体情绪」
func mean_vector() -> PackedFloat32Array:
	var v := Emotion.make_vector()
	if frames.is_empty():
		return v
	for i in frame_count():
		var fv := frame_vector(i)
		for k in Emotion.COUNT:
			v[k] += fv[k]
	for k in Emotion.COUNT:
		v[k] /= float(frame_count())
	return v


## 末帧向量 —— 代表「表演的落点」，多数条件看这个
func last_vector() -> PackedFloat32Array:
	return frame_vector(frame_count() - 1)


## 效价轨迹：每帧一个标量，正值偏「喜/魅」，负值偏「怒/哀/尬」。
## 「纯真」= 全程高正价；「幻灭」= 正价递减转负；「反转」= 首末符号翻转。
func valence_track() -> PackedFloat32Array:
	var t := PackedFloat32Array()
	for i in frame_count():
		t.append(Emotion.valence(frame_vector(i)))
	return t


func frame_purity(i: int) -> float:
	return Emotion.purity(frame_vector(i))


## 给玩家看的帧级情绪标签 —— 隐藏公式下唯一的反馈出口
func frame_label(i: int) -> String:
	return Emotion.dominant_label(frame_vector(i))


func all_labels() -> Array[String]:
	var out: Array[String] = []
	for i in frame_count():
		out.append(frame_label(i))
	return out


## 作品集／履历用的简短描述，如「喜 → 惊 → 哀」
func summarize() -> String:
	return " → ".join(all_labels())
