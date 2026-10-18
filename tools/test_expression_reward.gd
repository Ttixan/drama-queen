extends SceneTree
## 周结算翻牌奖励验证 —— headless 跑
##
##   godot --headless --path <项目> --script res://tools/test_expression_reward.gd
##
## 【它守的三件事】
##   1. **发牌规则**：龙套 / 配角 / 主角各发一次，发过不再发；牌面不重复；同种子同结果；
##      **试镜当天不发，按下「下一天」才发**。
##   2. **翻牌界面**：三张牌背、悬停描边、点哪张翻哪张、翻完才出现「获得表情」、
##      不点「收下」不算到手。
##   3. **落地**：收下的那套真的把 9 件部件在录像机里解禁（`Game.is_part_unlocked`）。
##
## 【为什么规则和界面分开测】规则在 `GameState`（纯 RefCounted，模拟器也跑它），
## 界面在 `expression_reward.gd`。两者混在一起测，将来改动画时长就会连带
## 「翻到哪一套」的断言一起红 —— 而它们没有关系。

const SCENE := "res://scenes/main/expression_reward.tscn"

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	print("")
	print("=== 翻牌奖励验证（下一天发放）===")
	print("")
	# `--script` 的主脚本编译早于 autoload 注册 → 不能直接写 `Game` / `EventBus` 这两个名字
	var game: Node = root.get_node_or_null("Game")
	if game == null:
		print("❌ Game autoload 没起来")
		quit(1)
		return
	_run_all(game)


func _run_all(game: Node) -> void:
	_test_sets()
	_test_queue()
	_test_deterministic()
	_test_advance_hook(game)
	_test_save_roundtrip()
	_test_unlock_gate(game)
	await _test_ui(game)

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
# 1. 数据：三套牌与部件表必须对得上
# ============================================================
func _test_sets() -> void:
	print("[1] 三套牌 ↔ 九件部件")
	_check("牌面数 = 3", ExpressionSets.SETS.size(), 3)
	_check("牌背图存在", ResourceLoader.exists(ExpressionSets.BACK_FRAME), true)
	var all_parts := 0
	var seen := {}
	for spec: Dictionary in ExpressionSets.SETS:
		var id := String(spec["id"])
		var parts := ExpressionSets.parts_of(id)
		_check("%s 有三件" % id, parts.size(), 3)
		_check("%s 有正面图" % id, ResourceLoader.exists(ExpressionSets.frame_of(id)), true)
		_check("%s 有名字" % id, ExpressionSets.name_of(id).is_empty(), false)
		var slots := {}
		for pid: String in parts:
			all_parts += 1
			var p := PartLibrary.by_id(pid)
			_check("%s 存在" % pid, p != null, true)
			if p == null:
				continue
			_check("%s 的 set_id = %s" % [pid, id], String(p.set_id), id)
			_check("%s 不走周次门" % pid, p.unlock_week, 1)
			slots[p.slot] = true
			seen[pid] = true
		_check("%s 覆盖眼/嘴/眉" % id, slots.size(), 3)
	_check("九件互不重复", all_parts, seen.size())
	_check("部件表里没有多余的 set", _count_set_parts(), 9)


func _count_set_parts() -> int:
	var n := 0
	for p: PartData in PartLibrary.all():
		if not String(p.set_id).is_empty():
			n += 1
	return n


# ============================================================
# 2. 发牌规则
# ============================================================
func _test_queue() -> void:
	print("[2] 每个档位首次成功发一张，发过不再发")
	var s := GameState.new()
	s.event_seed = 20251018
	_check("没演成过 → 没有牌", s.queue_expression_rewards(1).size(), 0)
	_check("状态里也没有待翻的牌", s.pending_flip_count(), 0)

	_play(s, 3, "A", RoleRequirement.Tier.EXTRA, 0.9)
	var first := s.queue_expression_rewards(1)
	_check("龙套首次成功 → 一张", first.size(), 1)
	_check("牌上是龙套档", int(first[0]["tier"]), RoleRequirement.Tier.EXTRA)
	_check("这一套是已知的", ExpressionSets.has(String(first[0]["set"])), true)
	_check("待翻 = 1", s.pending_flip_count(), 1)

	_check("这一档发过了，再跑一次不再发", s.queue_expression_rewards(1).size(), 0)
	_play(s, 4, "B", RoleRequirement.Tier.EXTRA, 0.9)
	_check("龙套演成第二次也不再发", s.queue_expression_rewards(2).size(), 0)

	_play(s, 10, "C", RoleRequirement.Tier.SUPPORTING, 0.9)
	_play(s, 11, "D", RoleRequirement.Tier.LEAD, 0.9)
	var more := s.queue_expression_rewards(2)
	_check("配角 + 主角各一张", more.size(), 2)
	_check("待翻 = 3", s.pending_flip_count(), 3)

	var sets := {}
	for f: Dictionary in s.pending_flips:
		sets[String(f["set"])] = true
	_check("三张牌是三套不同的脸", sets.size(), 3)
	_check("三套全发完了", s.rewarded_tiers.size(), 3)
	print("   三档 → 三张牌，牌面不重复；重复成功不重复发")


# ============================================================
# 3. 可复现：同种子同结果
# ============================================================
func _test_deterministic() -> void:
	print("[3] 同一份状态结算两次，翻到同一张脸")
	var a := GameState.new()
	var b := GameState.new()
	for s: GameState in [a, b]:
		s.event_seed = 777
		_play(s, 3, "A", RoleRequirement.Tier.EXTRA, 0.9)
		_play(s, 4, "A", RoleRequirement.Tier.SUPPORTING, 0.9)
	var ra := a.queue_expression_rewards(1)
	var rb := b.queue_expression_rewards(1)
	_check("两次发牌数量相同", ra.size(), rb.size())
	var same := true
	for i in ra.size():
		if String(ra[i]["set"]) != String(rb[i]["set"]):
			same = false
	_check("牌面顺序与内容完全一致", same, true)

	# 换种子必须可能换脸 —— 否则「随机」是假的
	var found_diff := false
	for seed_value in [1, 2, 3, 4, 5, 6, 7, 8]:
		var c := GameState.new()
		c.event_seed = seed_value
		_play(c, 3, "A", RoleRequirement.Tier.EXTRA, 0.9)
		var r := c.queue_expression_rewards(1)
		if not r.is_empty() and String(r[0]["set"]) != String(ra[0]["set"]):
			found_diff = true
	_check("换种子能换到别的脸（8 个种子）", found_diff, true)


# ============================================================
# 4. 发牌时机：试镜当天不发，按下「下一天」才发
# ============================================================
func _test_advance_hook(game: Node) -> void:
	print("[4] 「下一天」才发牌（不是试镜成功那一刻，也不是周末结算）")
	game.state = GameState.new()
	game.state.day = 3
	game.state.event_seed = 4242
	_play(game.state, 3, "A", RoleRequirement.Tier.EXTRA, 0.9)
	_check("试镜成功当天还没有牌", game.state.pending_flip_count(), 0)

	game.end_day()
	_check("按下「下一天」→ 排了一张", game.state.pending_flip_count(), 1)
	_check("这次推进没有跨周", game.state.day, 4)
	game.end_day()
	_check("再按一天不会多排", game.state.pending_flip_count(), 1)

	# 演砸了不算「首次成功」
	var lose := GameState.new()
	lose.event_seed = 4242
	_play(lose, 3, "A", RoleRequirement.Tier.EXTRA, 0.0, false)
	lose.queue_expression_rewards(1)
	_check("演砸了不发牌", lose.pending_flip_count(), 0)

	# 回归：曾经挂在周结算里 —— 现在结算一颗牌都不该发
	var s := GameState.new()
	s.money = 1000
	s.event_seed = 4242
	s.day = 3
	_play(s, 3, "A", RoleRequirement.Tier.EXTRA, 0.9)
	WeekCycle.settle(s, 1)
	_check("周末结算不发牌", s.pending_flip_count(), 0)


# ============================================================
# 5. 存档往返
# ============================================================
func _test_save_roundtrip() -> void:
	print("[5] 存档：拿到的套 / 发过的档 / 待翻的牌都要回来")
	var s := GameState.new()
	s.owned_sets.append("smug")
	s.rewarded_tiers.append(RoleRequirement.Tier.EXTRA)
	s.pending_flips.append({"tier": RoleRequirement.Tier.SUPPORTING, "set": "smirk"})
	var json := JSON.stringify(s.to_save_dict())
	var parsed: Variant = JSON.parse_string(json)
	_check("存档能序列化", typeof(parsed), TYPE_DICTIONARY)
	var back := GameState.new()
	back.from_save_dict(parsed)
	_check("已拥有的套", back.owned_sets, ["smug"] as Array[String])
	# 【JSON 里整数会变成浮点】读回来必须还是 int，否则 `has_rewarded_tier` 会漏判
	_check("发过的档位", back.rewarded_tiers, [RoleRequirement.Tier.EXTRA] as Array[int])
	_check("待翻的牌", back.pending_flip_count(), 1)
	_check("待翻的牌面", String(back.peek_flip().get("set", "")), "smirk")
	# 加这个功能之前存的档没有这三个键 —— 读回来该是「一套都没有、也没有待翻的牌」
	var legacy := GameState.new()
	legacy.from_save_dict({})
	_check("老存档没有已拥有的套", legacy.owned_sets.is_empty(), true)
	_check("老存档没有待翻的牌", legacy.pending_flip_count(), 0)


# ============================================================
# 6. 录像机的门：拿到才点得动
# ============================================================
func _test_unlock_gate(game: Node) -> void:
	print("[6] 收发牌与录像机的解锁门")
	game.state = GameState.new()
	var eyes := PartLibrary.by_id("eyes_08")        # 得意
	var late := PartLibrary.by_id("eyes_10")        # 爆缸笑脸（周次门）
	var base := PartLibrary.by_id("eyes_04")        # 普通件
	_check("没拿到得意 → 不能用", game.is_part_unlocked(eyes), false)
	_check("普通件开局就能用", game.is_part_unlocked(base), true)
	_check("爆缸笑脸第 1 周不能用", game.is_part_unlocked(late), false)

	game.state.owned_sets.append("smug")
	_check("拿到得意 → 三件都能用", game.is_part_unlocked(eyes), true)
	_check("但绿豆蛙还是不能用", game.is_part_unlocked(PartLibrary.by_id("eyes_11")), false)

	game.state.day = 15   # 第 3 周
	_check("第 3 周爆缸笑脸解禁", game.is_part_unlocked(late), true)


# ============================================================
# 7. 翻牌界面
# ============================================================
func _test_ui(game: Node) -> void:
	print("[7] 翻牌界面：三张背牌 / 悬停描边 / 翻面 / 收下")
	game.state = GameState.new()
	game.state.queue_flip(RoleRequirement.Tier.EXTRA, "smug")
	_check("先排一张牌", game.has_pending_flip(), true)

	var app: Node = load(SCENE).instantiate()
	var finished := [0]
	app.connect("finished", func() -> void: finished[0] += 1)
	root.add_child(app)
	await process_frame

	_check("三张牌都摆出来了", app._cards.size(), 3)
	# 布局：三张等大、间距相等、整排不越界（"均匀排布于主屏幕"）
	await process_frame
	var c0: Button = app._cards[0]
	var c1: Button = app._cards[1]
	var c2: Button = app._cards[2]
	_check("三张牌等大", c0.size, Vector2(300, 382))
	var gap_a: float = c1.global_position.x - (c0.global_position.x + c0.size.x)
	var gap_b: float = c2.global_position.x - (c1.global_position.x + c1.size.x)
	_check("两张缝一样宽（均匀排布）", is_equal_approx(gap_a, gap_b), true)
	_check("整排没越出屏幕右边", c2.global_position.x + c2.size.x <= app.size.x, true)
	_check("结果框在牌下面", app._result.global_position.y >= c0.global_position.y + c0.size.y, true)
	_check("牌面还是背面", app._faces[0].texture, app._back_tex)
	_check("三张牌都点得动", app._cards[0].disabled, false)
	_check("结果框先藏起来（占位但透明）", app._result.modulate.a, 0.0)
	_check("「收下」还没解禁", app._claim_button.disabled, true)
	_check("顶部写明是哪个档位", app._title.text, "首次当上龙套")

	# 悬停：黄描边只亮在鼠标停着的那张上
	app._cards[0].mouse_entered.emit()
	_check("悬停的那张有描边", app._glows[0].visible, true)
	_check("别张没有", app._glows[1].visible, false)
	app._cards[0].mouse_exited.emit()
	_check("移开就收掉", app._glows[0].visible, false)

	# 翻面：鼠标停在牌上直接点（黄框必须自己收掉，否则会一直亮到收下之后）
	app._cards[1].mouse_entered.emit()
	app._cards[1].pressed.emit()
	_check("翻过之后不能再翻", app._cards[0].disabled, true)
	_check("停在牌上点下去也不留黄框", app._glows[1].visible, false)
	# 动画总长 2×0.16 秒，多给一倍余量再断言
	await create_timer(0.6).timeout
	_check("翻到的那张换成了正面", app._faces[1].texture, load(ExpressionSets.frame_of("smug")))
	_check("另外两张仍是背面", app._faces[0].texture, app._back_tex)
	_check("结果框亮起来了", app._result.modulate.a, 1.0)
	_check("结果框写着「获得表情」", app._result_caption.text, "获得表情")
	_check("结果框写着表情名", app._result_name.text, "得意")
	_check("「收下」解禁", app._claim_button.disabled, false)
	_check("还没点收下 → 牌没消费", game.has_pending_flip(), true)

	app._claim_button.pressed.emit()
	_check("收下 → 表情进库", game.state.owned_sets.has("smug"), true)
	_check("收下 → 牌消费掉", game.has_pending_flip(), false)
	_check("收下 → 通知调用方", finished[0], 1)
	_check("收下 → 得意三件在录像机里解禁", game.is_part_unlocked(PartLibrary.by_id("eyes_08")), true)
	# 连点不该消费第二张
	app._claim_button.pressed.emit()
	_check("连点不会重复消费", game.state.owned_sets.size(), 1)

	app.queue_free()
	await process_frame

	# 没有牌还开这一屏：安静收工，不留黑屏
	var empty_app: Node = load(SCENE).instantiate()
	var empty_done := [0]
	empty_app.connect("finished", func() -> void: empty_done[0] += 1)
	root.add_child(empty_app)
	# `_abort()` 走的是 `call_deferred` —— 延后调用在帧末才刷，等一帧不够
	await create_timer(0.05).timeout
	_check("没有牌时自己退出", empty_done[0], 1)
	empty_app.queue_free()


# ============================================================
# 工具
# ============================================================
## 记一笔成功的投递（片酬 / 演技按真实公司数据取 —— 与 test_week_cycle 同一套造法）
func _play(s: GameState, day: int, code: String, tier: int, match_rate: float,
		passed := true) -> void:
	var co := CompanyLibrary.by_code(code)
	var role := co.role_of(tier)
	s.day = day
	s.record_submission(passed, {
		"company_code": code,
		"role_tier": tier,
		"match_rate": match_rate,
		"play_title": "测试剧",
		"role_name": "测试角色",
		"payout": Economy.payout(co, role),
		"acting_gain": role.acting_gain,
	})


func _check(label: String, got: Variant, want: Variant) -> void:
	_checks += 1
	if got != want:
		_failures.append("%s: 期望 %s，实际 %s" % [label, want, got])
