extends SceneTree
## 「记忆抽取」验证 —— 新手礼包翻牌（三选一，翻中哪张拿哪套）
##
##   godot --path <项目> --script res://tools/test_memory_draw.gd
##
## 【验什么】
##   1. 三张牌 = 爆缸笑脸 / 恶俗青蛙 / 严肃给力，牌背是问号拍立得
##   2. 翻第二张 → 牌面换成恶俗青蛙，`picked` 报的是它
##   3. 新手礼包**不进周结算的抽奖池**（否则开局前就可能被周结算抽走）
##   4. 收下之后那套进 `owned_sets`，录像机据此解禁三件部件

const SCENE := "res://scenes/ui/memory_draw.tscn"

var _failures: Array[String] = []
var _checks := 0
var _game


func _initialize() -> void:
	_game = root.get_node_or_null("Game")
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	print("")
	print("=== 记忆抽取验证 ===")
	print("")
	_check("Game autoload 可用", _game != null, true)
	if _game == null:
		print("❌ 环境没起来")
		quit(1)
		return
	_game.new_game()

	print("[1] 三张牌：三套新手礼包，牌背是问号")
	var app = load(SCENE).instantiate()
	root.add_child(app)
	await process_frame
	_check("三张牌", app._cards.size(), 3)
	_check("三套 id", app.card_ids(), ["blowup", "frog", "serious"] as Array[String])
	_check("牌背是拍立得问号",
			app._faces[0].texture.resource_path, ExpressionSets.STARTER_BACK_FRAME)
	_check("没翻之前收下是灰的", app._claim.disabled, true)
	_check("新手礼包没有正面图缺失",
			ResourceLoader.exists(ExpressionSets.frame_of("blowup"))
			and ResourceLoader.exists(ExpressionSets.frame_of("frog"))
			and ResourceLoader.exists(ExpressionSets.frame_of("serious")), true)

	print("")
	print("[2] 翻第二张 → 恶俗青蛙")
	var picked: Array[String] = []
	app.picked.connect(func(id: String) -> void: picked.append(id))
	app._cards[1].pressed.emit()
	await create_timer(0.6).timeout
	_check("两边都知道翻到的是青蛙", [app.picked_id(), picked], ["frog", ["frog"]] as Array)
	_check("第二张的牌面换成了青蛙",
			app._faces[1].texture.resource_path, ExpressionSets.frame_of("frog"))
	_check("另外两张还是问号",
			app._faces[0].texture.resource_path, ExpressionSets.STARTER_BACK_FRAME)
	_check("翻过之后不能翻第二张", app._cards[0].disabled, true)
	_check("收下可以点了", app._claim.disabled, false)

	print("")
	print("[3] 收下 → 进已拥有；周结算抽不到新手礼包")
	_game.grant_expression_set(app.picked_id())
	_check("状态里有 frog", _game.state.owned_sets.has("frog"), true)
	_check("爆缸/严肃没被顺带送出",
			_game.state.owned_sets.has("blowup") or _game.state.owned_sets.has("serious"), false)
	_check("周结算池只有那三套", ExpressionSets.reward_ids(), ["smug", "smirk", "late_love"] as Array[String])
	_check("新手礼包不在抽奖池", ExpressionSets.reward_ids().has("frog"), false)
	var finished := []
	app.finished.connect(func() -> void: finished.append(true))
	app._claim.pressed.emit()
	_check("收下后发出 finished", finished.size(), 1)

	print("")
	print("[4] 存档往返：礼包跟着存档走")
	var d: Dictionary = _game.state.to_save_dict()
	var fresh = load("res://scripts/core/game_state.gd").new()
	fresh.from_save_dict(d)
	_check("读档后仍然拥有 frog", fresh.owned_sets.has("frog"), true)

	_finish()


func _check(label: String, got: Variant, want: Variant) -> void:
	_checks += 1
	if got != want:
		_failures.append("%s: 期望 %s，实际 %s" % [label, want, got])


func _finish() -> void:
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
