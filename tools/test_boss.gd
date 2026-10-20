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
	_check("公司名渲染出来", _app._company_name.text, "小登传媒")
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
	# 【不再写死条数】正式文案里开场有几句铺垫、支线各几条都由 md 决定，
	# 测试只验「顺序与分支对不对」，狗牙改文案不该让它变红。
	var a_lines := CompanyLibrary.by_code("A").opening_chat
	var a_first := _first_choice_at(a_lines)
	_check("选项前有铺垫（正式文案不是一句开场就轮到玩家）", a_first > 1, true)
	var a_branch1 := _branch_lines(a_lines, 1)
	_check("第一个选项有自己的支线", a_branch1.is_empty(), false)
	var reached: bool = await _open_chat_until_choices("A")
	_check("聊天层盖住了详情", _app.chat_open(), true)
	_check("已经轮到玩家挑", reached, true)
	_check("详情层收起来了", _app._post_panel.visible, false)
	_check("聊天头上是这位 HR", _app._chat_name.text, CompanyLibrary.by_code("A").hr_name)
	# 职位卡（1）+ 选项之前那几句铺垫 + 刚摆出来的选项框（1）
	_check("铺垫先铺完，才轮到玩家", _app._chat_feed.get_child_count(), a_first + 2)
	_check("选项竖着三个", _app._choices.get_child_count(), 3)
	_check("还没挑/还没放完时不解锁", _game.is_hr_unlocked("A"), false)
	# 挑第一个
	(_app._choices.get_child(0) as Button).pressed.emit()
	_check("选项撤掉了", _app._choices, null)
	_check("挑中的那句成了我发的消息", _text_of_feed(a_first + 1),
			a_lines[a_first].display_text())
	_check("记下他挑的是第几句（0 起）", _game.hr_choice_of("A", 0), 0)
	_app.skip_chat()          # 把剩下那条支线放完
	_check("放完的支线正好是第一个选项那条",
			_text_of_feed(_app._chat_feed.get_child_count() - 2),
			a_branch1[a_branch1.size() - 1].display_text())
	var a_branch2 := _branch_lines(a_lines, 2)
	_check("别的选项的支线一句都没出现",
			_feed_has(a_branch2[0].display_text()), false)
	_check("话说完就解锁了", _game.is_hr_unlocked("A"), true)
	_check("只发了 1 次 hr_unlocked", _unlock_events.size(), 1)
	_check("发的就是 A", _unlock_events[0], "A")
	# 职位卡 + 铺垫 + 自己那句 + 支线 + 系统提示（「已加进微信联系人」）
	_check("对话都进了聊天列表", _app._chat_feed.get_child_count(),
			a_first + 1 + a_branch1.size() + 2)
	# 头像的左右（这一条只有截图才看得出来）：HR = 头像 → 气泡；玩家 = 气泡 → 头像
	# 【下标不再是 1/2 固定成 HR/我】正式文案第一句是玩家说的（「你好，请问贵司招收演员吗」），
	# 所以 feed[1] 是我、feed[2] 才是 HR。
	var me_row: HBoxContainer = _app._chat_feed.get_child(1)
	var hr_row: HBoxContainer = _app._chat_feed.get_child(2)
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
	_check("第二次也是完整对话（职位卡 + 铺垫 + 自己那句 + 支线 + 系统提示）",
			_app._chat_feed.get_child_count(),
			a_first + 1 + a_branch1.size() + 2)
	var a_sys: Label = _app._chat_feed.get_child(_app._chat_feed.get_child_count() - 1)
	_check("系统提示换了说法", a_sys.text.contains("已经在你的微信联系人里"), true)
	_check("且没有重复解锁（还是 1 次）", _unlock_events.count("A"), 1)
	_app._close_chat()

	print("")
	print("[6] 话没说完就退出去：不算数")
	# 【这一节必须关掉快进】要的就是「正等着玩家挑」的中间状态 ——
	# 快进会一路放完并直接解锁，那就测不到「退出去不算数」了。
	var c_reached: bool = await _open_chat_until_choices("C")
	_check("退出前正等玩家挑（说明确实停在中间）", c_reached and _app._choices != null, true)
	_app._close_chat()             # 选项刚摆出来就退
	_check("C 仍然没解锁", _game.is_hr_unlocked("C"), false)
	_check("也没发过解锁事件", _unlock_events.count("C"), 0)

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
	_check("他挑过的那句也还原（不然再点开会换一句）", _game.hr_choice_of("A", 0), 0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	print("")
	print("[10] 与手机屏的接口：左栏公司列表 + 「去微信聊」")
	_check("交得出公司列表（手机屏的左栏）", _app.take_sidebar().name, "ListPanel")
	_check("左栏标题", _app.sidebar_title(), "简历拿来 · 公司")
	var req: Array[String] = []
	_app.open_app_requested.connect(func(p: String) -> void: req.append(p))
	_app._chat_to_wechat.pressed.emit()
	_check("「去微信聊」请上层打开微信", req, ["res://scenes/apps/wechat.tscn"] as Array[String])

	print("")
	print("[11] 第二次进同一家之后，别人家的三选一还在（提提报的）")
	# 玩家自然就会走到的路径：跟 A 聊完拿到联系方式 → 再点 A 的 HR 看一遍
	# → **从这一步起**，后面每一家的选项都不见了，第一句选项还被当成玩家自己说的话发出去。
	# 【根因】「第二次进同一家」走 `skip_chat()`，它把 `_chat_step` 压成 0；
	# 而那个值从来没在进聊天时复位，于是一路漏到别人家 —— 界面上不报错，只是「选项没了」。
	# 【为什么这条非写不可】当时 131 项断言全绿：每一节都在第一家之后就换了话题，
	# 没人回头看第二家。
	_game.new_game()
	var a_ok: bool = await _open_chat_until_choices("A")
	_check("第一家：选项在（改之前也是好的）", a_ok, true)
	_app.skip_chat()               # 把这家放完 → 解锁（原来那个「跳过 ▸▸」按钮做的事）
	_app._close_chat()
	_app._select_company("A")
	_app._open_chat()              # 第二次进：直接铺完 —— **这一步就会把 `_chat_step` 压成 0**
	_check("第二次进：不再演，直接铺完", _app._choices, null)
	_check("内容一模一样（职位卡 + 铺垫 + 自己那句 + 支线 + 系统提示）",
			_app._chat_feed.get_child_count(), a_first + 1 + a_branch1.size() + 2)
	_app._close_chat()
	var b_ok: bool = await _open_chat_until_choices("B")
	_check("第二家：选项也在", b_ok and _app._choices != null, true)
	_check("还是三个", _app._choices.get_child_count(), 3)
	var b_lines := CompanyLibrary.by_code("B").opening_chat
	_check("没替玩家先说话（职位卡 + 铺垫 + 选项框）",
			_app._chat_feed.get_child_count(), _first_choice_at(b_lines) + 2)
	_app._close_chat()
	print("   快进只作用于这一次；下一家照常轮到玩家挑")

	print("")
	print("[12] 第二次进同一家：铺出来的还是**他挑的那句**（提提报的）")
	# 复现路径：在 C 家挑了**第二句** → 退出去 → 再进来（这一层不演、直接铺完）
	# → 原先永远铺第一句，玩家会看见一句自己没说过的话。
	_game.new_game()
	var c_lines := CompanyLibrary.by_code("C").opening_chat
	var c_first := _first_choice_at(c_lines)
	var c_ok: bool = await _open_chat_until_choices("C")
	_check("C 也走到选项了", c_ok, true)
	(_app._choices.get_child(1) as Button).pressed.emit()   # 挑第二句
	_check("记下挑的是第 2 句", _game.hr_choice_of("C", 0), 1)
	_check("送出去的也是第 2 句", _text_of_feed(c_first + 1),
			c_lines[c_first + 1].display_text())
	_app.skip_chat()
	_app._close_chat()
	_app._select_company("C")
	_app._open_chat()          # 第二次进：直接铺完
	_check("铺出来的还是他挑的那句", _text_of_feed(c_first + 1),
			c_lines[c_first + 1].display_text())
	_check("不再永远退回第一句",
			_text_of_feed(c_first + 1) == c_lines[c_first].display_text(), false)
	_app._close_chat()
	print("   挑过哪句进了进度；第二次进照他挑的铺")

	_finish()


## 选某家、进聊天，一直等到「轮到玩家挑」那一刻。
## 【为什么不能像以前那样一进去就断言选项】正式文案开场有好几句铺垫，
## 播放是异步的（每条之间要停一下），所以测试得等。
## 步长在进聊天后压到 0.01 —— `_open_chat` 每次都会复位成 CHAT_STEP，不会漏到下一节。
func _open_chat_until_choices(code: String) -> bool:
	_app._select_company(code)
	_app._fast_forward = false
	_app._first_msg_delay = 0.0
	_app._open_chat()
	_app._chat_step = 0.01
	return await _await_choices()


func _await_choices(timeout := 15.0) -> bool:
	var waited := 0.0
	while _app._choices == null and not _app._chat_done and waited < timeout:
		await create_timer(0.02).timeout
		waited += 0.02
	return _app._choices != null


## 第一组选项在数组里的下标（`opening_chat` 里前面有几句铺垫）
func _first_choice_at(lines: Array[ChatLine]) -> int:
	for i in lines.size():
		if lines[i].is_choice():
			return i
	return lines.size()


## 第 n 个选项的支线（按数组顺序）
func _branch_lines(lines: Array[ChatLine], n: int) -> Array[ChatLine]:
	var out: Array[ChatLine] = []
	for line: ChatLine in lines:
		if line.branch == n:
			out.append(line)
	return out


## 聊天列表里有没有出现过这句话
func _feed_has(text: String) -> bool:
	for i in _app._chat_feed.get_child_count():
		if _text_of_feed(i) == text:
			return true
	return false


## 取聊天列表里第 i 个孩子的文字（气泡、系统提示都能取）
func _text_of_feed(i: int) -> String:
	var node: Node = _app._chat_feed.get_child(i)
	if node is Label:
		return (node as Label).text
	# 气泡那一行是 [空档/头像, 面板, 头像/空档]，面板里是 [边距, 文字]
	var panel: Node = node.get_child(1)
	return (panel.get_child(0).get_child(0) as Label).text


## 走完「点开一家 → 点 HR → 聊完」这条链路。
## 【测试里开 `_fast_forward`】它走的就是「跳过」那条路：一次放完，不必等计时器 ——
## 否则断言得跟着 0.85 秒的节奏写，又慢又脆。
## 【为什么不再直接设 `_chat_step`】那个值现在每次进聊天都会被复位 —— 正是下面 [11] 教的。
func _walk_hr_chat(code: String) -> void:
	_app._select_company(code)
	_app._fast_forward = true
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
