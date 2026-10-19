extends SceneTree
## 开场导入验证 —— headless 跑，不需要渲染，也不需要人手点
##
##   godot --headless --path <项目> --script res://tools/test_intro.gd
##
## 【验的是哪条链】
##   数据（intro.tres 非空 / A2+A3 六句）
##   → A1 报纸（淡入之后才出现 ×）
##   → 关广告（报纸让位给对话框）
##   → 六句独白（点击推进，最后一句之后才出名字卡）
##   → 取名（写进 GameState + 同步 CastingPool + 存档）
##
## 【为什么必须机器验】「× 在文字出来之前就能点」「名字没写进存档」
## 「老存档被强制重看开场」这三件事，靠手点三次是看不住的。
##
## 【存档保护】本测试会真的触发 `save_requested`（那是产品行为）。
## 开跑前备份 `user://save.json`，跑完原样写回 —— 与 test_phone_shell 同一套。

const SCENE := "res://scenes/intro/intro.tscn"
const SAVE_PATH := "user://save.json"

var _failures: Array[String] = []
var _checks := 0
var _app
var _game
var _snapshot: Dictionary = {}
var _finished_flag := 0


func _initialize() -> void:
	_app = load(SCENE).instantiate()
	root.add_child(_app)
	process_frame.connect(_run_all, CONNECT_ONE_SHOT)


func _run_all() -> void:
	print("")
	print("=== 开场导入验证（A1 报纸 → A2/A3 独白 → 取名）===")
	print("")

	_game = root.get_node_or_null("Game")
	var bus := root.get_node_or_null("EventBus")
	_check("Game autoload 可用", _game != null, true)
	_check("EventBus autoload 可用", bus != null, true)
	if _game == null or bus == null:
		print("❌ 环境没起来")
		quit(1)
		return

	# 先备份真存档，再开一局干净状态（本测试会写回名字）
	_snapshot = _snapshot_save()
	_game.new_game()

	_test_data()
	await _test_ad()
	await _test_dialogue()
	await _test_name()
	_test_save_compat()
	_test_new_game_resets_name()

	_restore_save(_snapshot)
	_finish()


# ============================================================
func _test_data() -> void:
	print("[1] 数据 + 字体：intro.tres 由 md 生成；正文必须覆盖开场全部用字")
	# 【字体也要验】换过一次缺 590 个字的日文字体；「缺字」在界面上只是少几笔，
	# 不跑覆盖率检查的话，下次再换字体还会踩同一个坑。
	var font: Font = load("res://assets/fonts/ShiweiBanyue-Light.ttf")
	_check("正文字体可加载", font != null, true)

	var d = _app.data
	_check("读到了 IntroData", d != null, true)
	if d == null:
		return

	if font != null:
		var text: String = String(d.masthead) + String(d.edition) + String(d.title) \
				+ String(d.product) + String(d.subtitle) + String(d.body) \
				+ String(d.countdown) + String(d.footer)
		for line: Dictionary in d.narration():
			text += String(line["text"])
		var missing := ""
		for i: int in text.length():
			var code: int = text.unicode_at(i)
			# 只验中文与中文标点。`·`（U+00B7）这类西文分隔符归系统字体兜底，
			# 不值得为了一个装饰点换整套字。
			var cjk := (code >= 0x3400 and code <= 0x9fff) \
					or (code >= 0x3000 and code <= 0x303f) \
					or (code >= 0xff00 and code <= 0xffef)
			if cjk and not font.has_char(code):
				missing += text[i]
		_check("开场中文用字 0 缺字", missing, "")

	_check("内容自检无错", str(d.validate()), "[]")
	_check("报头", d.masthead, "《有瓜有戏》")
	_check("产品名", d.product, "PSwitch box2")
	_check("倒计时", d.countdown, "距离发售：21天")
	_check("A2 三句", d.lines_a2.size(), 3)
	_check("A3 三句", d.lines_a3.size(), 3)
	_check("独白合计六句", d.narration().size(), 6)
	_check("第一句是「关掉广告」", d.narration()[0]["text"], d.lines_a2[0])
	_check("最后一句是「开工」", d.narration()[5]["text"], "21天，凑够钱。开工！")
	_check("广告正文没丢", d.body.contains("掌机主机一体"), true)
	print("   %s · %s；正文 %d 行；独白 %d 句" % [
		d.masthead, d.product, d.body.split("\n").size(), d.narration().size()])


# ============================================================
func _test_ad() -> void:
	print("")
	print("[2] A1：报纸整版广告，淡入之后才允许关")
	_check("报纸在", _app._paper_layer.visible, true)
	_check("对话框还没出来", _app._dialogue_host.visible, false)
	_check("名字卡还没出来", _app._name_layer.visible, false)
	_check("淡入完成前 × 不出现（防止没看就关）", _app._close_button.visible, false)

	await create_timer(0.85).timeout
	_check("淡入完成后 × 出现", _app._close_button.visible, true)
	_check("× 在报纸层上", _app._close_button.get_parent(), _app._paper_layer)

	_app._on_close_ad()
	await create_timer(0.9).timeout
	_check("报纸让位", _app._paper_layer.visible, false)
	_check("对话框出场", _app._dialogue_host.visible, true)
	_check("停在第 1 句", _app._dialogue.current_index(), 0)
	_check("台词总数", _app._dialogue.line_count(), 6)
	_check("第一句是「你关掉广告」",
			_app._dialogue._text.text.begins_with("你关掉广告"), true)
	print("   报纸 → 对话框；第一句「%s…」" % _app._dialogue._text.text.substr(0, 12))


# ============================================================
func _test_dialogue() -> void:
	print("")
	print("[3] A2/A3：点击一句一句推进，最后一句之后才收")
	for i: int in range(6):
		_check("第 %d 句已就位" % (i + 1), _app._dialogue.current_index(), i)
		# 打字中：第一次点只补全，不跳句
		if _app._dialogue.is_typing():
			_app._dialogue.advance()
			_check("补全后仍在第 %d 句" % (i + 1), _app._dialogue.current_index(), i)
		_app._dialogue.advance()

	_check("六句之后对话框收掉", _app._dialogue_host.visible, false)
	await process_frame
	_check("名字卡出来了", _app._name_layer.visible, true)
	print("   六句推进完 → 演员登记表")


# ============================================================
func _test_name() -> void:
	print("")
	print("[4] 取名：空名不能开工，确认后写进状态 + 定角池 + 存档")
	_app._name_edit.text = "   "
	_app._on_name_changed("   ")
	_check("空名时开工置灰", _app._confirm_button.disabled, true)

	_app._name_edit.text = "阿呆"
	_app._on_name_changed("阿呆")
	_check("有名字时开工可点", _app._confirm_button.disabled, false)
	_check("最多 6 个字", _app._name_edit.max_length, 6)

	_app.finished.connect(func() -> void: _finished_flag += 1)
	_app._on_confirm_pressed()

	_check("状态里存了名字", _game.state.player_name, "阿呆")
	_check("Game.player_name 读得到", _game.player_name(), "阿呆")
	_check("定角池镜像同步（邮件 / 报纸走的就是这条）",
			MailLibrary.casting_pool().player_name, "阿呆")
	_check("开场已标记完成", _game.state.intro_done, true)
	_check("发出了 finished", _finished_flag, 1)

	# 确认时真的落盘了 —— 不落盘的话下次启动还会重看
	var raw := FileAccess.get_file_as_string(SAVE_PATH)
	_check("存档里有名字", raw.contains("\"player_name\": \"阿呆\""), true)
	_check("存档里有开场标记", raw.contains("\"intro_done\": true"), true)

	await create_timer(0.7).timeout
	_check("收尾后开场节点自己清掉", is_instance_valid(_app), false)
	print("   阿呆 · 已落盘；开场节点已释放")


# ============================================================
func _test_save_compat() -> void:
	print("")
	print("[5] 存档兼容：老档不重看，新局要看")
	var old := GameState.new()
	old.from_save_dict({"money": 999, "day": 12})
	_check("老档没有 intro_done → 当已看过", old.intro_done, true)
	_check("老档没有名字 → 空串（回退定角池）", old.player_name, "")

	var fresh := GameState.new()
	_check("新局 intro_done = false", fresh.intro_done, false)

	var saved := GameState.new()
	saved.intro_done = true
	saved.player_name = "阿呆"
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved.to_save_dict()))
	var back := GameState.new()
	back.from_save_dict(parsed)
	_check("名字能过 JSON 往返", back.player_name, "阿呆")
	_check("开场标记能过 JSON 往返", back.intro_done, true)


# ============================================================
func _test_new_game_resets_name() -> void:
	print("")
	print("[6] 重开一局：名字回到出厂值，等下一次取名")
	_game.set_player_name("另一个名字")
	_check("先改成一个新名字", MailLibrary.casting_pool().player_name, "另一个名字")
	_game.new_game()
	_check("开新局清掉玩家名", _game.state.player_name, "")
	_check("定角池回到出厂名", MailLibrary.casting_pool().player_name, "林小满")
	_check("新局又要看开场", _game.state.intro_done, false)


# ============================================================
# 存档备份 / 还原
# ============================================================
func _snapshot_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {"existed": false}
	return {"existed": true, "bytes": FileAccess.get_file_as_bytes(SAVE_PATH)}


func _restore_save(snap: Dictionary) -> void:
	if bool(snap.get("existed", false)):
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(snap["bytes"])
		f.close()
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


# ============================================================
func _check(label: String, got: Variant, want: Variant) -> void:
	_checks += 1
	if got != want:
		_failures.append("%s：得到 %s，期望 %s" % [label, str(got), str(want)])


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("✅ 全部通过（%d 项断言）" % _checks)
		quit(0)
	else:
		print("❌ %d / %d 项失败：" % [_failures.size(), _checks])
		for f: String in _failures:
			print("   - " + f)
		quit(1)
