extends SceneTree
## 部件库验证 —— headless 跑
##
##   godot --headless --path <项目> --script res://tools/test_part_library.gd
##
## 【和 test_data.gd 的分工】
##   test_data.gd 验的是「数据本身对不对」（数量、梯度、判定矩阵）。
##   本测试验的是「界面能不能拿到数据」—— PartLibrary 是场景层唯一的入口，
##   它坏掉的表现是「录像机空白」，而不是断言失败，所以必须单独钉死：
##   顺序、缓存、分组、以及那个最容易漏的「其他 = 留空」。

const EXPECT_SLOT_COUNT := {
	PartData.Slot.EYES: 15,
	PartData.Slot.MOUTH: 14,
	PartData.Slot.BROWS: 14,
	PartData.Slot.EXTRA: 6,
	PartData.Slot.SKIN: 9,
}

const EXPECT_TOTAL := 58

## 按**周次**累计可用件数。三套复杂表情不在这条线上（它们靠翻牌，见 [7]）——
## 第 1 周 49（58 − 认真脸×3 第 2 周 − 爆缸笑脸 / 绿豆蛙 各 3 件第 3 周），
## 第 2 周 52，第 3 周 58。
const EXPECT_UNLOCKED_BY_WEEK := {1: 49, 2: 52, 3: 58}

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	print("")
	print("=== 部件库验证（PartLibrary）===")
	print("")

	PartLibrary.reload()

	print("[1] 全量与分组")
	_check("部件总数", PartLibrary.count(), EXPECT_TOTAL)
	_check("all() 长度", PartLibrary.all().size(), EXPECT_TOTAL)
	for slot: int in PartLibrary.TAB_ORDER:
		var name: String = PartData.SLOT_NAMES[slot]
		var got := PartLibrary.by_slot(slot)
		_check("%s 数量" % name, got.size(), EXPECT_SLOT_COUNT[slot])
		_check_tier_sorted(name, got)
		_check_textures(name, got)
		print("   %s %2d 件：%s" % [
			name, got.size(),
			", ".join(got.map(func(p: PartData) -> String: return p.display_name)),
		])

	print("")
	print("[2] 页签顺序")
	var order := PartLibrary.TAB_ORDER
	_check("页签个数", order.size(), 5)
	_check("第一个页签是眼", order[0], PartData.Slot.EYES)
	_check("第四个页签是其他", order[3], PartData.Slot.EXTRA)
	_check("最后一个页签是肤色", order[4], PartData.Slot.SKIN)
	# all() 必须按页签顺序成段，否则 UI 直接拿 all() 分组会错位
	var all_parts := PartLibrary.all()
	var seen_slots: Array[int] = []
	for p: PartData in all_parts:
		if seen_slots.is_empty() or seen_slots[-1] != p.slot:
			if p.slot in seen_slots:
				_failures.append("all() 里槽位 %s 被拆成了不相邻的多段" % p.slot)
			seen_slots.append(p.slot)
	_check("all() 按页签顺序分成 5 段", seen_slots, PartLibrary.TAB_ORDER)

	print("")
	print("[3] 其他 = 留空（组合数 ×7 的那 1 种）")
	var extra_opts := PartLibrary.slot_options(PartData.Slot.EXTRA)
	_check("其他选项数 = 6 件 + 1 留空", extra_opts.size(), 7)
	_check("首位是留空哨兵 null", extra_opts[0], PartLibrary.EMPTY_EXTRA)
	_check("留空哨兵就是 null", PartLibrary.EMPTY_EXTRA, null)
	var null_count := 0
	for o: Variant in extra_opts:
		if o == null:
			null_count += 1
	_check("留空只出现一次", null_count, 1)
	# 眼/嘴/眉 不该有留空选项 —— 三件必填是 Clip.Frame.is_complete() 的前提
	for slot in [PartData.Slot.EYES, PartData.Slot.MOUTH, PartData.Slot.BROWS]:
		var opts := PartLibrary.slot_options(slot)
		var has_null := false
		for o: Variant in opts:
			if o == null:
				has_null = true
		_check("%s 没有留空选项（必填）" % PartData.SLOT_NAMES[slot], has_null, false)

	print("")
	print("[4] 按 id 取件")
	for id in ["eyes_00", "eyes_07", "mouth_09", "brows_03", "extra_05", "skin_00"]:
		var p := PartLibrary.by_id(id)
		_check("按 id 取到 %s" % id, p != null, true)
		if p != null:
			_check("%s 的 id 回读一致" % id, String(p.id), id)
	_check("取不存在的 id 返回 null", PartLibrary.by_id("eyes_99"), null)

	print("")
	print("[5] 肤色：可选、无留空、默认那件一定在")
	var skin_opts := PartLibrary.slot_options(PartData.Slot.SKIN)
	_check("肤色选项数 = 9（没有留空）", skin_opts.size(), 9)
	var skin_null := 0
	for o: Variant in skin_opts:
		if o == null:
			skin_null += 1
	_check("肤色没有留空选项", skin_null, 0)
	var def := PartLibrary.default_skin()
	_check("默认肤色取得到", def != null, true)
	if def != null:
		_check("default_skin() 返回的就是 DEFAULT_SKIN_ID 那件", String(def.id), PartLibrary.DEFAULT_SKIN_ID)
	# 【纯外观槽】一件都不能带情绪 —— 否则玩家换张脸就悄悄改了判定结果
	for p: PartData in PartLibrary.by_slot(PartData.Slot.SKIN):
		_check("肤色「%s」不参与判定" % p.display_name, p.emotion_labels(), "中性")

	print("")
	print("[6] 缓存（static var 只加载一次）")
	var a1 := PartLibrary.by_id("eyes_04")
	var a2 := PartLibrary.by_id("eyes_04")
	_check("两次取到的是同一个 Resource 实例", a1 == a2, true)
	var arr1 := PartLibrary.all()
	PartLibrary.reload()
	var arr2 := PartLibrary.all()
	# 【注意】不能用「Resource 实例换没换」来验缓存 —— Godot 的 ResourceLoader 自己也
	# 有一层缓存，load() 同一路径永远返回同一个实例。要验 PartLibrary 有没有真的重跑，
	# 只能看 all() 返回的数组对象是不是新的（它每次都是新建的副本）。
	_check("reload() 后重新加载数量不变", PartLibrary.count(), EXPECT_TOTAL)
	_check("reload() 后重建了数组（加载路径确实重跑）", is_same(arr1, arr2), false)
	var a3 := PartLibrary.by_id("eyes_04")
	_check("reload() 后按 id 仍取得到", a3 != null, true)
	if a3 != null:
		_check("reload() 后内容仍然正确", a3.display_name, a1.display_name)

	print("")
	print("[7] 解锁门：10-20 起**没有周次门**，6 套复杂表情全走 `set`")
	for week: int in EXPECT_UNLOCKED_BY_WEEK:
		var n := 0
		for p: PartData in PartLibrary.all():
			if p.is_unlocked_at(week):
				n += 1
		# 以前这里按周数递减（49 / 52 …）；现在 week 门只剩默认值 1，
		# 每周的「按周可用件数」都等于总数 —— 真正锁住的是 set 门（下面两段验）
		_check("第 %d 周按周门放行的件数 = 全部" % week, n, PartLibrary.count())
	_check("eyes_04 第 1 周就有", PartLibrary.by_id("eyes_04").unlock_week, 1)

	# ---- 新手礼包三套：爆缸笑脸 / 恶俗青蛙 / 严肃给力 ----
	# 只在开场引导的「记忆抽取」里翻一次；部件靠 `owned_sets` 放行，不按周。
	_check("新手礼包有三套", ExpressionSets.STARTER_SETS.size(), 3)
	for spec: Dictionary in ExpressionSets.STARTER_SETS:
		var set_id := String(spec["id"])
		_check("%s 被标成新手礼包" % set_id, ExpressionSets.is_starter(set_id), true)
		var parts := ExpressionSets.parts_of(set_id)
		_check("%s 有三件（眼/嘴/眉）" % set_id, parts.size(), 3)
		for id: String in parts:
			var p := PartLibrary.by_id(id)
			_check("%s 的 set_id = %s" % [id, set_id], String(p.set_id), set_id)
			_check("%s 不走周次门" % id, p.unlock_week, 1)
	# 8 基础表情的部件开局就有（恐惧眼 / 愤怒② / 喜悦眉是 10-20 补进来的）
	for id in ["eyes_12", "eyes_13", "brows_12"]:
		_check("%s 第 1 周就能用" % id, PartLibrary.by_id(id).is_unlocked_at(1), true)
	# 每一件都得落在 1..3 里 —— 写成 0 或 4 就等于「永远不给」或「一开始就错锁」
	var bad := 0
	for p: PartData in PartLibrary.all():
		if p.unlock_week < 1 or p.unlock_week > GameState.WEEKS:
			bad += 1
	_check("解锁周次都在 1..%d 内" % GameState.WEEKS, bad, 0)

	# ---- 翻牌门：三套复杂表情 ----
	# 【两边 id 必须一致】部件表的 `set` 与 `ExpressionSets.SETS` 是手写的两份数据，
	# 一旦对不上，翻到「得意」却解开一张别家的脸 —— 所以逐个反查。
	_check("ExpressionSets 有三套", ExpressionSets.SETS.size(), 3)
	for spec: Dictionary in ExpressionSets.SETS:
		var set_id := String(spec["id"])
		var parts := ExpressionSets.parts_of(set_id)
		_check("%s 有三件（眼/嘴/眉）" % set_id, parts.size(), 3)
		var slots := {}
		for id: String in parts:
			var p := PartLibrary.by_id(id)
			if p == null:
				_failures.append("ExpressionSets 里的 %s 在部件库里不存在" % id)
				continue
			_check("%s 的 set_id = %s" % [id, set_id], String(p.set_id), set_id)
			_check("%s 不走周次门" % id, p.unlock_week, 1)
			slots[p.slot] = true
		_check("%s 覆盖了眼/嘴/眉三个槽" % set_id, slots.size(), 3)
	# 反过来：带 set_id 的部件必须都能在 ExpressionSets 里找到归属
	for p: PartData in PartLibrary.all():
		if String(p.set_id).is_empty():
			continue
		_check("%s 的 set 是已知的一套" % p.id, ExpressionSets.has(String(p.set_id)), true)

	# 开局（真·第 1 周：周次门 + 翻牌门都算上）仍然要凑得出「正 / 负」两种效价，
	# 否则 D/E 两关开局无解
	for slot in [PartData.Slot.EYES, PartData.Slot.MOUTH, PartData.Slot.BROWS]:
		var pos := 0
		var neg := 0
		for p: PartData in PartLibrary.by_slot(slot):
			if not p.is_unlocked_at(1) or not String(p.set_id).is_empty():
				continue
			var v := Emotion.valence(p.emotion_vector())
			if v > 0.0:
				pos += 1
			elif v < 0.0:
				neg += 1
		_check("开局的%s仍有正效价件" % PartData.SLOT_NAMES[slot], pos > 0, true)
		_check("开局的%s仍有负效价件" % PartData.SLOT_NAMES[slot], neg > 0, true)

	print("")
	print("共 %d 项断言" % _checks)
	if _failures.is_empty():
		print("✅ 全部通过")
		quit(0)
	else:
		print("❌ %d 项失败：" % _failures.size())
		for f: String in _failures:
			print("   - " + f)
		quit(1)


# ============================================================
func _check(label: String, got: Variant, want: Variant) -> void:
	_checks += 1
	if got != want:
		_failures.append("%s: 期望 %s，实际 %s" % [label, want, got])


## tier 必须从 0 开始、连续、严格递增 —— 梯度是 D/E 两关能不能玩的前提。
func _check_tier_sorted(name: String, parts: Array[PartData]) -> void:
	var expect := 0
	var ok := true
	for p: PartData in parts:
		if p.tier != expect:
			ok = false
			_failures.append("%s 的 tier 不连续：期望 %d，实际 %d（%s）" % [
				name, expect, p.tier, p.display_name])
		expect += 1
	_checks += 1
	if not ok:
		return


func _check_textures(name: String, parts: Array[PartData]) -> void:
	var missing: Array[String] = []
	for p: PartData in parts:
		if p.texture == null:
			missing.append(String(p.id))
	_checks += 1
	if not missing.is_empty():
		_failures.append("%s 有 %d 件没有贴图：%s" % [name, missing.size(), ", ".join(missing)])
