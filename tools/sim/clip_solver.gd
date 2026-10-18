class_name ClipSolver
extends RefCounted
## 从 53 件部件里搜出一段「尽量满足给定条件」的 3 帧表情包
##
## 【它是干什么的】数值模拟器里的「贪心玩家」需要一段**真的能过线**的表演。
## 没有它，模拟器只能告诉你「乱拼能过多少」—— 那回答不了任何平衡问题。
##
## 【为什么用真实判定器评分，而不是另写一套打分函数】
## 两套规则一定会漂移：求解器认为「好」的那段剪辑，真判定器可能判它不合格，
## 于是模拟器给你的平衡结论是错的，而你还照着它调数值。
## 这里直接调 `AuditionResolver.evaluate()` —— 求解器求解的就是**真实的匹配度**。
##
## 【为什么能缓存到 static】条件只跟公司有关，与玩家状态无关（演技另算）。
## 所以每家只需解一次，之后所有投递复用 —— 这是模拟器能跑几千局的前提。
##
## 【搜索规模与三步缩小】单帧候选 = 12 眼 × 14 嘴 × 12 眉 × 7 其他(含留空) = 14112。
## 三帧全枚举是 14112³ ≈ 2.8×10¹²，不可能。做法：
##   1. 14112 个候选按「各种用途」各取前几名，**缩成一个与公司无关的通用池**
##      （池子只建一次，五家共用 —— 这是把搜索压到 0.1 秒级的关键）
##   2. 在池子里枚举**有序**三元组（顺序影响「趋势」与「反转」，不能只算组合）
##   3. 用真实条件判定器评分，取最高
##
## 【不允许重复帧吗】允许（i/j/k 独立取值）。「平稳」这类条件要的就是
## 三帧效价接近，重复同一帧是最直接的解法 —— 禁掉反而解不出来。

## 池子上限。当前 11 条取材准则 × 4 帧 = 44 帧 → 85184 个有序三元组，
## 五家公司的理想解合计约 0.6 秒（含建池子）。调大它搜索时间是**立方**增长。
const MAX_POOL := 48
## 每条取材准则贡献几帧
const PER_CRITERION := 4

static var _all: Array[Dictionary] = []
static var _all_built := false
static var _pool: Array[Dictionary] = []
static var _pool_built := false
## signature -> {"clip": Clip, "rate": float, "vetoed": bool}
static var _cache: Dictionary = {}


# ============================================================
# 对外
# ============================================================
## 解出一段满足 `conditions` 的最佳表情包。
##
## 【返回的是副本】缓存里的那一份不能被调用方改坏 ——
## 模拟器会给解出来的剪辑「故意挑错一个部件」，那是在改它。
static func solve(conditions: Array) -> Clip:
	return copy(best(conditions)["clip"])


## 最佳匹配度（0~1）。**这是「这组条件到底能不能过」的答案**。
static func rate(conditions: Array) -> float:
	return float(best(conditions)["rate"])


static func best(conditions: Array) -> Dictionary:
	var sig := signature(conditions)
	if _cache.has(sig):
		return _cache[sig]
	_ensure_pool()

	var best_rate := -1.0
	var best_clip: Clip = null
	var best_vetoed := false
	var clip := FastClip.new()
	# 【满分的早退】满分不可能再被超过。少了它，A 公司那种「随便拼都满分」
	# 的条件也要把 46656 个三元组跑满，而它每局都要被解一次。
	var done := false
	for i: Dictionary in _pool:
		clip.frames[0] = i["frame"]
		for j: Dictionary in _pool:
			clip.frames[1] = j["frame"]
			for k: Dictionary in _pool:
				clip.frames[2] = k["frame"]
				clip.set_vectors(i["v"], j["v"], k["v"])
				var sc := _score(clip, conditions)
				var r: float = sc["rate"]
				if r > best_rate:
					best_rate = r
					best_vetoed = sc["vetoed"]
					best_clip = copy(clip)
					if r >= 1.0:
						done = true
						break
			if done:
				break
		if done:
			break

	var out := {"clip": best_clip, "rate": maxf(best_rate, 0.0), "vetoed": best_vetoed}
	_cache[sig] = out
	return out


## 某家公司的「理想表演」—— 一个读懂了线索、手也不抖的玩家能拼出来的东西
static func solve_for_company(company: CompanyData) -> Clip:
	if company == null:
		return null
	return solve(company.conditions)


static func rate_for_company(company: CompanyData) -> float:
	if company == null:
		return 0.0
	return rate(company.conditions)


## 深拷贝：帧是新的，`PartData` 仍然共享（资源本来就是只读的）
static func copy(clip: Clip) -> Clip:
	if clip == null:
		return null
	var out := Clip.new(clip.frame_count())
	for i in clip.frame_count():
		var f: Clip.Frame = clip.frames[i]
		out.frames[i] = Clip.Frame.new(f.eyes, f.mouth, f.brows, f.extra)
	return out


## 模拟「懂了线索但手潮」：两种失误各以 `chance` 的概率发生
##   1. **挑错部件** —— 每帧把一个随机槽位换成随机一件（零散的失误）
##   2. **排错顺序** —— 交换相邻两帧（L3 曲线形态 / L4 帧间反转 考的**就是顺序**）
##
## 【为什么第二种必须有】第一版只做了「挑错部件」，结果 75% 的手潮仍然 100% 过线 ——
## 因为一帧有 4 个部件，换掉一个通常动不了主导情绪，更动不了三帧的先后关系。
## 而玩家最容易犯、也最该被惩罚的错，其实正是「三帧排反了」。
## 少了第 2 条，这个模型会告诉设计者「失误没有代价」，那是假的。
##
## 【为什么这个模型比「整段重拼」好】真实失误是**零散**的：大方向对，细节错。
## 整段重拼测的是「完全没懂」，那是随机 agent 的职责。
static func make_sloppy(clip: Clip, rng: RandomNumberGenerator, chance: float) -> Clip:
	var out := copy(clip)
	if out == null or chance <= 0.0:
		return out
	for i in out.frame_count():
		if rng.randf() >= chance:
			continue
		var f: Clip.Frame = out.frames[i]
		match rng.randi_range(0, 3):
			0:
				f.eyes = _random_in(PartData.Slot.EYES, rng)
			1:
				f.mouth = _random_in(PartData.Slot.MOUTH, rng)
			2:
				f.brows = _random_in(PartData.Slot.BROWS, rng)
			_:
				var opts := PartLibrary.slot_options(PartData.Slot.EXTRA)
				f.extra = opts[rng.randi_range(0, opts.size() - 1)]

	if out.frame_count() >= 2 and rng.randf() < chance:
		var a := rng.randi_range(0, out.frame_count() - 2)
		var swap: Clip.Frame = out.frames[a]
		out.frames[a] = out.frames[a + 1]
		out.frames[a + 1] = swap
	return out


static func _random_in(slot: int, rng: RandomNumberGenerator) -> PartData:
	var opts := PartLibrary.by_slot(slot)
	if opts.is_empty():
		return null
	return opts[rng.randi_range(0, opts.size() - 1)]


# ============================================================
# 诊断（测试与调参用）
# ============================================================
static func pool_size() -> int:
	_ensure_pool()
	return _pool.size()


static func candidate_count() -> int:
	_build_all()
	return _all.size()


static func cache_size() -> int:
	return _cache.size()


static func clear_cache() -> void:
	_cache.clear()


## 条件清单的指纹 —— 只认**影响判定**的字段
static func signature(conditions: Array) -> String:
	var parts: Array[String] = []
	for c: AuditionCondition in conditions:
		parts.append("%d/%d/%s/%d/%s/%s" % [
			c.type, c.emotion, str(c.value), c.trend, str(c.weight), str(c.required)])
	return "|".join(parts)


# ============================================================
# 搜索用的两个加速件
# ============================================================
## 加速壳：把每帧的向量预先算好，`frame_vector()` 直接查表。
##
## 【为什么这样也算「用真实判定器」】`Clip.mean_vector()` / `valence_track()` /
## `last_vector()` **全都经由 `frame_vector()` 取数**，覆写这一个方法就够 ——
## 判定规则一行没改。而 46k 次搜索里 `frame_vector()` 会被调几十万次，
## 每次都重算 4 个部件的向量和，那是纯粹的重复劳动。
##
## 【它带来的风险与对冲】如果将来 `Clip` 改成不走 `frame_vector()` 取数，
## 这条快路就会和真判定器分叉。`test_clip_solver.gd` 里有一条断言专门钉这个：
## **求解器报的匹配度必须等于真判定器对同一段剪辑的判定**。
class FastClip extends Clip:
	var vectors: Array[PackedFloat32Array] = []

	func _init() -> void:
		super(3)

	func set_vectors(a: PackedFloat32Array, b: PackedFloat32Array, c: PackedFloat32Array) -> void:
		vectors.resize(3)
		vectors[0] = a
		vectors[1] = b
		vectors[2] = c

	func frame_vector(i: int) -> PackedFloat32Array:
		if i < 0 or i >= vectors.size():
			return Emotion.make_vector()
		return vectors[i]


## 廉价评分：只算「Σ命中权重 / Σ总权重」，不造 details。
##
## 【为什么不直接调 AuditionResolver.evaluate()】它会给每个条件造一条带
## Dictionary 的 details 记录。46k 次搜索要造几十万条，而搜索只需要那个数字。
##
## 【为什么这不叫「第二套规则」】命中与否仍然问 `AuditionResolver.check()`，
## 只有最后那次除法在这里重写了一遍 —— 而它被 `test_clip_solver.gd` 钉在
## 真实 `evaluate()` 上。
static func _score(clip: Clip, conditions: Array) -> Dictionary:
	var total := 0.0
	var hit := 0.0
	var vetoed := false
	for c: AuditionCondition in conditions:
		total += c.weight
		if AuditionResolver.check(clip, c):
			hit += c.weight
		elif c.required:
			vetoed = true
	var r := 1.0
	if vetoed:
		r = 0.0
	elif total > 0.0:
		r = hit / total
	return {"rate": r, "vetoed": vetoed}


# ============================================================
# 池子
# ============================================================
static func _ensure_pool() -> void:
	if _pool_built:
		return
	_pool_built = true
	_build_all()

	var picked := {}
	# 六个情绪维各取最高的几帧 —— 覆盖「要有某情绪」
	for e in Emotion.COUNT:
		_take_top(picked, func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["v"][e]) > float(b["v"][e]))
	# 纯度最高 —— 覆盖 C 的「克制的纯粹」
	_take_top(picked, func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["purity"]) > float(b["purity"]))
	# 效价最正 / 最负 —— 覆盖「递增/递减」与「反转」的两端
	_take_top(picked, func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["valence"]) > float(b["valence"]))
	_take_top(picked, func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["valence"]) < float(b["valence"]))
	# 效价最接近 0 —— 覆盖「平稳」与「排除情绪」的中间态
	_take_top(picked, func(a: Dictionary, b: Dictionary) -> bool:
		return absf(a["valence"]) < absf(b["valence"]))
	# 情绪总量最小 —— 覆盖「不要有某情绪」这一类否定条件
	_take_top(picked, func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["total"]) < float(b["total"]))

	for idx: int in picked:
		_pool.append(_all[idx])


static func _take_top(picked: Dictionary, cmp: Callable) -> void:
	# 【为什么真的去卡上限】搜索代价是池子的立方，所以这条上限必须是**硬**的。
	# 将来有人往池子里加第 13 条取材准则时，会在这里被拦下，而不是等模拟器变慢才发现。
	if picked.size() >= MAX_POOL:
		return
	var sorted := _all.duplicate()
	sorted.sort_custom(cmp)
	var added := 0
	for e: Dictionary in sorted:
		if added >= PER_CRITERION or picked.size() >= MAX_POOL:
			return
		var idx: int = e["index"]
		if picked.has(idx):
			continue
		picked[idx] = true
		added += 1


## 展开全部 14112 个单帧候选。**只做一次**，五家公司共用。
static func _build_all() -> void:
	if _all_built:
		return
	_all_built = true
	if PartLibrary.is_empty():
		push_error("[ClipSolver] 部件库是空的 —— 先跑 tools/gen_data.gd")
		return
	var eyes_list := PartLibrary.by_slot(PartData.Slot.EYES)
	var mouth_list := PartLibrary.by_slot(PartData.Slot.MOUTH)
	var brows_list := PartLibrary.by_slot(PartData.Slot.BROWS)
	var extra_list := PartLibrary.slot_options(PartData.Slot.EXTRA)
	for e: PartData in eyes_list:
		for m: PartData in mouth_list:
			for b: PartData in brows_list:
				for x: Variant in extra_list:
					var f := Clip.Frame.new(e, m, b, x as PartData)
					var v := f.emotion_vector()
					_all.append({
						"index": _all.size(),
						"frame": f,
						"v": v,
						"total": Emotion.total(v),
						"purity": Emotion.purity(v),
						"valence": Emotion.valence(v),
					})
