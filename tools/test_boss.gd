extends SceneTree
## Boss直聘验证 —— headless 跑，驱动真实控件
##
##   godot --headless --path <项目> --script res://tools/test_boss.gd
##
## 【这个 App 只有一件事要做对】「看过招聘页 → 微信里多一个 HR」。
## 它自己没有任何动作（不投递、不花钱、不推进时间），所以测试的重点是：
##   1. 招聘页的内容真的来自 md（生成管线是活的，不是空字段）
##   2. 进页解锁，且**只解锁一次**（重复进出不该反复发信号）
##   3. 没点过的公司不能白送 HR

const SCENE := "res://scenes/apps/boss.tscn"
const COMPANY_DIR := "res://data/companies"
const CODES: Array[String] = ["A", "B", "C", "D", "E"]

var _failures: Array[String] = []
var _checks := 0
var _app
var _game
var _unlock_events: Array[String] = []


func _initialize() -> void:
	_app = load(SCENE).instantiate()
	root.add_child(_app)
	process_frame.connect(_run_all, CONNECT_ONE_SHOT)


func _run_all() -> void:
	print("")
	print("=== Boss直聘验证 ===")
	print("")

	_game = root.get_node_or_null("Game")
	var bus := root.get_node_or_null("EventBus")
	_check("Game autoload 可用", _game != null, true)
	if _game == null or bus == null:
		print("❌ 环境没起来")
		quit(1)
		return
	bus.hr_unlocked.connect(func(code: String) -> void: _unlock_events.append(code))

	_game.new_game()

	print("[1] 招聘页内容真的来自 md（生成管线是活的）")
	_check("公司数", CompanyLibrary.count(), 5)
	for code: String in CODES:
		var co: CompanyData = CompanyLibrary.by_code(code)
		_check("%s 有定位" % code, co.tagline.is_empty(), false)
		_check("%s 的定位与 md 标题一致" % code, co.tagline, _md_tagline(code))
		_check("%s 有行业" % code, co.industry.is_empty(), false)
		_check("%s 有规模" % code, co.scale.is_empty(), false)
		_check("%s 有代表性职位" % code, co.position_title.is_empty(), false)
		_check("%s 有薪资" % code, co.salary.is_empty(), false)
		_check("%s 有详情正文" % code, co.posting_text.length() > 50, true)
		_check("%s 详情里没有残留的 markdown 星号" % code, co.posting_text.contains("**"), false)
		_check("%s 线索里没有残留的 markdown 星号" % code, co.hint.contains("**"), false)
		print("   %s %-22s 职位：%s" % [code, co.tagline, co.position_title])
	_check("A 有标签", CompanyLibrary.by_code("A").tags.size() > 0, true)

	print("")
	print("[2] 开局是空状态，不白送 HR")
	_check("没解锁任何 HR", _game.state.unlocked_hr.size(), 0)
	_check("没有选中公司", _app._current, null)
	_check("招聘页处于空状态", _app._company_name.text, "还没选公司")
	_check("职位置卡隐藏", _app._job_panel.visible, false)
	_check("线索卡隐藏", _app._hint_panel.visible, false)
	_check("联系人行数", _app._rows.size(), 5)

	print("")
	print("[3] 点开一家 = 浏览过 = 解锁 HR")
	_app._select_company("A")
	_check("选中了 A", _app._current.code, "A")
	_check("A 的 HR 解锁了", _game.is_hr_unlocked("A"), true)
	_check("只发了 1 次 hr_unlocked", _unlock_events.size(), 1)
	_check("发的就是 A", _unlock_events[0], "A")
	_check("公司名渲染出来", _app._company_name.text, "A 公司")
	_check("定位渲染出来", _app._company_tagline.text, _md_tagline("A"))
	_check("职位渲染出来", _app._job_title.text, CompanyLibrary.by_code("A").position_title)
	_check("详情渲染出来",
			_app._detail_text.text, CompanyLibrary.by_code("A").posting_text)
	_check("线索渲染出来", _app._hint_text.text, CompanyLibrary.by_code("A").hint)
	_check("卡片都显示出来了", _app._job_panel.visible and _app._hint_panel.visible, true)
	_check("标签芯片数", _app._tag_row.get_child_count(),
			CompanyLibrary.by_code("A").tags.size())
	_check("解锁后锁状态转绿",
			_app._lock_state.text.contains("刚加上联系人"), true)
	_check("顶栏计数", _app._status_label.text, "已联系 1 / 5 家")

	print("")
	print("[4] 同一家再看一遍：不重复解锁、不重复发信号")
	_app._select_company("B")
	_app._select_company("A")
	_check("A 只解锁过一次", _unlock_events.count("A"), 1)
	_check("累计 2 次解锁事件（A + B）", _unlock_events.size(), 2)
	_check("锁状态改为「已加过」", _app._lock_state.text.contains("已在微信联系人里"), true)
	_check("顶栏计数", _app._status_label.text, "已联系 2 / 5 家")

	print("")
	print("[5] 五家全逛一遍")
	for code: String in CODES:
		_app._select_company(code)
	_check("五家都解锁了", _game.state.unlocked_hr.size(), 5)
	_check("解锁事件共 5 次（每家一次）", _unlock_events.size(), 5)
	_check("顶栏计数", _app._status_label.text, "已联系 5 / 5 家")
	_check("列表底部提示换了文案",
			_app._list_hint.text.contains("五家都加上了"), true)
	var states: Array[String] = []
	for code: String in CODES:
		states.append(String(_app._row_labels[code]["state"].text))
	_check("五行的状态都是已联系", states, ["已联系", "已联系", "已联系", "已联系", "已联系"])

	print("")
	print("[6] 解锁状态进存档")
	var path := "user://test_boss_save.json"
	_check("存档成功", _game.save_to(path), OK)
	_game.new_game()
	_check("重开后清空", _game.state.unlocked_hr.size(), 0)
	_check("读档成功", _game.load_from(path), true)
	_check("解锁状态还原", _game.state.unlocked_hr.size(), 5)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	_finish()


# ============================================================
## 直接读 md 的标题行，验证 .tres 里的定位确实是它生成出来的。
## 【为什么不写死期望值】md 是狗牙在改的内容，写死会让测试在他每次改文案时变红；
## 这里验的是「管线通不通」，不是「文案是什么」。
func _md_tagline(code: String) -> String:
	var dir := DirAccess.open(COMPANY_DIR)
	if dir == null:
		return ""
	for f: String in dir.get_files():
		if f.begins_with(code + "_") and f.ends_with(".md"):
			var lines := FileAccess.get_file_as_string("%s/%s" % [COMPANY_DIR, f]).split("\n")
			if lines.is_empty():
				return ""
			var parts := String(lines[0]).substr(2).split("｜")
			if parts.size() >= 2:
				return parts[1].strip_edges()
	return ""


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
