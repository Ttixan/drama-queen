extends SceneTree
## 微信投递链路验证 —— headless 跑，驱动真实控件
##
##   godot --headless --path <项目> --script res://tools/test_wechat.gd
##
## 【这是 M1 验收门的那条断言】「拼 3 帧表情包 → 微信私聊 HR 投递 → 出通过/失败」。
## 这里把整条链子连起来跑：录像机发信号 → 微信收到表情包 → 选中角色 → 发送
## → 判定 → 回信 → 表情包被消耗 → 履历落账。任何一环断开，这个测试都会红。
##
## 【为什么用 root.get_node("Game") 而不是直接写 Game】
## autoload 是**运行期**注册的全局标识符，而 `--script` 模式下这个脚本在 autoload
## 注册之前就被编译了 —— 直接写 `Game.foo()` 会编译失败（Identifier not found: Game）。
## 场景脚本没这个问题（它们晚一步编译），所以生产代码照常直接用 `Game`。
##
## 【注意】不能只看 UI —— 核心层的校验（未解锁 / 周上限 / 行动点）也必须单独钉，
## 因为那几条是玩法规则，界面只是它的一个入口。

const SCENE := "res://scenes/apps/wechat.tscn"
const BOSS_SCENE := "res://scenes/apps/boss.tscn"
const RECORDER_SCENE := "res://scenes/minigame/recorder.tscn"
const SAVE_PATH := "user://test_wechat_save.json"

var _failures: Array[String] = []
var _checks := 0
var _app                       ## 故意不标类型：要动态访问场景脚本的成员
var _game                      ## Game autoload（动态调用）
var _bus                       ## EventBus autoload（动态调用）
## 微信发出的「换一个 App」请求（`open_app_requested`）
var _jumps: Array[String] = []


## 手机屏切 App 时会把上一个 App 销毁、回来时重建 —— 这里照做一遍。
## 【为什么要重建】「去录像机」是**整屏切走**，微信那一刻不在了；屏幕里那个附件
## 只能从状态里取回来。这条测试因此天然守住「切走再回来，东西还在不在」。
## 【为什么是 queue_free 而不是 free】`free()` 是当场销毁 —— 本 App 里挂在
## `await get_tree().process_frame` 上的那一句（`_scroll_chat_to_bottom`）会带着
## 一个已经没了的实例恢复，引擎报 "Resumed function after await, but class instance is gone"。
## 真正的宿主（`phone_screen._close_app`）用的也是 `queue_free`，这里照它来。
func _rebuild_app() -> void:
	_app.queue_free()
	_app = load(SCENE).instantiate()
	root.add_child(_app)
	_app.open_app_requested.connect(_on_jump)


func _on_jump(scene_path: String) -> void:
	_jumps.append(scene_path)


func _initialize() -> void:
	_app = load(SCENE).instantiate()
	root.add_child(_app)
	_app.open_app_requested.connect(_on_jump)
	process_frame.connect(_run_all, CONNECT_ONE_SHOT)


func _run_all() -> void:
	print("")
	print("=== 微信投递链路验证 ===")
	print("")

	_game = root.get_node_or_null("Game")
	_bus = root.get_node_or_null("EventBus")
	_check("Game autoload 可用", _game != null, true)
	_check("EventBus autoload 可用", _bus != null, true)
	# 【注意别拿 _current 当就绪探针】开局「谁都没选中」是**正常状态**（五家还没解锁）。
	# 用 @onready 的节点引用判断 _ready 有没有跑完才靠谱。
	if _game == null or _bus == null or _app._send_button == null:
		print("❌ 环境没起来，后面的断言没有意义")
		quit(1)
		return

	print("[1] 开局：五家 HR 全锁（还没逛过 Boss直聘）")
	# 【为什么先真的开一局】`Game._ready()` 会试着读 `user://save.json`（决策 1.1），
	# 而那正是真机上那份存档的目录 —— 本机可能躺着上一局（你自己玩的，或别的链写的）。
	# 「开局」这几条要有意义，就得真的从开局起，不能拿环境里的状态当开局。
	_game.new_game()
	_check("公司数", CompanyLibrary.count(), 5)
	_check("联系人行数", _app._rows.size(), 5)
	_check("开局零解锁", _game.state.unlocked_hr.size(), 0)
	_check("开局不选中任何联系人（避免「能点但发不出去」）", _app._current, null)
	# 【名单上只放真的加上了的人】开局五家全锁 —— 五行都该藏着，
	# 并留一句告诉玩家去哪儿加人（提提点名：没加上的 HR 不该占着名单）
	_check("没解锁的 HR 一行都不显出来", _visible_rows(), 0)
	_check("提示写清了去哪儿加人", _app._contacts_hint.text.contains("简历拿来"), true)

	print("")
	print("[2] 核心层校验（未解锁 / 未拼完 / 行动点）")
	_game.new_game()
	_check("new_game 后没有解锁任何 HR", _game.state.unlocked_hr.size(), 0)

	var a: CompanyData = CompanyLibrary.by_code("A")
	var extra := a.role_of(RoleRequirement.Tier.EXTRA)
	var flat := _flat_clip()

	var locked: Dictionary = _game.submit_audition(flat, a, extra)
	_check("未解锁的 HR 投不出去", locked["rejected"], true)
	_check("未解锁的原因说清楚了", "简历拿来" in locked["fail_reasons"][0], true)
	_check("被拦下不扣行动点", _game.state.ap_left_today, GameState.AP_PER_DAY)
	_check("被拦下不记履历", _game.state.history.size(), 0)

	_game.unlock_hr("A")
	_check("解锁后可以私聊", _game.is_hr_unlocked("A"), true)
	_check("重复解锁返回 false", _game.unlock_hr("A"), false)
	_check("加上之后名单上就多了这一位", _visible_rows(), 1)

	var bad: Dictionary = _game.submit_audition(Clip.new(), a, extra)
	_check("空表情包投不出去", bad["rejected"], true)
	_check("空表情包的原因说清楚了", "没拼完" in bad["fail_reasons"][0], true)

	_game.state.ap_left_today = 0
	var no_ap: Dictionary = _game.submit_audition(flat, a, extra)
	_check("没行动点投不出去", no_ap["rejected"], true)
	_check("没行动点的原因说清楚了", "行动点" in no_ap["fail_reasons"][0], true)

	print("")
	print("[3] 周上限：一周最多 4 次")
	_game.new_game()
	_game.unlock_hr("A")
	var accepted := 0
	for i in GameState.MAX_SUBMIT_PER_WEEK:
		_game.state.ap_left_today = 1
		var r: Dictionary = _game.submit_audition(flat, a, extra)
		if not r.get("rejected", false):
			accepted += 1
	_check("前 4 次都投出去了", accepted, GameState.MAX_SUBMIT_PER_WEEK)
	_check("本周计数", _game.state.submissions_this_week, GameState.MAX_SUBMIT_PER_WEEK)
	_game.state.ap_left_today = 1
	var fifth: Dictionary = _game.submit_audition(flat, a, extra)
	_check("第 5 次被周上限拦下", fifth["rejected"], true)
	_check("周上限的原因说清楚了", "本周投递次数已用完" in fifth["fail_reasons"][0], true)
	# 周上限只在「跨过第 7 天」时才清零，所以要把日期推到周末再 advance 一次
	_game.state.day = GameState.DAYS_PER_WEEK
	var crossed: bool = _game.state.advance_day()
	_check("第 7 天之后 advance_day 报告跨周", crossed, true)
	_check("跨周后本周计数清零", _game.state.submissions_this_week, 0)

	print("")
	print("[4] 真实链路：去「简历拿来」解锁 → 回微信投递")
	_game.new_game()
	_app._refresh_all()
	_check("重开后没有联系人", _app._current, null)

	# 【这两个入口现在是「整屏切走」】微信只发一个场景路径，由手机屏换 App ——
	# 对方不再被嵌进右栏（内嵌那一套已经删了）
	_app._on_open_boss()
	_check("「去简历拿来」发的是整屏切换请求", _jumps.size(), 1)
	_check("请求的是简历拿来", _jumps[0] if not _jumps.is_empty() else "", BOSS_SCENE)
	_jumps.clear()

	# 手机屏收到请求会真的把简历拿来开起来（两台是同一层的 App，不是父子）——
	# 这里直接建一个驱动它，简历拿来自己的链路在 test_boss 里
	var boss = load(BOSS_SCENE).instantiate()
	root.add_child(boss)
	boss._select_company("A")   # 模拟玩家点开 A 的招聘页
	# 【别再设 `_chat_step`】那个值现在每次进聊天都会被复位（Boss 的 [11] 就是这条）——
	# 想一次放完要走这个专门的开关。
	boss._fast_forward = true
	boss._open_chat()           # 再点 HR 说上两句 —— **解锁那一步在聊完之后**
	_check("跟 HR 聊完后 A 的 HR 解锁了", _game.is_hr_unlocked("A"), true)
	_check("Boss 里那一行也标成已联系", String(boss._row_labels["A"]["state"].text), "已联系")
	_check("回车键之外的老路：不能再靠 DEV 开关白送", _game.state.unlocked_hr.size(), 1)
	_check("聊完它会请手机屏切回微信", boss._chat_to_wechat.visible, true)
	boss.queue_free()

	# 回微信 = 手机屏重建一个实例（原来那个已经跟着切 App 销毁了）
	#
	# 【注意这里有个优先级】开新局排了第 1 周的事件，而「周初事件必须先被看见」
	# 是 GDD 阶段 1 的要求 —— 所以重建后的微信**先打开事件那一条会话**，
	# 而不是他刚才在聊的 HR。这条先单独钉住，免得以后有人以为那是 bug。
	_rebuild_app()
	var ev_now = _game.pending_event()
	_check("开新局排出了第 1 周的事件（下面两条才有意义）", ev_now != null, true)
	if ev_now != null:
		_check("还有事没回时，回微信先给你看那条会话",
				String(_app._event_speaker), String(ev_now.speaker))
	_check("事件会话开着时不选中任何 HR", _app._current, null)

	# 料理掉事件再回一次 —— 这时才该落在「刚加上的那位」上
	_game.state.pending_event = &""
	_check("刚加上的那位被记进了状态", _game.focus_hr(), "A")
	_rebuild_app()
	_check("没有待办事件时，落回刚加上的那位", _app._current.code, "A")
	_check("两个入口都能点（没有子页面盖在上面了）", _app._go_boss_button.disabled, false)
	_check("还没有附件", _app._pending, null)
	_check("没有附件时发送按钮置灰", _app._send_button.disabled, true)

	# 【加完人就有聊天记录】这段该从「我是谁」开始（提提点名），而不是一上来只有系统提示
	var co := CompanyLibrary.by_code("A")
	_check("第一条是 HR 自报家门",
			_chat_text(0), "我是%s的%s" % [co.display_name, co.hr_name])
	_check("第二条是我回自己的名字", _chat_text(1), "我是" + _player_name())

	# 【气泡的形状与配色】对方在左（灰底、头像在最左）、自己在右（绿底、头像在最右）——
	# 同一个聊天里只允许这两种底色，不再按成败 / 哪条会话换色
	var rows := _bubble_rows()
	_check("开头就是两条气泡（不是系统提示）", rows.size() >= 2, true)
	if rows.size() >= 2:
		# 一行 = 【头像 + 气泡】两件，外加一个撑开的空控件把整行顶到该去的那一边。
		# 【为什么连控件类型一起钉】这两处正是最容易写反的地方：
		# 头像挂错侧 → 对方的头像跑到自己气泡右边；撑开的控件一律挂行尾 →
		# 自己的气泡被推到左边（看着就是「右边没靠边」）
		_check("对方那行：头像在最左、气泡紧跟其后",
				"%s/%s" % [rows[0].get_child(0).get_class(), rows[0].get_child(1).get_class()],
				"Panel/PanelContainer")
		_check("对方那条：气泡是中性灰", _bubble_bg(rows[0]), UiPalette.PANEL_SOFT)
		_check("自己那行：气泡 + 头像，最前面是撑开的空控件（把气泡顶到右边）",
				"%s/%s/%s" % [
					rows[1].get_child(0).get_class(),
					rows[1].get_child(1).get_class(),
					rows[1].get_child(2).get_class(),
				], "Control/PanelContainer/Panel")
		_check("自己那条：气泡是微信绿", _bubble_bg(rows[1]), UiPalette.WECHAT)
		_check("绿底上压的是深色字（白字在绿底上发虚）",
				_bubble_text_color(rows[1]), UiPalette.INK)
		_check("短消息的气泡跟着文字收窄，不是一条通栏",
				_card_of(rows[0]).get_combined_minimum_size().x < 300.0, true)

	# 「去录像机」同样是整屏切走。**录完的回程归手机屏管**（它记着是谁顶开的），
	# 而表情包由核心层接住 —— 微信那一刻不在场，所以这两件事都不能指望它自己做
	_app._on_open_recorder()
	_check("「去录像机」也是整屏切换请求", _jumps.size(), 1)
	_check("请求的是录像机", _jumps[0] if not _jumps.is_empty() else "", RECORDER_SCENE)
	var clip := _flat_clip()
	_bus.recorder_finished.emit(clip)
	_check("表情包落进了状态（微信不在场也不会丢）", _game.pending_clip(), clip)

	_rebuild_app()
	_check("重建后附件从状态里取回来", _app._pending, clip)
	# 【附件到位 ≠ 能发】提提 10-16 的新流程：还得先在聊天里挑一个档位、等 HR 把剧本发过来
	_check("有附件、但还没剧本时发送键仍然是灰的", _app._send_button.disabled, true)
	_check("聊天里 HR 在问「试哪类角色」", _chat_contains("试哪类角色"), true)
	_check("三个档位的选项都摆出来了", _app._tier_buttons.size(), co.roles.size())
	_check("底部那排一个都没预选（预选了反倒要点两下才走得通）", _app._role, null)
	_check("composer 的状态行说的是还没拿到剧本",
			_app._status_line.text.contains("剧本"), true)

	# 底部那排档位 = 要一份这一档的剧本（和聊天里那三个按钮是同一件事）
	_app._role_buttons[RoleRequirement.Tier.EXTRA].button_pressed = true
	await _settle()
	_check("选中了龙套", _app._role.tier, RoleRequirement.Tier.EXTRA)
	_check("公司门槛显示正确", _app._requirement_label.text.contains("演技门槛 0"), true)
	_check("要到了剧本：状态里记下了这一档",
			int(_game.hr_script_of("A").get("tier", -1)), RoleRequirement.Tier.EXTRA)
	_check("剧本发过来了（聊天里出现那个 .docx）", _chat_contains(".docx"), true)
	_check("我先开口要了龙套这一档", _chat_contains("我想试龙套"), true)
	_check("有剧本之后发送键才解禁", _app._send_button.disabled, false)

	_app._send_button.pressed.emit()
	await _settle()
	_check("附件被消耗（一次性）", _app._pending, null)
	_check("状态里那份也清掉了（下次进微信不会又冒出来）", _game.pending_clip(), null)
	_check("落了一条履历", _game.state.history.size(), 1)
	# 【闸门】下面每一条都要读 entry，履历为空时中断会让这一节静默变绿（还曾把整轮测试吊死）
	if _game.state.history.is_empty():
		print("❌ 没有履历，本节后面的断言无从谈起")
		_finish()
		return
	_check("花了 1 点行动点", _game.state.ap_left_today, GameState.AP_PER_DAY - 1)
	_check("这一份剧本用掉了 —— 状态里空了", _game.hr_script_of("A"), {})
	var entry: Dictionary = _game.state.history[0]
	_check("履历记了公司", entry.get("company_code", ""), "A")
	_check("履历记了剧名", String(entry.get("play_title", "")).is_empty(), false)
	_check("履历记了角色名", String(entry.get("role_name", "")).is_empty(), false)
	_check("履历存了回信原文（读档才能还原聊天记录）",
			(entry.get("mail", {}) as Dictionary).get("text", "").is_empty(), false)
	# 【为什么不数「气泡 +2」】投递 + 回信那一整段现在是**从履历重建**出来的
	# （`_on_send` 后面跟着 `_rebuild_chat`），日志里同时还要把「这一部拍完、
	# HR 接着问下一部」摆进去 —— 数条数不如直接看内容在不在。
	_check("聊天记录里有投递那一条", _chat_contains("【投递】"), true)
	_check("回信原文铺在聊天记录里", _chat_has(String(entry["mail"]["text"])), true)
	_check("投完 HR 接着问下一部要试哪类角色", _chat_contains("试哪类角色"), true)
	_check("下一个档位的选项又摆出来了", _app._tier_buttons.size(), co.roles.size())

	var mail: Dictionary = entry["mail"]
	# 拿**填好的**期望主题去比，不是拿带《【剧名】》的原始模板 ——
	# A 公司的成功/失败主题不同（「试镜通过」/「试镜结果」），所以这一条同时证明了
	# 「用了成败对应的那封信」和「剧名确实填进去了」
	var expect_subject: String = MailLibrary.for_company("A").letter(entry.get("passed", false)) \
			.subject.replace("【剧名】", String(entry["play_title"]))
	_check("回信是成败对应的那封信，且剧名已填", mail.get("subject", ""), expect_subject)
	_check("回信里没有漏网的方块",
			str(MailComposer.find_leftovers(String(mail.get("text", "")))), "[]")
	_check("回信里出现了剧名", String(mail.get("text", "")).contains(entry["play_title"]), true)

	print("    回信：")
	for line: String in String(mail.get("text", "")).split("\n"):
		if not line.strip_edges().is_empty():
			print("      " + line)

	print("")
	print("[5] 回信成败与判定一致（换个必定失败的组合）")
	_game.new_game()
	_game.unlock_hr("A")
	# A 公司的一票否决是「全程不允许出现怒」→ 塞怒件进去必然失败
	var res: Dictionary = _game.submit_audition(_clip_with("eyes_02", "mouth_07", "brows_04"), a, extra)
	_check("怒脸在 A 厂被拒", res["passed"], false)
	var fail_subject: String = MailLibrary.for_company("A").fail.subject \
			.replace("【剧名】", String(res["casting"]["剧名"]))
	_check("拒信是失败模板", res["mail"]["subject"], fail_subject)
	_check("拒信也填满了字段",
			str(MailComposer.find_leftovers(String(res["mail"]["text"]))), "[]")

	print("")
	print("[6] 存档往返：解锁状态 + 聊天记录原文")
	_check("存档成功", _game.save_to(SAVE_PATH), OK)
	var before_unlocked := str(_game.state.unlocked_hr)
	var before_mail := String((_game.state.history[0] as Dictionary)["mail"]["text"])
	_game.new_game()
	_check("重开后解锁清空", _game.state.unlocked_hr.size(), 0)
	_check("读档成功", _game.load_from(SAVE_PATH), true)
	_check("解锁状态还原", str(_game.state.unlocked_hr), before_unlocked)
	_check("履历条数还原", _game.state.history.size(), 1)
	_check("回信原文逐字还原",
			String((_game.state.history[0] as Dictionary)["mail"]["text"]), before_mail)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

	print("")
	print("[7] 周初事件：自动打开会话 + 二选一")
	_game.new_game()
	# 开新局时第 1 周的事件已经排好了（`Game.new_game` 里排的）
	var ev: EventData = _game.pending_event()
	_check("开新局就排出了第 1 周的事件", ev != null, true)
	# 【闸门】后面每条都要读 ev 的字段，为 null 时中断会让这一节静默变绿
	if ev == null:
		print("❌ 没有事件可验，本节跳过")
		_finish()
		return

	# 【为什么按代价找下标而不是写死 0/1】占位文案里是「买 / 不买」，
	# 但狗牙完全可以把收费项写在后面。按 ap_cost 找才测的是规则本身。
	var paid := -1
	var free := -1
	for i in ev.options.size():
		if ev.options[i].ap_cost > 0:
			paid = i
		else:
			free = i
	_check("占位事件里有一个收费项和一个免费项", paid >= 0 and free >= 0, true)
	if paid < 0 or free < 0:
		_finish()
		return

	_check("事件会话被自动打开了", String(_app._event_speaker), String(ev.speaker))
	_check("开着事件会话时不选中任何 HR", _app._current, null)
	_check("事件说话人出现在联系人列表里", _app._event_rows.has(ev.speaker), true)
	_check("两个选项按钮都在", _app._event_buttons.size(), 2)
	_check("HR 那三排 composer 藏起来了", _app._role_row.visible, false)
	_check("事件那排 composer 露出来了", _app._event_row.visible, true)
	_check("聊天记录里有开场白", _chat_has(String(ev.intro)), true)
	_check("按钮上带着代价与收益",
			String(_app._event_buttons[paid].text).contains(ev.options[paid].label), true)

	# 行动点花光之后：收费那个灰掉，免费那个照旧 —— 这一周不会被卡死
	_game.state.ap_left_today = 0
	_app._refresh_all()
	_check("没行动点时收费选项灰掉", _app._event_buttons[paid].disabled, true)
	_check("免费选项仍然可点", _app._event_buttons[free].disabled, false)
	_check("灰掉的原因写在状态行里", _app._event_status.text.contains("行动点"), true)

	# 点免费那个（GDD 的「拒」那一侧）
	_game.state.ap_left_today = 1
	_app._refresh_all()
	var ap_before: int = _game.ap_left()
	var money_before: int = _game.money()
	_app._event_buttons[free].pressed.emit()
	_check("处理完之后不再有待处理事件", _game.pending_event(), null)
	_check("聊天记录里出现了我的回话", _chat_has(String(ev.options[free].label)), true)
	_check("聊天记录里出现了对方的回话", _chat_has(String(ev.options[free].reply)), true)
	_check("免费选项没花钱", _game.money(), money_before)
	_check("行动点没被扣", _game.ap_left(), ap_before)
	# 【回完不删人】名单是「你和谁聊过」的记录，不是待办清单（提提点名）——
	# 原来回完那人就从名单上消失，玩家想回头看那天的对话就找不到了
	_check("回完之后那个人还留在名单上", _app._event_rows.has(ev.speaker), true)
	_check("他的状态字改成了回过的样子", _app._speaker_state(ev.speaker), "已回过")
	_check("但这条会话还开着，回完还能回头看", _app._is_event_chat(), true)

	# 事件会话里的气泡走**同一套**配色：他说的灰、我说的绿 —— 不再另开一套青
	var ev_rows := _bubble_rows()
	_check("事件会话里他说的也是灰气泡", _bubble_bg(ev_rows[0]), UiPalette.PANEL_SOFT)
	_check("我回的那句是绿气泡", _bubble_bg(ev_rows[1]), UiPalette.WECHAT)
	_check("他后面那句还是灰的（不是绿也不是红）",
			_bubble_bg(ev_rows[ev_rows.size() - 1]), UiPalette.PANEL_SOFT)
	_check("本周不会再来第二件", _game.pending_event(), null)
	_check("处理完事件那排按钮收起来了", _app._event_buttons[paid].visible, false)

	# 切回 HR 会话，composer 要换回来
	_game.unlock_hr("A")
	_app._select_company("A")
	_check("切回 HR 后角色那排回来了", _app._role_row.visible, true)
	_check("切回 HR 后附件那排回来了", _app._attach_row.visible, true)
	_check("切回 HR 后事件那排藏起来", _app._event_row.visible, false)
	print("   自动打开 → 门槛预演 → 二选一 → 切回 HR，全程走通")

	print("")
	print("[8] 剧本：HR 问档位 → 发 .docx → 玩家点开看（提提 10-16）")
	_game.new_game()
	_game.unlock_hr("A")
	# 【先把演技提上去】A 厂三个档位的门槛是 0 / 5 / 15 —— 不上演技就测不出「换档」
	_game.state.acting = 30
	# 开新局排了第 1 周的事件，不料理掉的话微信会先开事件那条会话（见 [4] 的说明）
	_game.state.pending_event = &""
	_rebuild_app()
	_check("落在刚加上的那位身上", _app._current.code, "A")

	# 一进门：HR 先问，三个档位摆出来；还没有剧本，发送键是灰的
	_check("HR 先问试哪类角色", _chat_contains("试哪类角色"), true)
	_check("三个档位都摆出来了", _app._tier_buttons.size(), 3)
	_check("状态里还没有剧本", _game.hr_script_of("A"), {})
	_check("发送键灰着", _app._send_button.disabled, true)
	_check("底部档位没有预选", _app._role, null)

	# 点「配角」→ HR 发一份配角视角的剧本过来
	var sup := _tier_button(RoleRequirement.Tier.SUPPORTING)
	_check("聊天里有「配角」那个选项", sup != null, true)
	if sup == null:
		_finish()
		return
	sup.pressed.emit()
	# 【必须等一帧】重建聊天是 queue_free 旧气泡 —— 不等的话下面按下标读气泡
	# 会读到上一轮那几条（`_settle` 的说明）
	await _settle()
	var hand: Dictionary = _game.hr_script_of("A")
	_check("状态里记下了这一档", int(hand.get("tier", -1)), RoleRequirement.Tier.SUPPORTING)
	var doc := ScriptLibrary.for_play_tier(int(hand.get("play", 0)), int(hand.get("tier", -1)))
	_check("抽到的是三份剧本里某一本的配角视角", doc != null, true)
	if doc == null:
		print("❌ 没有配角剧本 —— tools/gen_scripts.gd 跑过了吗")
		_finish()
		return
	_check("抽中的那份档位就是配角", doc.tier, RoleRequirement.Tier.SUPPORTING)
	_check("文件名是 剧本标题-角色名·档位名.docx",
			doc.file_name(), "%s-%s·配角.docx" % [doc.play_title, doc.role_name])
	_check("聊天里出现了这个文件名", _chat_contains(doc.file_name()), true)
	_check("我先开口要了配角这一档", _chat_contains("我想试配角"), true)
	_check("我还回了一句", _chat_contains("我先看剧本"), true)
	_check("底部档位跟着选中了配角", _app._role.tier, RoleRequirement.Tier.SUPPORTING)
	# 【卡点已经越过剧本那一关】这一节没拼表情包，所以发送键还是灰的 ——
	# 但拦它的理由应该换成了「还没拼表情包」，而不是「还没拿到剧本」
	_check("拦住它的理由换成了「还没拼表情包」",
			_app._status_line.text.contains("表情包"), true)
	_check("最后一条气泡是我那句（文件卡不算气泡）",
			_chat_text(_bubble_rows().size() - 1), "好，我先看剧本。")
	# 【顺序：邀请 → 我开口 → 他发】提提 10-16 点出来的两件事：
	# 邀请那句要**留着**（聊天记录是「聊过什么」，不是「还剩什么待办」），
	# 而「我先说试配角」要排在「这是《…》的桂香剧本」前面。
	# 数气泡：0/1 是自我介绍，2 是他邀请我挑档，3 是我要的档，4 才是他发的
	_check("邀请选角色那句话留在记录里", _chat_text(2).contains("试哪类角色"), true)
	_check("顺序是「我先说试哪一档」", _chat_text(3), "我想试配角。")
	_check("紧接着才是 HR 发剧本的那句", _chat_text(4).contains(doc.play_title), true)

	# 文件卡：整张可点，点开铺出橘色的剧本页
	var card := _script_card()
	_check("文件卡在聊天记录里（是 Button，整张可点）", card is Button, true)
	_check("卡上画着那个「W」图标", _has_label(card, "W"), true)
	# 【W 要落在蓝底正中间】提提一眼看出来过「偏了」—— 量的是几何中心对几何中心。
	# 蓝底是 PanelContainer（会把子节点铺满），W 靠两个 alignment 居中；
	# 自己摆锚点那种写法在布局跑完之后才会看出偏，所以这条必须等布局跑完再量。
	var icon := _find_named(card, "WordIcon")
	var mark := _find_named(card, "WordMark")
	_check("蓝底是个 56×56 的 PanelContainer", icon is PanelContainer, true)
	if icon != null and mark != null:
		_check("W 的横向中心 = 蓝底的横向中心",
				absf(mark.position.x + mark.size.x / 2.0 - icon.size.x / 2.0) < 0.5, true)
		_check("W 的纵向中心 = 蓝底的纵向中心",
				absf(mark.position.y + mark.size.y / 2.0 - icon.size.y / 2.0) < 0.5, true)
		# 【图标不能贴着卡片边】提提两次看出「太靠左」—— Button 不是容器，
		# 子节点不会自动让开 stylebox 的 content_margin，留白得显式给（见 CARD_PAD）
		var pad: float = icon.get_global_rect().position.x - card.get_global_rect().position.x
		_check("图标离卡片左边缘有留白（%d px）" % int(pad), pad >= 16.0, true)
	_check("剧本页默认关着", _app._script_overlay.visible, false)
	_app._open_script()
	_check("点开后铺出剧本页", _app._script_overlay.visible, true)
	_check("标题就是那个文件名", _app._script_title.text, doc.file_name())
	_check("副标题写了哪一本 / 哪一档 / 几场",
			_app._script_subtitle.text.contains(doc.tier_name()), true)
	_check("正文逐字就是那一份（原文照搬）", _app._script_text.text, doc.body)
	_check("正文里留着试镜批注", _app._script_text.text.contains("[试镜批注]"), true)
	_check("正文里留着拼贴标记", _app._script_text.text.contains("拼贴表情轮"), true)
	_check("剧本页盖在聊天区上（不是另开一个 App）",
			_app._script_overlay.get_parent().name, "BodyWrap")
	_check("聊天记录还在底下（只是被盖住）", _app._chat_log.get_child_count() > 0, true)
	_app._script_back_button.pressed.emit()
	_check("返回键关掉它，回到聊天", _app._script_overlay.visible, false)

	# 换档位 = 重新要一份（提提选的 B：每次投递前都要走一遍）。
	# 【换档走底部那排】聊天里那三个按钮**只在手上没剧本时才出现**（有剧本就摆文件卡了），
	# 所以换档是点底部那排 —— 两条路最后都进 `_pick_tier`
	_check("手上有剧本时，聊天里不再摆选项", _app._tier_buttons.size(), 0)
	_app._role_buttons[RoleRequirement.Tier.EXTRA].button_pressed = true
	_check("档位换成龙套了", int(_game.hr_script_of("A").get("tier", -1)), RoleRequirement.Tier.EXTRA)
	_check("手上那份也跟着换了", _app._role.tier, RoleRequirement.Tier.EXTRA)
	_check("剧本页还关着", _app._script_overlay.visible, false)

	# 同一档再要一次：不重抽（不然刚看过的内容白看了）
	var keep := str(_game.hr_script_of("A"))
	_app._pick_tier(RoleRequirement.Tier.EXTRA)
	_check("同一档再点不重抽", str(_game.hr_script_of("A")), keep)

	# 演技不够的档位在底部那排上不了台：灰掉并写明要多少演技 ——
	# 但**已经拿到手的剧本不会被收走**（那是他要来的东西，凭什么收）
	_game.state.acting = 0
	# 【走真实路径】真机上演技是在别的 App 里涨的，回微信时这个 App 是**重建**的 ——
	# `_select_company` 正是重建后必然走的那一步（它重摆底部那排按钮与聊天记录）
	_app._select_company("A")
	_check("演技掉回 0 后，配角那个按钮灰了",
			(_app._role_buttons[RoleRequirement.Tier.SUPPORTING] as Button).disabled, true)
	_check("按钮上写着要多少演技",
			String((_app._role_buttons[RoleRequirement.Tier.SUPPORTING] as Button).text).contains("演技"), true)
	_check("已经拿到手的剧本不会被收走", str(_game.hr_script_of("A")), keep)

	# 【一个档都够不着时不该摆选项】提提 10-16：三个按钮全灰着摆出来的话，
	# 玩家只会一遍遍点 —— 干脆先不出现，只留一句说清差什么。
	# B 厂的门槛是 3，演技 0 时它的三个档位一个都够不着（A 厂不一样：龙套档 0 就能上）
	_game.unlock_hr("B")
	_app._select_company("B")
	await _settle()   # 同上：等 A 家那几条被真的丢掉，免得下面按内容查时串台
	_check("够不着任何档位时不摆选项", _app._tier_buttons.size(), 0)
	_check("也不问「试哪类角色」", _chat_contains("试哪类角色"), false)
	_check("但留了一句说清为什么", _chat_contains("演技"), true)
	_check("发送键当然也是灰的", _app._send_button.disabled, true)
	print("   问档位 → 我先开口 → 他发 .docx → 点开看 → 换档重抽，全程走通")

	_finish()


## 聊天里那个「试镜 N 档」的按钮。**每次重建聊天都是新对象**，所以按名字现找。
## 【为什么不存下标】按钮是按 `_current.roles` 的顺序建的，换一家公司顺序就可能变
func _tier_button(tier: int) -> Button:
	for b: Button in _app._tier_buttons:
		if b.name == "Tier_%d" % tier:
			return b
	return null


## HR 发过来的那张文件卡（名字固定在 `_file_card` 里）
func _script_card() -> Button:
	return _find_named(_app._chat_log, "ScriptCard") as Button


## 按名字递归找节点 —— 卡片那几个部件都是脚本建的，没有 @onready 引用
func _find_named(root: Node, node_name: String) -> Node:
	for child: Node in root.get_children():
		if child.name == node_name:
			return child
		var deep := _find_named(child, node_name)
		if deep != null:
			return deep
	return null


## 名单上真正露出来的 HR 行有几条（没加上的那些是 `visible = false`）
func _visible_rows() -> int:
	var n := 0
	for code: String in _app._rows:
		if (_app._rows[code] as Button).visible:
			n += 1
	return n


# ============================================================
# 气泡：形状（头像在哪一侧）与配色（左灰右绿）
# ============================================================
## 聊天区里的气泡行 —— 系统提示是 Label，气泡是 HBox（头像 + 气泡 + 撑开用的空控件）
## 【为什么要多判一次有没有气泡】HR 发的那份 `.docx` 文件消息也是个 HBox，
## 但它里面装的是按钮、不是 PanelContainer 气泡 —— 不排掉它，后面按下标取气泡全错位。
func _bubble_rows() -> Array:
	var out: Array = []
	for child: Node in _app._chat_log.get_children():
		if child is HBoxContainer and _card_of(child) != null:
			out.append(child)
	return out


## 一行里的气泡本身。**按类型找 PanelContainer**：另一侧那个头像也是 Panel，
## 按类型才分得开（这也顺带钉住了「一行里只有一个气泡」）
func _card_of(row: Node) -> PanelContainer:
	for node in row.get_children():
		if node is PanelContainer:
			return node
	return null


## 第 i 条气泡的文字
func _chat_text(i: int) -> String:
	var rows := _bubble_rows()
	if i >= rows.size():
		return "<没有第 %d 条气泡>" % i
	var card := _card_of(rows[i])
	if card == null or card.get_child_count() == 0:
		return "<这条气泡里没有文字框>"
	var margin := card.get_child(0) as MarginContainer
	if margin == null or margin.get_child_count() == 0:
		return "<这条气泡里没有文字>"
	return String((margin.get_child(0) as Label).text)


## 第 i 条气泡的底色
func _bubble_bg(row: Node) -> Color:
	var card := _card_of(row)
	if card == null:
		return Color(0, 0, 0, 0)
	var box := card.get_theme_stylebox("panel") as StyleBoxFlat
	return box.bg_color if box != null else Color(0, 0, 0, 0)


## 一条气泡里文字的颜色
func _bubble_text_color(row: Node) -> Color:
	var card := _card_of(row)
	if card == null or card.get_child_count() == 0:
		return Color(0, 0, 0, 0)
	var margin := card.get_child(0) as MarginContainer
	if margin == null or margin.get_child_count() == 0:
		return Color(0, 0, 0, 0)
	return (margin.get_child(0) as Label).get_theme_color("font_color")


## 主角的名字：**界面上那一句是从内容池读的**（`data/casting_pool.tres`），
## 所以这里也照同一条路读 —— 断了就说明「名字只有一个来源」这条破了
func _player_name() -> String:
	var pool := MailLibrary.casting_pool()
	return pool.player_name if pool != null else ""


# ============================================================
# 聊天记录里有没有出现某段文字（气泡是动态建的，只能按内容找）
# ============================================================
func _chat_has(text: String) -> bool:
	for child: Node in _app._chat_log.get_children():
		if _has_label(child, text):
			return true
	return false


func _has_label(node: Node, text: String) -> bool:
	if node is Label and (node as Label).text == text:
		return true
	for c: Node in node.get_children():
		if _has_label(c, text):
			return true
	return false


## 「这段话在不在聊天里」—— 子串匹配。
## 【和 `_chat_has` 的分工】那个是**整段相等**（比一整条正文，比如回信原文）；
## 想查「有没有这一句」用子串，省得把整句文案再抄一份到测试里（抄了就会漂）。
func _chat_contains(text: String) -> bool:
	for child: Node in _app._chat_log.get_children():
		if _label_contains(child, text):
			return true
	return false


func _label_contains(node: Node, text: String) -> bool:
	if node is Label and String((node as Label).text).contains(text):
		return true
	for c: Node in node.get_children():
		if _label_contains(c, text):
			return true
	return false


## 等一帧。`_rebuild_chat` 是用 `queue_free` 丢旧气泡的 —— **同一帧里它们还是子节点**，
## 不等一帧就按下标读气泡，读到的是上一轮那份（顺序断言会假红）。
func _settle() -> void:
	await process_frame
	await process_frame


# ============================================================
# 造表情包
# ============================================================
## 平脸：A 厂的一票否决是「不许有怒」，平脸必过
func _flat_clip() -> Clip:
	return _clip_with("eyes_00", "mouth_00", "brows_00")


func _clip_with(eye: String, mouth: String, brow: String) -> Clip:
	var c := Clip.new()
	for i in c.frame_count():
		c.frames[i] = Clip.Frame.new(
				PartLibrary.by_id(eye), PartLibrary.by_id(mouth),
				PartLibrary.by_id(brow), null)
	return c


# ============================================================
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
