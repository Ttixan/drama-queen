extends SceneTree
## 拍戏日验证 —— 试镜通过后的第二天整天跳过
##
##   godot --path <项目> --script res://tools/test_shoot_day.gd
##
## 【验什么】
##   1. 推进到拍戏日时**连推两天**，并把跳过了第几天回报给界面（黑幕写「去演戏了，跳过此天」）
##   2. 拍戏日撞上周日，那周的结算照发（不能被一起跳掉）
##   3. 拍戏日进存档，读档回来还在

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	print("")
	print("=== 拍戏日验证 ===")
	print("")
	var game := root.get_node_or_null("Game")
	_check("Game 可用", game != null, true)
	if game == null:
		quit(1)
		return

	print("[1] 拍戏日整天跳过")
	game.new_game()
	game.state.shoot_day = 2          # 模拟第 1 天试镜通过
	var res: Dictionary = game.end_day()
	_check("第 1 天结束 → 直接落到第 3 天", game.state.day, 3)
	_check("结果里写明跳过了第 2 天", int(res.get("shoot_skipped", -1)), 2)
	_check("标记已被消费", game.state.shoot_day, 0)
	var res2: Dictionary = game.end_day()
	_check("第 3 天正常推进到第 4 天", game.state.day, 4)
	_check("没拍戏的日子不带跳过标记", res2.has("shoot_skipped"), false)

	print("")
	print("[2] 拍戏日撞周日：结算照发")
	game.new_game()
	game.state.day = 6                # 下一天是第 7 天（周日）
	game.state.shoot_day = 7
	var res3: Dictionary = game.end_day()
	_check("跳到第 8 天", game.state.day, 8)
	_check("这一周仍然结算了", res3.get("settled", false), true)
	_check("跳过的是第 7 天", int(res3.get("shoot_skipped", -1)), 7)

	print("")
	print("[3] 每天结束都自动存档")
	var saves: Array[int] = []
	var bus := root.get_node_or_null("EventBus")
	if bus != null:
		bus.save_requested.connect(func() -> void: saves.append(int(game.day())))
	game.new_game()
	game.end_day()
	_check("推进一天就发一次存档请求", saves.size() >= 1, true)
	var before := saves.size()
	game.end_day()
	_check("再推一天又多一次", saves.size(), before + 1)

	print("")
	print("[4] 存档往返")
	game.new_game()
	game.state.shoot_day = 5
	var fresh = load("res://scripts/core/game_state.gd").new()
	fresh.from_save_dict(game.state.to_save_dict())
	_check("读档保留拍戏日", fresh.shoot_day, 5)
	fresh.from_save_dict({"money": 10})
	_check("老档没有这个字段时当作没有安排", fresh.shoot_day, 0)

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
