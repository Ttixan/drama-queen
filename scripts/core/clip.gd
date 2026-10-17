class_name Clip
extends RefCounted
## 一段表情包 = 若干帧，每帧由 眼/嘴/眉/其他 四个部件拼成（「其他」可为空）
##
## 为什么是多帧：GDD 的公司偏好里，「反转」这个风格**单帧根本表达不出来** ——
## 只有看帧与帧之间的情绪变化才能算。多帧机制让 E 大厂成立。
##
## 【帧数为什么是可变的】不同公司对「录满几帧」的要求不一样（`MIN_FRAMES` 那一档），
## 而一条片子演 2 帧还是 4 帧，是玩家自己的表演选择 —— 所以帧数由录像机那边增删，
## 这里只负责「几帧都装得下」：均值、末帧、效价轨迹全都按 `frame_count()` 走，没有写死 3。

const DEFAULT_FRAME_COUNT := 3
## 兜底帧数区间。上限的理由是界面（底部帧槽按 1..5 排得开），不是数据 ——
## 数据层留 1 帧是允许的：判定里没有任何一条要求「至少 2 帧」。
const MIN_FRAME_COUNT := 1
const MAX_FRAME_COUNT := 5

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


## 末尾补一帧空的，返回它的下标。**满了就不加**（返回 -1）——
## 上限放在数据层而不是只放界面，是因为界面可能不止一处会调它。
func add_frame() -> int:
	if frames.size() >= MAX_FRAME_COUNT:
		return -1
	frames.append(Frame.new())
	return frames.size() - 1


## 删掉第 i 帧。留一帧兜底：空 Clip 在判定层是「什么都没演」，
## 而界面那边一帧都没有时连「当前帧」都没得指，不如干脆不让它发生。
func remove_frame(i: int) -> bool:
	if frames.size() <= MIN_FRAME_COUNT:
		return false
	if i < 0 or i >= frames.size():
		return false
	frames.remove_at(i)
	return true


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


# ============================================================
# 存档
# ============================================================
## 【为什么它需要能进存档】拼好的表情包现在是**待投递的道具**，存在 `GameState` 里
## （录像机与微信是两个各自整屏的 App，切过去时微信会被销毁）。
## 状态里躺着一个不进存档的字段，读档回来就会静默地少一样东西 —— 所以它得能序列化。
##
## 存的是**部件 id**，不是资源本身：`PartData` 是 `.tres`，JSON 存不下；
## 而 id 是稳定键（美术换图不改 id），读回来由 `PartLibrary` 还原。
func save_dict() -> Dictionary:
	var out: Array = []
	for f: Frame in frames:
		out.append({
			"eyes": _part_id(f.eyes),
			"mouth": _part_id(f.mouth),
			"brows": _part_id(f.brows),
			"extra": _part_id(f.extra),
		})
	return {"frames": out}


## 从存档还原。**认不出来的一律返回 null**（空帧数组、坏了的结构）——
## 调用方把 null 当成「没有待投递的表情包」，界面因此只会少一个附件，不会崩。
static func from_save_dict(d: Dictionary) -> Clip:
	var raw: Variant = d.get("frames", null)
	if typeof(raw) != TYPE_ARRAY or (raw as Array).is_empty():
		return null
	var c := Clip.new((raw as Array).size())
	for i in c.frame_count():
		var fd: Variant = (raw as Array)[i]
		if typeof(fd) != TYPE_DICTIONARY:
			return null
		var parts: Dictionary = fd
		c.frames[i] = Frame.new(
				PartLibrary.by_id(String(parts.get("eyes", ""))),
				PartLibrary.by_id(String(parts.get("mouth", ""))),
				PartLibrary.by_id(String(parts.get("brows", ""))),
				PartLibrary.by_id(String(parts.get("extra", ""))))
	return c


## 「其他」可以留空 —— 空槽存成空串
static func _part_id(p: PartData) -> String:
	return "" if p == null else String(p.id)
