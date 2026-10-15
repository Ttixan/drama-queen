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
	_check("联系人行数", _app._rows.size(), 5)

	print("")
	print("[3] 点开一家：先看详情 —— **看招聘页不给联系人**")
	_app._select_company("A")
	_check("选中了 A", _app._current.code, "A")
	_check("看招聘页不解锁", _game.is_hr_unlocked("A"), false)
	_check("一条解锁事件都没发", _unlock_events.size(), 0)
	_check("公司名渲染出来", _app._company_name.text, "A 公司")
	_check("定位渲染出来", _app._company_tagline.text, _md_tagline("A"))
	_check("职位渲染出来", _app._job_title.text, CompanyLibrary.by_code("A").position_title)
	_check("详情渲染出来",
			_app._detail_text.text, CompanyLibrary.by_code("A").posting_text)
	# 线索**还在数据里**，只是界面上不再显示（绿框已删）—— 别把内容一起丢了
	_check("线索数据没丢（只是不显示了）", CompanyLibrary.by_code("A").hint.is_empty(), false)
	_check("职位卡显示出来了", _app._job_panel.visible, true)
	_check("标签芯片数", _app._tag_row.get_child_count(),
			CompanyLibrary.by_code("A").tags.size())
	_check("HR 卡显示出来了", _app._hr_card.visible, true)
	_check("HR 卡上是真名字",
			(_app._hr_labels["name"] as Label).text, CompanyLibrary.by_code("A").hr_name)
	_check("HR 活跃状态来自文案",
			(_app._hr_labels["status"] as Label).text,
			CompanyLibrary.by_code("A").hr_status)
	_check("「还没联系过」写在锁状态里", _app._lock_state.text.contains("还没联系过"), true)
	_check("顶栏计数还是 0", _app._status_label.text, "已联系 0 / 5 家")

	print("")
	print("[4] 点 HR 进聊天：先听开场，再自己挑一句回过去")
	_check("A 的对话共 5 条（开场 + 三个选项 + 统一回复）",
			CompanyLibrary.by_code("A").opening_chat.size(), 5)
	_app._open_chat()
	_check("聊天层盖住了详情", _app.chat_open(), true)
	_check("详情层收起来了", _app._post_panel.visible, false)
	_check("聊天头上是这位 HR", _app._chat_name.text, CompanyLibrary.by_code("A").hr_name)
	# 职位卡 + 开场白 + **刚摆出来的选项** —— 选项是紧跟着开场白出现的，不等计时器
	_check("职位卡 + 开场白 + 选项", _app._chat_feed.get_child_count(), 3)
	_check("开场白之后立刻轮到你（不用干等）", _app._choices != null, true)
	_check("选项竖着三个", _app._choices.get_child_count(), 3)
	_check("还没挑/还没放完时不解锁", _game.is_hr_unlocked("A"), false)
	# 挑第一个（点哪个都行，HR 后面回的是同一句）
	(_app._choices.get_child(0) as Button).pressed.emit()
	_check("选项撤掉了", _app._choices, null)
	_check("挑中的那句成了我发的消息", _text_of_feed(2),
			CompanyLibrary.by_code("A").opening_chat[1].display_text())
	_app._chat_step = 0.0
	_app.skip_chat()
	_check("HR 回的是同一句（挑哪句无关）", _text_of_feed(3),
			CompanyLibrary.by_code("A").opening_chat[4].display_text())
	_check("话说完就解锁了", _game.is_hr_unlocked("A"), true)
	_check("只发了 1 次 hr_unlocked", _unlock_events.size(), 1)
	_check("发的就是 A", _unlock_events[0], "A")
	# 职位卡 + 3 条对话 + 1 条系统提示（「已加进微信联系人」）
	_check("对话都进了聊天列表", _app._chat_feed.get_child_count(), 5)
	# 头像的左右（这一条只有截图才看得出来）：HR = 头像 → 气泡；玩家 = 气泡 → 头像
	var hr_row: HBoxContainer = _app._chat_feed.get_child(1)
	var me_row: HBoxContainer = _app._chat_feed.get_child(2)
	_check("HR 那行第一块是头像（在最左）", hr_row.get_child(0) is Panel, true)
	_check("HR 那行气泡在头像右边", hr_row.get_child(1) is PanelContainer, true)
	_check("玩家那行气泡在前", me_row.get_child(1) is PanelContainer, true)
	_check("玩家那行头像是最后一块（在最右）", me_row.get_child(2) is Panel, true)
	_check("出现「去微信聊」", _app._chat_to_wechat.visible, true)
	_check("解锁后锁状态转绿",
			_app._lock_state.text.contains("刚加上联系人"), true)
	_check("顶栏计数", _app._status_label.text, "已联系 1 / 5 家")
	_app._close_chat()
	_check("退回详情", _app._post_panel.visible and not _app.chat_open(), true)

	print("")
	print("[5] 第二次进聊天：内容一模一样，但不再演")
	_walk_hr_chat("A")            # A 已经解锁过 → 应当直接铺完
	_check("第二次也是完整对话（职位卡 + 3 条 + 系统提示）",
			_app._chat_feed.get_child_count(), 5)
	_check("系统提示换了说法",
			(_app._chat_feed.get_child(4) as Label).text.contains("已经在你的微信联系人里"), true)
	_check("且没有重复解锁（还是 1 次）", _unlock_events.count("A"), 1)
	_app._close_chat()

	print("")
	print("[6] 话没说完就退出去：不算数")
	_app._select_company("C")
	_app._chat_step = 1.0          # 让它处在「正在播」的状态（测试不等它）
	_app._open_chat()
	_app._close_chat()             # 第一条刚出来就退
	_check("C 仍然没解锁", _game.is_hr_unlocked("C"), false)
	_check("也没发过解锁事件", _unlock_events.count("C"), 0)
	_app._chat_step = 0.0

	print("")
	print("[7] 同一家再看一遍：不重复解锁、不重复发信号")
	_walk_hr_chat("B")
	_app._select_company("A")
	_check("A 只解锁过一次", _unlock_events.count("A"), 1)
	_check("累计 2 次解锁事件（A + B）", _unlock_events.size(), 2)
	_check("锁状态改为「已加过」", _app._lock_state.text.contains("已在微信联系人里"), true)
	_check("顶栏计数", _app._status_label.text, "已联系 2 / 5 家")

	print("")
	print("[8] 五家全聊一遍")
	for code: String in CODES:
		_walk_hr_chat(code)
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
	print("[9] 解锁状态进存档")
	var path := "user://test_boss_save.json"
	_check("存档成功", _game.save_to(path), OK)
	_game.new_game()
	_check("重开后清空", _game.state.unlocked_hr.size(), 0)
	_check("读档成功", _game.load_from(path), true)
	_check("解锁状态还原", _game.state.unlocked_hr.size(), 5)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	print("")
	print("[10] 与手机屏的接口：左栏公司列表 + 「去微信聊」")
	_check("交得出公司列表（手机屏的左栏）", _app.take_sidebar().name, "ListPanel")
	_check("左栏标题", _app.sidebar_title(), "Boss直聘 · 公司")
	var req: Array[String] = []
	_app.open_app_requested.connect(func(p: String) -> void: req.append(p))
	_app._chat_to_wechat.pressed.emit()
	_check("「去微信聊」请上层打开微信", req, ["res://scenes/apps/wechat.tscn"] as Array[String])

	_finish()


## 取聊天列表里第 i 个孩子的文字（气泡、系统提示都能取）
func _text_of_feed(i: int) -> String:
	var node: Node = _app._chat_feed.get_child(i)
	if node is Label:
		return (node as Label).text
	# 气泡那一行是 [空档/头像, 面板, 头像/空档]，面板里是 [边距, 文字]
	var panel: Node = node.get_child(1)
	return (panel.get_child(0).get_child(0) as Label).text


## 走完「点开一家 → 点 HR → 聊完」这条链路。
## 【测试里把 `_chat_step` 设成 0】那就是「跳过」按钮走的那条路：一次放完，不必等计时器 ——
## 否则断言得跟着 0.85 秒的节奏写，又慢又脆。
func _walk_hr_chat(code: String) -> void:
	_app._select_company(code)
	_app._chat_step = 0.0
	_app._open_chat()


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
