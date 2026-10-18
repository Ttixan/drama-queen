extends SceneTree
## 主界面两屏验证 —— headless 跑，驱动真实控件
##
## 【改版后它测两张屏】桌子下面分成两屏：
##   `calendar_screen`（日历）= 状态栏 + 今日安排 + 本周进度 + 结算浮层 + 重开一局
##   `phone_screen`（手机）  = 左栏 App 列表 / 某个 App 的二级列表 + 右栏内容
## 变量名沿用 `_app`（历史上只有一个手机壳），它是**日历屏**；手机屏是 `_phone`。
##
##   godot --headless --path <项目> --script res://tools/test_phone_shell.gd
##
## 【这是第一条"整局"级的测试】前面几条链测的都是单个系统，
## 这一条走的是**玩家真实的那条路**：桌面 → 打工 / 上课 → 结束今天 →
## 周末结算浮层 → 翻篇 → 三周后结局 → 再来一局。
## 它同时守住两条边界：
##   1. 手机壳里**不许出现玩法数值**（+30 元必须来自 Economy，不是这里写死的）
##   2. 主场景换了之后，开新局 / 读档必须把打开的 App 与浮层一起清掉

const SCENE := "res://scenes/main/calendar_screen.tscn"
const PHONE_SCENE := "res://scenes/main/phone_screen.tscn"
const WECHAT_SCENE := "res://scenes/apps/wechat.tscn"
const BOSS_SCENE := "res://scenes/apps/boss.tscn"
const RECORDER_SCENE := "res://scenes/minigame/recorder.tscn"

var _failures: Array[String] = []
var _checks := 0
var _app        ## 日历屏（今日安排 / 结算 / 结局 / 重开都在它身上）
var _phone      ## 手机屏（左栏 App 列表 / 右栏内容）
var _game
## 开跑之前那份 `user://save.json`（可能是玩家的真进度）。跑完原样写回
var _save_snapshot: Dictionary = {}


func _initialize() -> void:
	_app = load(SCENE).instantiate()
	root.add_child(_app)
	_phone = load(PHONE_SCENE).instantiate()
	root.add_child(_phone)
	process_frame.connect(_run_all, CONNECT_ONE_SHOT)


func _run_all() -> void:
	print("")
	print("=== 主界面两屏验证（日历 + 手机）===")
	print("")

	_game = root.get_node_or_null("Game")
	var bus := root.get_node_or_null("EventBus")
	_check("Game autoload 可用", _game != null, true)
	if _game == null or bus == null:
		print("❌ 环境没起来")
		quit(1)
		return
	_game.new_game()

	# 【整条链跑完必须把真存档还原】下面有好几节会走 `Game.advance_day()` ——
	# 跨周时它会 `save_requested` → 写 `user://save.json`（那是产品行为，不是测试的错），
	# 而 `user://` 与真机上那份存档**是同一个目录**。
	# 不还原的话，跑完测试再打开游戏看到的是一个测试局 —— 10-16 就这么丢过一次进度。
	_save_snapshot = _snapshot_save()

	_test_desktop()
	_test_work_and_class()
	_test_app_switch()
	_test_app_jump()
	_test_badges()
	_test_end_day()
	_test_week_settle()
	_test_full_run_to_ending()
	_test_finished_save()
	_test_save_load()
	_test_restart_button()
	_test_week_event()
	_test_desk_jump()
	_test_notebook()
	_test_sfx()

	print("")
	print("共 %d 项断言" % _checks)
	# 无论成败都要还原真存档 —— 失败时更容易留下一个半截的测试局
	_restore_save(_save_snapshot)
	if _failures.is_empty():
		print("✅ 全部通过")
		quit(0)
	else:
		print("❌ %d 项失败：" % _failures.size())
		for f: String in _failures:
			print("   - " + f)
		quit(1)


func _check(label: String, got: Variant, want: Variant) -> void:
	_checks += 1
	if got != want:
		_failures.append("%s: 期望 %s，实际 %s" % [label, want, got])


func _card(key: String) -> Button:
	return _app._cards[key]["button"]


func _card_state(key: String) -> String:
	return String(_app._cards[key]["state"].text)


# ============================================================
func _test_desktop() -> void:
	print("[1] 台历：第 N 天 + 今日安排 ｜ 手机：左栏 App 列表")
	_check("四张动作卡都在", _app._cards.size(), 4)
	_check("手机左栏列着四个 App", _phone._app_list.get_child_count(), 4)
	_check("开局没有打开的 App", _phone.current_app_path(), "")
	_check("结算层是隐藏的", _app._report_layer.visible, false)
	_check("台历上能看到属性（这是做决定的地方）",
			_app._ps5_label.text.is_empty(), false)
	_check("手机栏是窄的：只有天数 / 行动点 / 钱", _phone._money_label.text.is_empty(), false)

	var bal := BalanceLibrary.data()
	# 【版面改版后这些 Label 只写数字】单位（元 / 点 / 期）是旁边一个独立小字，
	# 混进同一个 Label 就没法让数字走 BubbleDub、中文走 Lemi。
	_check("状态·金钱 == 数值表的初始金钱", _app._money_label.text, str(bal.init_money))
	_check("状态·行动点", _app._ap_label.text, str(GameState.AP_PER_DAY))
	# 抬头是「第 {BubbleDub 数字} 天」：`_day_label` 只放那个数字
	_check("状态·天数", _app._day_label.text, "1")
	_check("状态·PS5 进度", _app._ps5_label.text, "0 / %d" % bal.ps5_installments)

	_check("投递卡可用", _card("submit").disabled, false)
	_check("打工卡可用", _card("work").disabled, false)
	_check("上课卡可用", _card("class").disabled, false)
	_check("结束今天卡可用", _card("end").disabled, false)
	# 卡片上的数字必须来自 Economy，而不是手机壳里写死的
	_check("打工卡写着 Economy 的收入", _card_state("work").contains(str(Economy.work_income())), true)
	print("   行动点 1、金钱 %d，四张卡都可点" % bal.init_money)


func _test_work_and_class() -> void:
	print("[2] 打工 / 上课：即时到账，不走周末结算")
	var money0: int = _game.money()
	_app._on_work_pressed()
	_check("打工 +%d 元" % Economy.work_income(), _game.money(), money0 + Economy.work_income())
	_check("打工花掉行动点", _game.ap_left(), 0)
	_check("本周打工计数", _game.state.work_this_week, 1)

	# 行动点没了 —— 四张卡里只剩「结束今天」还能点
	_check("投递卡被灰掉", _card("submit").disabled, true)
	_check("打工卡被灰掉", _card("work").disabled, true)
	_check("上课卡被灰掉", _card("class").disabled, true)
	_check("灰掉的原因写在卡上", _card_state("work"), Economy.REASON_AP)
	_check("结束今天仍然可点", _card("end").disabled, false)

	_app._on_end_day_pressed()
	_check("结束今天推进到第 2 天", _game.day(), 2)
	_check("次日行动点恢复", _game.ap_left(), GameState.AP_PER_DAY)
	_check("新的一天打工卡又亮了", _card("work").disabled, false)

	# 上课
	var money1: int = _game.money()
	var acting0: int = _game.acting()
	_app._on_class_pressed()
	_check("上课扣学费", _game.money(), money1 - Economy.class_fee())
	_check("上课涨演技", _game.acting(), acting0 + Economy.class_gain())
	_check("本周上课计数", _game.state.class_this_week, 1)
	_app._on_end_day_pressed()
	_check("上完课本周不能再上", _card("class").disabled, true)
	_check("原因是本周上过了", _card_state("class").contains("上过"), true)
	print("   打工 +%d / 上课 −%d+%d 演技；一天一件事，用完就灰" % [
			Economy.work_income(), Economy.class_fee(), Economy.class_gain()])


func _test_app_switch() -> void:
	print("[3] 手机屏：App 切换与二级列表")
	_phone.open_app("res://scenes/apps/boss.tscn")
	_check("打开了 Boss直聘", _phone.current_app_path(), "res://scenes/apps/boss.tscn")
	# App 自己的返回按钮在这层**不该露出来**：它写的是原来那位宿主的去向
	# （Boss 上写着「返回微信」），而本屏自己有「← 桌面」+ 左栏 App 列表两层导航
	_check("没有露出 App 自己的返回按钮", _phone._current._back_button.visible, false)
	_check("空右侧的提示收起来了", _phone._empty_hint.visible, false)
	# 再开一个：不该叠第二层，前一个要被换掉
	_phone.open_app("res://scenes/apps/wechat.tscn")
	_check("同一时刻只开一个 App", _phone.current_app_path(), "res://scenes/apps/wechat.tscn")
	# 微信交出了自己的联系人列表 → 左栏从「App 列表」换成二级列表
	_check("微信交出了二级列表", _phone._sidebar != null, true)
	_check("左栏换成了二级列表", _phone._sidebar_host.visible, true)
	_check("App 列表让位了", _phone._app_list.visible, false)
	_check("顶上写明这是谁的列表", _phone._caption.text.contains("微信"), true)
	_check("有回全列表的路", _phone._column_back.visible, true)
	# 【左栏那个框的大小不该跟着 App 变】微信的联系人面板自带 `custom_minimum_size = 460`
	# （它当年是整屏 App，自己说了算），搬过来必须让位给左栏 —— 否则比宿主宽，
	# 多出来的部分被隔壁面板盖住，看着就是「左边的手机框被遮了」（提提报的）
	_check("外来列表自带的最小宽度被清掉了", _phone._sidebar.custom_minimum_size, Vector2.ZERO)
	_check("宿主会裁掉以后任何越界", _phone._sidebar_host.clip_contents, true)
	# 切进哪个 App，周围那圈（状态栏下边线 / 两块面板的描边 / 左栏标题）就用它的品牌色
	_check("开着微信用微信绿", _phone._accent(), UiPalette.WECHAT)

	# 【再点同一个 App 不该变成「收起」】原来这里写的是 toggle：玩家按过「← 全部」
	# 之后再点它，第一次点击被当成关闭 —— 看到的现象是「点一次没进去，得点两次」
	var keep: String = _phone.current_app_path()
	_phone.open_app(keep)
	_check("再点同一个 App 仍然是它", _phone.current_app_path(), keep)

	_phone._current.cancelled.emit()
	_check("返回后 App 关掉了", _phone.current_app_path(), "")
	_check("左栏换回 App 列表", _phone._app_list.visible, true)
	_check("二级列表被收掉了（它已经不归 App 管）", _phone._sidebar, null)
	_check("没开 App 时退回通用强调色", _phone._accent(), UiPalette.ACCENT)

	# 【「← 全部」= 离开当前 App】只换左栏的话，右栏还停在聊天那一层 —— 两边对不上（真踩过）
	_phone.open_app("res://scenes/apps/boss.tscn")
	_check("开着简历拿来用它自己的青", _phone._accent(), UiPalette.BOSS)
	_phone._current._select_company("A")
	_phone._current._first_msg_delay = 0.0
	_phone._current._open_chat()
	_check("Boss 聊天开着", _phone._current.chat_open(), true)
	var unlocked_before: int = _game.state.unlocked_hr.size()
	_phone._column_back.pressed.emit()
	_check("「← 全部」把 App 一起关了", _phone.current_app_path(), "")
	_check("右栏回到空态", _phone._empty_hint.visible, true)
	_check("话没说完就退了：不算解锁", _game.state.unlocked_hr.size(), unlocked_before)
	print("   一次只开一个；交得出二级列表的 App 会把左栏换掉")


## App 之间互相顶开（微信 → 简历拿来 / 录像机），以及录像机录完的回程。
##
## 【为什么要单独一条】这两个入口原来是把对方**嵌在自己的右栏里**，切 App 这一层根本不参与；
## 改成整屏切换之后，「是谁顶开的」「录完回哪儿」都成了手机屏身上的新状态 ——
## 而且它坏起来很安静（确实切过去了，只是回来时东西没了、或者回不来）。
func _test_app_jump() -> void:
	print("[3b] 手机屏：App 之间互相顶开 + 录像机的回程")
	var bus := root.get_node("EventBus")
	_game.new_game()
	_phone.open_app(WECHAT_SCENE)
	_check("先开着微信", _phone.current_app_path(), WECHAT_SCENE)

	# 微信 → 简历拿来：整屏切过去（不是塞进右栏）
	_phone._current._on_open_boss()
	_check("「去简历拿来」把手机屏切过去了", _phone.current_app_path(), BOSS_SCENE)
	_check("左栏换成它的公司列表", _phone._sidebar != null, true)
	_check("周围那圈换成它的青", _phone._accent(), UiPalette.BOSS)

	# 回微信 → 再走一次录像机
	_phone.open_app(WECHAT_SCENE)
	_check("回到微信", _phone.current_app_path(), WECHAT_SCENE)
	_phone._current._on_open_recorder()
	_check("「去录像机」也是整屏切过去", _phone.current_app_path(), RECORDER_SCENE)
	_check("录像机不交二级列表，左栏继续列 App", _phone._app_list.visible, true)
	_check("它自己的「返回」露出来了（在这一层它就是「上一步」）",
			_phone._current._back_button.visible, true)

	# 录像机点「确认」→ 表情包进状态 → 手机屏把玩家送回微信
	var clip := _flat_clip()
	bus.recorder_finished.emit(clip)
	_check("录完自动回到微信（不用自己从列表里找）", _phone.current_app_path(), WECHAT_SCENE)
	_check("表情包已进状态", _game.pending_clip(), clip)
	_check("回微信后附件就在那儿", _phone._current._pending, clip)
	_check("周围那圈跟着回到微信绿", _phone._accent(), UiPalette.WECHAT)

	# 录像机的「返回」= 回顶开它的那个 App，而不是回 App 列表
	_phone._current._on_open_recorder()
	_check("又切到录像机", _phone.current_app_path(), RECORDER_SCENE)
	_phone._current.cancelled.emit()
	_check("它的「返回」回到来路", _phone.current_app_path(), WECHAT_SCENE)

	# 「← 全部」仍然是「离开这个 App」，与上面那条是两回事
	_phone._column_back.pressed.emit()
	_check("「← 全部」回 App 列表", _phone.current_app_path(), "")
	_check("左栏换回 App 列表", _phone._app_list.visible, true)
	print("   整屏切换 + 录完回程都是通的；「返回」是上一步、「← 全部」是离开")


## 左栏的未读角标。
##
## 【守两件事】1) **只有微信会亮** —— 别的 App 没有「等着你处理」的东西，硬凑数字会
## 训练玩家忽略角标；2) **靠信号刷新** —— 微信活在右栏，它那边变了不会自己走到左栏来。
func _test_badges() -> void:
	print("[3c] 手机屏：左栏未读角标（只有微信 / 靠信号亮）")
	var bus := root.get_node("EventBus")
	_game.new_game()
	# 【基准不写死】新开局自带那位初始联系人的未读（`unlock_hr` 会塞进 `unread_hrs`），
	# 所以下面全部按「相对基准加减」断言，避免把开局的礼貌性未读当成回归。
	var base := _badge_number(WECHAT_SCENE)
	_check("角标数字就是状态里的未读数", base, _game.wechat_badge_count())
	_check("亮着的角标只有微信一个", _badge_visible_count(), 1 if base > 0 else 0)
	for path: String in _phone._app_badges:
		if path != WECHAT_SCENE:
			_check("非微信的 App 不亮（%s）" % path.get_file(), _badge_visible(path), false)

	# 周初事件：微信 +1
	_game.state.add_pending_event(&"ev_badge")
	bus.week_event_offered.emit(&"ev_badge")
	_check("来了件周初事件：多 1", _badge_number(WECHAT_SCENE), base + 1)
	_check("别的 App 仍然不跟风亮", _badge_visible_count(), 1)

	# 新解锁一位 HR = 一条未读
	_game.unlock_hr("A")
	_check("多了一位没点开过的 HR：再多 1", _badge_number(WECHAT_SCENE), base + 2)

	# 【`mark_hr_read` 没有信号】玩家读完那一刻左栏可能正被二级列表盖着 ——
	# 回到列表时必须重算，否则那个数会一直挂到下一次事件。
	_game.mark_hr_read("A")
	_phone.open_app(RECORDER_SCENE)
	_phone._current.cancelled.emit()
	_check("读过那位 HR：回到列表就少 1", _badge_number(WECHAT_SCENE), base + 1)

	# 事件回完 → 退回基准（基准为 0 时角标整个隐藏，不是显示 0）
	_game.state.remove_pending_event(&"ev_badge")
	bus.week_event_resolved.emit(&"ev_badge", 0)
	_check("事回完了：回到基准", _badge_number(WECHAT_SCENE), base)

	# 换掉整个状态（开新局 / 读档）也不许留着上一局的数字
	_game.state.add_pending_event(&"ev_badge")
	bus.week_event_offered.emit(&"ev_badge")
	_check("再排一件：又 +1", _badge_number(WECHAT_SCENE), base + 1)
	_game.new_game()
	_phone._show_app_list()
	_check("开新局后回到新一局的基准", _badge_number(WECHAT_SCENE), _game.wechat_badge_count())
	print("   只有微信亮；事件 / HR / 换局都由信号驱动，读完 HR 回列表时补算")


## 角标上的数字。**隐藏时返回 0** —— 断言里「0」同时意味着「没亮」。
func _badge_number(scene: String) -> int:
	var dot: Panel = _phone._app_badges.get(scene, null)
	if dot == null or not dot.visible:
		return 0
	return int((dot.get_node("Num") as Label).text)


func _badge_visible(scene: String) -> bool:
	var dot: Panel = _phone._app_badges.get(scene, null)
	return dot != null and dot.visible


func _badge_visible_count() -> int:
	var n := 0
	for path: String in _phone._app_badges:
		if _badge_visible(path):
			n += 1
	return n


## 平脸表情包（A 厂的一票否决是「不许有怒」，平脸必过）——
## 这里只是当个「录像机录好了」的载荷，判定不在这条链上
func _flat_clip() -> Clip:
	var c := Clip.new()
	for i in c.frame_count():
		c.frames[i] = Clip.Frame.new(
				PartLibrary.by_id("eyes_00"), PartLibrary.by_id("mouth_00"),
				PartLibrary.by_id("brows_00"), null)
	return c


func _test_end_day() -> void:
	print("[4] 「结束今天」在非周末不结算")
	_game.state.day = 3
	_app._refresh_all()
	# 【注意这里不能写 :=】`_game` 是 Node 类型的局部变量（不是 Game 单例的静态类型），
	# 从它身上调方法的返回值推不出类型，GDScript 会直接报解析错误
	var res: Dictionary = _game.end_day()
	_check("非周末不结算", res.get("settled", false), false)
	_check("但日期推进了", _game.day(), 4)
	_check("非周末不弹浮层", _app._report, null)
	# 从手机壳的按钮走一遍，确认路径一致
	_app._on_end_day_pressed()
	_check("按钮路径也推进了", _game.day(), 5)
	print("   只有第 7 / 14 / 21 天才结算")


func _test_week_settle() -> void:
	print("[5] 周末结算：浮层、《有瓜有戏》、翻篇")
	# 造一部本周播出的戏（直接写履历 —— 走完整投递要拼表情包、解锁 HR，与本节无关）
	_game.state.day = 6
	_game.state.record_submission(true, {
		"company_code": "B", "role_tier": RoleRequirement.Tier.LEAD, "match_rate": 0.85,
		"play_title": "测试剧", "role_name": "测试角色",
		"payout": Economy.payout(CompanyLibrary.by_code("B"),
				CompanyLibrary.by_code("B").role_of(RoleRequirement.Tier.LEAD)),
		"acting_gain": 5,
	})
	_game.state.day = 7
	_app._refresh_all()
	_app._on_end_day_pressed()

	_check("周末弹出了结算浮层", _app._report != null, true)
	# 【这道闸门很要紧】浮层的脚本一旦解析失败，手机壳拿到的就只是个空 Control：
	# 下面每一句 `_app._report.report` 都会报错中断当前函数，而 GDScript 的报错
	# **不会让测试变红** —— 它会安静地跳过剩下的断言，最后打印「全部通过」。
	# 所以这里必须先确认脚本真的挂上了。
	if not _app._report.has_method("_build_week"):
		_failures.append("结算浮层的脚本没加载起来 —— 后面的断言全都不可信")
		return
	var report: Dictionary = _app._report.report
	_check("周报结算了 1 部", (report["plays"] as Array).size(), 1)
	_check("周报有头条", (report["headlines"] as Array).size() >= 1, true)
	_check("头条没有残留的【xx】字段",
			MailComposer.find_leftovers(String((report["headlines"] as Array)[0])), [] as Array[String])
	_check("结算后也扣了房租", report["rent"], Economy.rent())

	# 翻篇
	var next_day: int = _game.day()
	_app._report._next_button.pressed.emit()
	_check("翻篇关掉了浮层", _app._report, null)
	_check("本周投递计数清零", _game.state.submissions_this_week, 0)
	_check("日期已进入下一周", next_day, 8)
	print("   头条：《%s》" % String((report["headlines"] as Array)[0]))


func _test_full_run_to_ending() -> void:
	print("[6] 三周跑满 → 结局 → 再来一局")
	# 第 1 周已在上一节结算过，这里把第 2 周走完
	_game.state.day = 2 * GameState.DAYS_PER_WEEK
	_game.state.ap_left_today = GameState.AP_PER_DAY
	_app._refresh_all()
	_app._on_end_day_pressed()
	_check("第 2 周结算弹层", _app._report != null, true)
	_check("第 2 周的报纸没有结局页", _app._report.report.get("ending", {}).is_empty(), true)
	_app._report._next_button.pressed.emit()
	_check("普通周翻一次就关掉", _app._report, null)

	# 第 3 周：这一期的报纸带结局
	_game.state.day = 3 * GameState.DAYS_PER_WEEK
	_game.state.ap_left_today = GameState.AP_PER_DAY
	_app._refresh_all()
	_app._on_end_day_pressed()
	_check("第 3 周弹出报纸", _app._report != null, true)
	_check("三周后本局结束", _game.state.finished, true)
	_check("判出了结局", String(_game.ending_id()).is_empty(), false)
	_check("周报存了三期", _game.state.reports.size(), 3)
	_check("什么都没演 → 平庸", String(_game.ending_id()), "mediocre")
	_check("报纸上带着结局", _app._report.report.get("ending", {}).is_empty(), false)

	# 有一期带结局的报纸时，桌面的「结束今天」要变成「看结局」
	_app._refresh_all()
	_check("结束后卡片标题变成「看结局」",
			String(_app._cards["end"]["title"].text), "看结局")
	_check("结束后的提示换了", _app._plan_hint.text.contains("三周结束"), true)

	# 第一次按：翻到结局页，报纸**不关**（玩家还要读结局）
	_app._report._next_button.pressed.emit()
	_check("翻到了结局页", _app._report._on_ending, true)
	_check("结局页标题是结局名", _app._report._title.text, "结局 ｜ 平庸")
	_check("结局页有内容", _app._report._content.get_child_count() > 0, true)

	# 第二次按：再来一局
	_app._report._next_button.pressed.emit()
	_check("再来一局：本局重开", _game.state.finished, false)
	_check("再来一局：回到第 1 天", _game.day(), 1)
	_check("再来一局：金钱回到初始值", _game.money(), BalanceLibrary.data().init_money)
	_check("再来一局：浮层关掉了", _app._report, null)
	_check("再来一局：周报清空", _game.state.reports.size(), 0)
	# 开新局 / 读档必须把打开的 App 一起清掉，
	# 否则打完一局再开新局，屏幕上还挂着上一局的聊天窗口
	# （改版后 App 在手机屏里，所以这条改测手机屏）
	_phone.open_app("res://scenes/apps/wechat.tscn")
	_check("先打开一个 App", _phone.current_app_path() != "", true)
	_game.new_game()
	_check("开新局把 App 也清掉了", _phone.current_app_path(), "")
	print("   三周跑满 → 平庸 → 再来一局，状态与界面一起归零")


## 读档读到一个「已经打完」的存档时，桌面也要认得出来。
## 【为什么要单独测】这条路径上的周报是**存档版**（没有 before / after 快照、
## 也没有逐条作品的履历原文），界面必须能优雅退化而不是显示一堆空白或直接报错。
func _test_finished_save() -> void:
	print("[7] 读到一个已结束的存档")
	_game.state.finished = true
	_game.state.ending_id = &"mediocre"
	_game.state.reports.append({
		"week": GameState.WEEKS, "day": GameState.TOTAL_DAYS,
		"headlines": ["测试头条"], "plays": [],
		"payout": 0, "rent": Economy.rent(),
		"ending": {"id": &"mediocre", "name": "平庸", "implemented": true,
				"text": "测试文案", "condition": "兜底"},
	})
	_app._refresh_all()
	_check("结束状态下卡片变成「看结局」",
			String(_app._cards["end"]["title"].text), "看结局")
	_check("结束状态下提示换了", _app._plan_hint.text.contains("三周结束"), true)
	_check("结束后打工卡仍被拦", _card("work").disabled, true)

	_app._on_end_day_pressed()
	_check("「看结局」能打开存档版周报", _app._report != null, true)
	if _app._report == null:
		return
	_check("存档版周报带着结局", _app._report.report.get("ending", {}).is_empty(), false)
	# 没有 before/after 快照时不该崩，也不该显示 0
	_app._report._next_button.pressed.emit()
	_check("从存档版也能翻到结局页", _app._report._on_ending, true)
	_check("结局页读到存档里的文案", _app._report._title.text, "结局 ｜ 平庸")
	_app._report._next_button.pressed.emit()
	_check("再来一局把造出来的状态也清掉", _game.state.finished, false)
	print("   存档版周报缺快照与履历原文，界面必须能退化")


## 存档的另一半 —— 决策 1.1 只写了「每周结算自动存档」，
## 但**存了却没人读，那份存档就是死的**。这一节守三件事：
## 读得回来、读档会让界面重画、没有存档时不许假装成功。
func _test_save_load() -> void:
	print("[8] 存档与读档")
	var path := "user://test_shell_save.json"
	# 造一个「一眼看不出是开局」的状态
	_game.new_game()
	_game.state.day = 12
	_game.state.money = 777
	_game.state.acting = 19
	_game.state.ps5_paid = 270
	_game.state.work_this_week = 2
	_game.state.class_this_week = 1
	_game.state.unlock_hr("C")
	_game.save_to(path)
	_check("存档文件写出来了", FileAccess.file_exists(path), true)

	# 开新局把一切抹掉，再读回来
	_game.new_game()
	_check("开新局后回到第 1 天", _game.day(), 1)
	_check("开新局后金钱归位", _game.money(), BalanceLibrary.data().init_money)

	_check("读档成功", _game.load_from(path), true)
	_check("读回了天数", _game.day(), 12)
	_check("读回了金钱", _game.money(), 777)
	_check("读回了演技", _game.acting(), 19)
	_check("读回了 PS5 进度", _game.state.ps5_paid, 270)
	_check("读回了本周打工计数", _game.state.work_this_week, 2)
	_check("读回了本周上课计数", _game.state.class_this_week, 1)
	_check("读回了已解锁的 HR", _game.is_hr_unlocked("C"), true)

	# 读档对界面来说和开新局一样：状态整个换了，界面必须照着重画
	_check("读档后状态跟着变", _app._money_label.text, "777")
	_check("读档后天数跟着变", _app._day_label.text, "12")

	# 【这一条守的是"开机读档"那条路径】`Game._ready()` 在 `new_game()` **之前**调
	# `load_from()`，那一刻 `state` 还是 null。往 null 上调 `from_save_dict()` 会报错，
	# 而报错只中断当前函数 → `load_from()` 返回 null → `_ready()` 转身开新局，
	# 表现就是**读档静默失效**（Day 2 真踩过）。所以这里把 state 打成 null 再读一次。
	_game.state = null
	_check("state 为 null 时也能读档（开机那条路径）", _game.load_from(path), true)
	_check("读完 money 对得上", _game.money(), 777)
	_check("读完 day 对得上", _game.day(), 12)

	# 没有存档时不许假装成功 —— 否则调用方会以为读到了一个空局
	var missing := "user://definitely_not_here.json"
	_check("文件不存在时读档失败", _game.load_from(missing), false)
	_check("读档失败不会把 state 弄丢", _game.state != null, true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("   存 → 清 → 读，属性与周计数都回来了；界面由 state_reset 驱动重画")


## 重开按钮：一局二十一天，误触一下进度全没 —— 所以必须两步确认。
func _test_restart_button() -> void:
	print("[9] 重开一局：两步确认")
	# 【存档的保护不在这儿】重开会把新局写进 `user://save.json`（那是产品行为），
	# 但整条链的备份与还原来在 `_run_all` 的头尾统一做 —— 这一节以前只保护自己，
	# 结果前面几节写入的那份测试局照样留在真存档里（见 `_run_all` 里那段注释）。
	_game.new_game()
	_app._restart_armed_at = 0
	_game.state.day = 9
	_game.state.money = 500
	_app._refresh_all()
	_check("常态下按钮写着「重开一局」", _app._restart_button.text, "重开一局")

	_app._on_restart_pressed()
	_check("第一次按不会重开", _game.day(), 9)
	_check("第一次按只是进入待确认", _app._restart_button.text.contains("再点一次"), true)
	_check("待确认时按钮变红", _app._restart_button.get_theme_color("font_color"), UiPalette.DANGER)

	_app._on_restart_pressed()
	_check("第二次按才真的重开（回到第 1 天）", _game.day(), 1)
	_check("第二次按把钱也清了", _game.money(), BalanceLibrary.data().init_money)
	_check("重开后按钮回到常态", _app._restart_button.text, "重开一局")
	_check("重开会把新局写进存档（否则下次打开会被读回上一局）",
			FileAccess.file_exists("user://save.json"), true)

	# 待确认窗口过期之后，再按一次只应该**重新进入待确认**
	_game.state.day = 15
	_app._refresh_restart()
	_app._restart_armed_at = Time.get_ticks_msec() - (int(_app.RESTART_CONFIRM_MS) + 100)
	_app._on_restart_pressed()
	_check("窗口过期后按一下不会重开", _game.day(), 15)
	_check("过期后重新进入待确认", _app._restart_button.text.contains("再点一次"), true)
	# 被打断的待确认也会自己退掉（_refresh_restart 顺手清理）
	_app._restart_armed_at = Time.get_ticks_msec() - (int(_app.RESTART_CONFIRM_MS) + 100)
	_app._refresh_restart()
	_check("过期的待确认会被刷新顺手退掉", _app._restart_button.text, "重开一局")

	print("   第一次按只是进入待确认，5 秒内再按才真重开 —— 二十一天的进度不能一键清掉")


## 周初事件是不是真的挂在周循环上
##
## 【为什么在整局测试里再验一遍】`EventScheduler` 自己在 `test_events.gd` 里已经验透了，
## 这一节验的是**接线**：`new_game` / `end_day` 有没有在正确的那一天去排事件，
## 上一周没理会的那条会不会溜进下一周。这类问题在纯逻辑测试里看不出来 ——
## 它坏的是「谁在什么时候调了它」。
func _test_week_event() -> void:
	print("[10] 周初事件跟着周循环排")
	_game.new_game()
	var w1: EventData = _game.pending_event()
	_check("开新局当天就有事件在等", w1 != null, true)
	if w1 == null:
		return
	_check("排的是第 1 周的那条", String(w1.id), "class_discount")

	# 整周不理会 → 进第 2 周时它要作废，而不是赖着不走
	_game.state.day = GameState.DAYS_PER_WEEK
	_game.state.ap_left_today = GameState.AP_PER_DAY
	var res: Dictionary = _game.end_day()
	_check("第 1 周结算了", res.get("settled", false), true)
	_check("没理会也记了一笔", int(_game.state.event_history[0]["choice"]), -1)
	_check("进了第 2 周的第一天", _game.day(), GameState.DAYS_PER_WEEK + 1)
	var w2: EventData = _game.pending_event()
	_check("第 2 周排上了自己的事件", w2 != null, true)
	if w2 == null:
		return
	_check("不是第 1 周那条赖着", String(w2.id), "bad_film_offer")

	# 这一周处理掉之后，不该再冒出第二件
	var paid := 0 if w2.options[0].ap_cost > 0 else 1
	var free := 1 - paid
	_game.state.ap_left_today = 0
	_check("行动点花光时收费选项被拦",
			_game.event_option_block_reason(paid).is_empty(), false)
	_check("免费选项不受影响",
			_game.event_option_block_reason(free), "")
	_game.state.ap_left_today = GameState.AP_PER_DAY
	var r: Dictionary = _game.resolve_event(free)
	_check("回话成功", r.get("ok", false), true)
	_check("处理完不再有待处理事件", _game.pending_event(), null)
	_check("本周不会再来第二件", EventScheduler.pick(_game.state, 2), null)
	print("   周初排事件、错过作废、一周只演一出，都挂在周循环上")


## 桌子：跨屏跳转
##
## 【为什么要单独测】「去投递」那张卡在日历上，但微信住在手机屏里 ——
## 这一跳跨了两个屏，只有桌子知道该怎么走。不测的话，坏起来的表现是
## 「点了没反应」，而两屏各自的测试都是绿的。
func _test_desk_jump() -> void:
	print("[11] 桌子：跨屏跳转（日历「去投递」→ 手机的微信）")
	var desk: Node = load("res://scenes/main/desk_screen.tscn").instantiate()
	root.add_child(desk)
	# 笔记本热区必须接上抄录手册 —— 它曾经是 `target_scene = null`（点了没反应），
	# 而三个二级页各自的测试都是绿的，谁也不会发现
	var book_hot: Node = desk.get_node("Hotspots/HotspotNotebook")
	_check("笔记本热区接上了抄录手册",
			String(book_hot.target_scene.resource_path), "res://scenes/main/notebook_screen.tscn")

	desk._on_activated(desk.get_node("Hotspots/HotspotCalendar"))
	_check("先打开了日历", desk._open.name, "CalendarScreen")
	# 日历自己**不该**开微信（App 归手机屏管），它只发请求
	var requests: Array[String] = []
	desk._open.open_app_requested.connect(func(p: String) -> void: requests.append(p))
	desk._open._on_submit_pressed()
	_check("日历把「去投递」发成了请求", requests, ["res://scenes/apps/wechat.tscn"] as Array[String])
	# 桌子接住请求：关掉日历、开手机、再把微信打开
	_check("桌子把玩家送进了手机屏", desk._open.name, "PhoneScreen")
	_check("并且直接打开了微信", desk._open.current_app_path(), "res://scenes/apps/wechat.tscn")
	# 手机上返回桌面要能回到桌子
	desk._open.cancelled.emit()
	_check("从手机返回后桌面空了", desk.has_open_screen(), false)

	# 笔记本走同一条路：桌子打开 → 露出返回 → 回去
	desk._on_activated(book_hot)
	_check("打开抄录手册", desk._open.name, "NotebookScreen")
	_check("二级页露出了返回桌面", desk._open._back_button.visible, true)
	desk._open.cancelled.emit()
	_check("从抄录手册返回后桌面空了", desk.has_open_screen(), false)

	# GM 控制台（只在 debug 构建里挂）：指令必须真的改到状态，而不只是打印一行
	# 【按节点名找，不写类型】那个脚本故意没有 `class_name`（见它文件头）；
	# 而且 `--script` 里的主脚本编译早于 autoload，引用它会连带编译失败。
	var gm: Node = desk.get_node_or_null("GmConsole")
	_check("调试构建里挂上了 GM 控制台", gm != null, true)
	if gm != null:
		_test_gm_commands(gm)
	desk.queue_free()
	print("   日历发请求 → 桌子切屏 → 手机开微信；返回能回桌面")
	print("   GM：force 能塞事件、resolve 的效果真的落账、seed 能换抽签")


## GM 指令的最小回归：**事件塞得进去、选项效果真的落账**。
## 【为什么值得测】控制台是开发期唯一的「单条事件」入口；它悄悄坏掉的话，
## 内容同学会以为「这条事件没效果」，其实是指令写错了。
func _test_gm_commands(gm: Node) -> void:
	_game.new_game()
	# 新开局可能已经排着一条（开局即周一），所以数量都对着基准算
	var pending_before: int = _game.state.pending_events.size()
	gm.call("_run", "event force friend_loan")
	_check("GM 把事件挂上了", _game.state.pending_events.has("friend_loan"), true)
	_check("只多这一条", _game.state.pending_events.size(), pending_before + 1)
	gm.call("_run", "event force no_such_event")
	_check("瞎写代号不会挂上东西", _game.state.pending_events.size(), pending_before + 1)

	var money_before: int = _game.money()
	gm.call("_run", "event resolve friend_loan 0")
	# friend_loan 的 [0] 借出 100：钱少 100，事件从待处理里摘掉
	_check("GM 选完，钱真的少了 100", _game.money(), money_before - 100)
	_check("事件已从待处理摘掉", _game.state.pending_events.has("friend_loan"), false)
	_check("其它挂着的不受影响", _game.state.pending_events.size(), pending_before)
	_check("履历里记下了这次选择",
			String(_game.state.event_history.back().get("event", "")), "friend_loan")

	gm.call("_run", "event force friend_loan")
	gm.call("_run", "event clear")
	_check("GM 能清空挂着的事件", _game.state.pending_events.size(), 0)

	var acting_before: int = _game.acting()
	gm.call("_run", "acting +2")
	_check("数值指令走 add_*：演技 +2", _game.acting(), acting_before + 2)
	# 【信号那条必须验】直接写 `state.money` 界面不会变；走 `add_money` 才会重画 HUD
	gm.call("_run", "money 777")
	_check("GM 改的钱已同步到手机顶栏", _phone._money_label.text, "777 元")


## 抄录手册：二级页（贴纸）→ 三级页（单页笔记）→ × 回来。
##
## 【为什么要测】三级页是所有便签共用的一个壳：`_open_note(index)` 少填一行，
## 玩家点第二张贴纸看到的还是第一篇 —— 这种错肉眼要连点四次才发现。
func _test_notebook() -> void:
	print("[12] 抄录手册：贴纸 → 单页笔记 → × 回本子")
	var book: Node = load("res://scenes/main/notebook_screen.tscn").instantiate()
	root.add_child(book)

	var stickers := 0
	for child: Node in book.get_node("Page").get_children():
		if String(child.name).begins_with("Sticker_"):
			stickers += 1
	_check("贴纸数量 == 便签条数", stickers, NoteLibrary.count())
	_check("一进来笔记页是关着的", book._note_layer.visible, false)

	# 走真实按钮：贴纸就是 Button，`pressed` 通了才算接上
	book.get_node("Page/Sticker_0").pressed.emit()
	_check("点第一张贴纸：笔记页开了", book._note_layer.visible, true)
	_check("标题是第一条", book._note_title.text, String(NoteLibrary.NOTES[0]["title"]))
	_check("正文按行排好（8 行）", book._note_body.text.split("\n").size(), 8)

	# × 是三级页唯一的出口（手机上没 Esc）
	book._close_button.pressed.emit()
	_check("× 之后回到笔记本", book._note_layer.visible, false)
	_check("关掉后记的索引也清了", book._note_index, -1)

	book.get_node("Page/Sticker_3").pressed.emit()
	_check("点第四张：换的是第四篇", book._note_title.text, String(NoteLibrary.NOTES[3]["title"]))
	book._close_button.pressed.emit()
	_check("再按 × 又收回本子", book._note_layer.visible, false)
	book.call("_open_note", 99)
	_check("越界不崩、也不亮", book._note_layer.visible, false)

	book.queue_free()
	print("   四张贴纸各开各的；× 只收三级页，不退出笔记本")


## 音效：**按钮是自动挂的**，事件音是信号接的。
##
## 【为什么要测】headless 的音频驱动是 Dummy，听不见也看不出来 ——
## 少接一条信号，或者 `STREAMS` 里写了个错路径，只有真机上才会发现"怎么没声"。
## 这里用 `Sfx.played_log` 把「信号 → 播放」这一步钉住。
func _test_sfx() -> void:
	print("[13] 音效：按钮全局挂钩 + 事件音")
	var sfx: Node = root.get_node_or_null("Sfx")
	_check("Sfx autoload 在", sfx != null, true)
	if sfx == null:
		return
	_check("7 条素材都配上了", sfx.STREAMS.size(), 7)
	var broken := 0
	for code: StringName in sfx.STREAMS:
		if sfx.STREAMS[code] == null:
			broken += 1
	_check("没有加载失败的音", broken, 0)

	# 【全局挂钩】新按钮加进树就该自动有两条音，页面作者什么都不用写
	var b := Button.new()
	root.add_child(b)
	_check("按钮自动挂上点击音", b.pressed.get_connections().size(), 1)
	_check("按钮自动挂上悬浮音", b.mouse_entered.get_connections().size(), 1)
	b.queue_free()

	var bus := root.get_node("EventBus")
	sfx.played_log.clear()
	bus.money_changed.emit(120, 20)
	_check("加钱：响一声", sfx.played_log.back(), &"money_up")
	sfx.played_log.clear()
	bus.money_changed.emit(100, -20)
	_check("扣钱：不响（否则像赚了）", sfx.played_log.size(), 0)

	sfx.played_log.clear()
	bus.acting_changed.emit(5, 2)
	_check("演技涨：响一声", sfx.played_log.back(), &"skill_up")

	sfx.played_log.clear()
	bus.audition_submitted.emit({})
	_check("投递出去：发送成功音", sfx.played_log.back(), &"mail_sent")

	# 【回信音不跟信号走】它现在由微信在"打字"到位、气泡出现那一刻自己播
	# （见 `wechat_app._finish_typing`）—— 这里钉住的是"核心层不再提前响"，
	# 否则发给玩家的会是先一声叮、几秒后才看到回信。
	sfx.played_log.clear()
	bus.hr_replied.emit("A", true, {})
	_check("HR 回信不再由信号提前响", sfx.played_log.size(), 0)

	sfx.played_log.clear()
	bus.broadcast_published.emit(1, [])
	_check("没有头条的周报不响", sfx.played_log.size(), 0)
	bus.broadcast_published.emit(2, [{"title": "x"}])
	_check("有头条：围脖提示音", sfx.played_log.back(), &"weibo")
	print("   按钮自动挂点击/悬浮；钱·演技·投递·围脖由信号触发（回信音等气泡出现）")


func _snapshot_save() -> Dictionary:
	const P := "user://save.json"
	if not FileAccess.file_exists(P):
		return {"existed": false}
	return {"existed": true, "bytes": FileAccess.get_file_as_bytes(P)}


func _restore_save(snap: Dictionary) -> void:
	const P := "user://save.json"
	if bool(snap.get("existed", false)):
		var f := FileAccess.open(P, FileAccess.WRITE)
		f.store_buffer(snap["bytes"])
		f.close()
	elif FileAccess.file_exists(P):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(P))
