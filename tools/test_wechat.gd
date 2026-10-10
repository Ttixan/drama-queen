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
const SAVE_PATH := "user://test_wechat_save.json"

var _failures: Array[String] = []
var _checks := 0
var _app                       ## 故意不标类型：要动态访问场景脚本的成员
var _game                      ## Game autoload（动态调用）
var _bus                       ## EventBus autoload（动态调用）


func _initialize() -> void:
	_app = load(SCENE).instantiate()
	root.add_child(_app)
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
	_check("公司数", CompanyLibrary.count(), 5)
	_check("联系人行数", _app._rows.size(), 5)
	_check("开局零解锁", _game.state.unlocked_hr.size(), 0)
	_check("开局不选中任何联系人（避免「能点但发不出去」）", _app._current, null)

	print("")
	print("[2] 核心层校验（未解锁 / 未拼完 / 行动点）")
	_game.new_game()
	_check("new_game 后没有解锁任何 HR", _game.state.unlocked_hr.size(), 0)

	var a: CompanyData = CompanyLibrary.by_code("A")
	var extra := a.role_of(RoleRequirement.Tier.EXTRA)
	var flat := _flat_clip()

	var locked: Dictionary = _game.submit_audition(flat, a, extra)
	_check("未解锁的 HR 投不出去", locked["rejected"], true)
	_check("未解锁的原因说清楚了", "Boss直聘" in locked["fail_reasons"][0], true)
	_check("被拦下不扣行动点", _game.state.ap_left_today, GameState.AP_PER_DAY)
	_check("被拦下不记履历", _game.state.history.size(), 0)

	_game.unlock_hr("A")
	_check("解锁后可以私聊", _game.is_hr_unlocked("A"), true)
	_check("重复解锁返回 false", _game.unlock_hr("A"), false)

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
	print("[4] 真实链路：去 Boss直聘 解锁 → 回来投递")
	_game.new_game()
	_app._refresh_all()
	_check("重开后没有联系人", _app._current, null)

	# 从零开始：微信里打开 Boss直聘（上个版本这里是个 DEV_UNLOCK_ALL 作弊开关）
	_app._on_open_boss()
	_check("Boss直聘 被嵌进来了", _app._overlay != null, true)
	_check("子页面盖上来时「去 Boss直聘」置灰", _app._go_boss_button.disabled, true)
	var boss = _app._overlay
	boss._select_company("A")   # 模拟玩家点开 A 的招聘页
	_check("看过招聘页后 A 的 HR 解锁了", _game.is_hr_unlocked("A"), true)
	_check("Boss 里那一行也标成已联系", String(boss._row_labels["A"]["state"].text), "已联系")
	_check("回车键之外的老路：不能再靠 DEV 开关白送", _game.state.unlocked_hr.size(), 1)

	_app._close_overlay()
	_check("子页面关掉了", _app._overlay, null)
	_check("回来时自动打开了刚加上的 HR", _app._current.code, "A")
	_check("「去 Boss直聘」重新可用", _app._go_boss_button.disabled, false)
	_check("还没有附件", _app._pending, null)
	_check("没有附件时发送按钮置灰", _app._send_button.disabled, true)

	# 走真实握手：打开内嵌录像机 → 它 emit recorder_finished → 微信接住
	_app._on_open_recorder()
	_check("录像机被嵌进来了", _app._overlay != null, true)
	_check("录像机打开时「去录像机」置灰", _app._open_recorder_button.disabled, true)
	var clip := _flat_clip()
	_bus.recorder_finished.emit(clip)
	_check("微信接住了表情包", _app._pending, clip)
	_check("录像机已关闭", _app._overlay, null)
	_check("「去录像机」重新可用", _app._open_recorder_button.disabled, false)
	_check("有附件后发送按钮解禁", _app._send_button.disabled, false)

	_app._role_buttons[RoleRequirement.Tier.EXTRA].button_pressed = true
	_check("选中了龙套", _app._role.tier, RoleRequirement.Tier.EXTRA)
	_check("公司门槛显示正确", _app._requirement_label.text.contains("演技门槛 0"), true)

	var bubbles_before: int = _app._chat_log.get_child_count()
	_app._send_button.pressed.emit()
	_check("附件被消耗（一次性）", _app._pending, null)
	_check("落了一条履历", _game.state.history.size(), 1)
	_check("花了 1 点行动点", _game.state.ap_left_today, GameState.AP_PER_DAY - 1)
	var entry: Dictionary = _game.state.history[0]
	_check("履历记了公司", entry.get("company_code", ""), "A")
	_check("履历记了剧名", String(entry.get("play_title", "")).is_empty(), false)
	_check("履历记了角色名", String(entry.get("role_name", "")).is_empty(), false)
	_check("履历存了回信原文（读档才能还原聊天记录）",
			(entry.get("mail", {}) as Dictionary).get("text", "").is_empty(), false)
	_check("聊天气泡增加了 2 条（投递 + 回信）",
			_app._chat_log.get_child_count(), bubbles_before + 2)

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

	_finish()


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
