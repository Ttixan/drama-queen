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
	PartData.Slot.EYES: 8,
	PartData.Slot.MOUTH: 10,
	PartData.Slot.BROWS: 8,
	PartData.Slot.EXTRA: 6,
}

const EXPECT_TOTAL := 32

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
	_check("页签个数", order.size(), 4)
	_check("第一个页签是眼", order[0], PartData.Slot.EYES)
	_check("最后一个页签是其他", order[3], PartData.Slot.EXTRA)
	# all() 必须按页签顺序成段，否则 UI 直接拿 all() 分组会错位
	var all_parts := PartLibrary.all()
	var seen_slots: Array[int] = []
	for p: PartData in all_parts:
		if seen_slots.is_empty() or seen_slots[-1] != p.slot:
			if p.slot in seen_slots:
				_failures.append("all() 里槽位 %s 被拆成了不相邻的多段" % p.slot)
			seen_slots.append(p.slot)
	_check("all() 按页签顺序分成 4 段", seen_slots, PartLibrary.TAB_ORDER)

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
	for id in ["eyes_00", "eyes_07", "mouth_09", "brows_03", "extra_05"]:
		var p := PartLibrary.by_id(id)
		_check("按 id 取到 %s" % id, p != null, true)
		if p != null:
			_check("%s 的 id 回读一致" % id, String(p.id), id)
	_check("取不存在的 id 返回 null", PartLibrary.by_id("eyes_99"), null)

	print("")
	print("[5] 缓存（static var 只加载一次）")
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
