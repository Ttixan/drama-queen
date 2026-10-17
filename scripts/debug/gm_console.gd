extends CanvasLayer
## 开发期 GM 控制台：**只为了「快速看到某条事件 / 某个选项的效果」**，不是玩法功能。
##
## 【为什么没有 `class_name`】`tools/*.gd` 是 `--script` 跑起来的：那份主脚本会在 autoload
## （`Game` / `EventBus`）注册**之前**编译。只要工具脚本里引用了这个类型，本脚本就会在那个
## 时间点被连带编译，而它满篇 `Game.state` —— 编译当场失败，之后一律报
## 「Nonexistent function 'new' in base 'GDScript'」。桌子用 `preload` 拿它即可，
## 加载时机在 autoload 之后，不存在这个问题。
##
## 【为什么需要它】随机事件看完一段文案要「结束今天」推进到周一、还要等调度器抽中，
## 而事件表有 4 条、选项各带一套数值 —— 靠手玩逐条核对等于把整局跑四五遍。
## 这里的指令让「排哪条 / 选哪一项 / 数值变成多少」都能一步到位。
##
## 【挂在哪】`desk_screen.gd` 的 `_ready()` 里按 `OS.is_debug_build()` 动态加进来：
## 不写进 `.tscn`（它是工具，不是场景的一部分），release 导出包里也不会存在。
## 用 `CanvasLayer` 是为了不受 Control 布局与 `overlay_parent` 的层级影响 ——
## 手机 / 日历不管开没开，它都盖在最上面。
##
## 【F1 开关】`_shortcut_input` 而不是 `_unhandled_input`：`phone_screen` 会把
## `ui_cancel` 消费掉（`get_viewport().set_input_as_handled()`），走 `_unhandled_input`
## 容易被它先吃掉。`_shortcut_input` 在 GUI 之前，稳定。
##
## 【为什么不直接改 state】`Game.state.money = 5000` 这种写法不发信号，界面不会刷新。
## 下面所有改数值的指令都走 `Game.add_*`（它自带夹值 + 发 `*_changed`）；
## 推进时间走 `Game.end_day()`（它才会排事件、发信号），不碰 `state.advance_day()`。

const SAVE_PATH := "user://save.json"
## GM 备份存档。放在 `user://` 下是为了和真存档同目录 —— 不会混进导出包。
const BACKUP_PATH := "user://save.gm.json"

## 输出区最多留多少行（超出从头丢）。GM 会打印一堆表，不设上限会把内存吃满。
const MAX_LINES := 400
const KEEP_LINES := 300

var _root: Control
var _panel: Panel
var _out: RichTextLabel
var _input: LineEdit
var _lines: PackedStringArray = []


func _ready() -> void:
	layer = 128
	# 暂停时（结算浮层 / 结局）也要能按 —— GM 常常正是在那一刻想看数据
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_panel.visible = false
	_print("GM 控制台就绪。F1 开合，help 看指令。")
	_print("现在：" + _state_line())


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 空白处不挡鼠标：面板收起时整层必须「不存在」，展开时也只挡面板那一块
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.offset_left = 24
	_panel.offset_top = -500
	_panel.offset_right = 24 + 880
	_panel.offset_bottom = -24
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel",
			UiPalette.panel(Color(0.08, 0.08, 0.1, 0.97), 14, 2, UiPalette.LINE))
	_root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)

	var title := Label.new()
	title.text = "GM 控制台"
	UiPalette.text(title, 20, UiPalette.ACCENT)
	head.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)

	var tip := Label.new()
	tip.text = "F1 收起 · 输出可选中复制"
	UiPalette.text(tip, 14, UiPalette.TEXT_DIM)
	head.add_child(tip)

	_out = RichTextLabel.new()
	_out.bbcode_enabled = false
	_out.scroll_following = true
	_out.selection_enabled = true
	_out.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_out.mouse_filter = Control.MOUSE_FILTER_STOP
	_out.add_theme_font_size_override("normal_font_size", 15)
	_out.add_theme_color_override("default_color", UiPalette.TEXT)
	_out.add_theme_stylebox_override("normal",
			UiPalette.panel(Color("1b1b20"), 10, 1, UiPalette.LINE))
	box.add_child(_out)

	_input = LineEdit.new()
	_input.placeholder_text = "输入指令后回车（help）"
	_input.clear_button_enabled = true
	_input.add_theme_font_size_override("font_size", 16)
	_input.add_theme_color_override("font_color", UiPalette.TEXT)
	_input.add_theme_color_override("caret_color", UiPalette.ACCENT)
	_input.add_theme_color_override("font_placeholder_color", UiPalette.TEXT_DISABLED)
	_input.add_theme_stylebox_override("normal",
			UiPalette.button(UiPalette.PANEL_SOFT, UiPalette.LINE, 2, 10, 0, 10))
	_input.add_theme_stylebox_override("focus",
			UiPalette.button(UiPalette.PANEL, UiPalette.ACCENT, 2, 10, 0, 10))
	_input.text_submitted.connect(_submit)
	box.add_child(_input)


# ============================================================
# 开合
# ============================================================
func _shortcut_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F1 or key.physical_keycode == KEY_F1:
		_set_open(not _panel.visible)
		get_viewport().set_input_as_handled()
		return
	# 开着的时候 Esc 只收面板 —— 否则会被手机屏当成「返回桌面」
	if _panel.visible and key.is_action_pressed("ui_cancel"):
		_set_open(false)
		get_viewport().set_input_as_handled()


func _set_open(open: bool) -> void:
	_panel.visible = open
	if open:
		# 打开就能直接打字：GM 的用法永远是「按 F1 → 敲一行 → 回车」
		_input.grab_focus()
		_input.caret_column = _input.text.length()
	else:
		_input.release_focus()


func _submit(text: String) -> void:
	var raw := text.strip_edges()
	_input.clear()
	if raw.is_empty():
		return
	_print("> " + raw)
	_run(raw)
	_input.grab_focus()


# ============================================================
# 指令分发
# ============================================================
func _run(raw: String) -> void:
	var parts := raw.split(" ", false)
	if parts.is_empty():
		return
	var head := parts[0].to_lower()
	var args := parts.slice(1)
	match head:
		"help", "?", "h":
			_help()
		"state", "s":
			_print(_state_line())
			_print("挂着的事件：%s" % _pending_ids())
		"event", "e":
			_cmd_event(args)
		"day", "d":
			_cmd_day(args)
		"seed":
			_cmd_seed(args)
		"money", "acting", "fame", "reputation":
			_cmd_stat(head, args)
		"backup":
			_cmd_backup()
		"restore":
			_cmd_restore()
		_:
			_print_err("不认识的指令：%s（help）" % head)


func _help() -> void:
	_print("event list                 事件表：代号 / 周次 / 说话人 / 门槛")
	_print("event pool                 本周计划、候选池、今天会不会出")
	_print("event show                 现在挂着的事件与两个选项的数值")
	_print("event force <代号>         硬塞一条（等价于调度器周一那条）")
	_print("event resolve [代号] [0|1] 直接选一项，看数值/履历效果")
	_print("event clear                清空挂着的事件（看角标消失）")
	_print("event reload               重新读 events.tres（改完文案不用重启）")
	_print("day [n]                    推进 n 天（走 end_day：会排事件、会结算）")
	_print("seed [n|random]            查看 / 改 event_seed（影响本周抽签）")
	_print("money|acting|fame|reputation [n]   查看；`n` 设为 n，`+n`/-n` 增减")
	_print("state                      当前天数 / 行动点 / 属性 / 挂着的事件")
	_print("backup / restore           备份 / 还原 user://save.json")


# ============================================================
# 事件
# ============================================================
func _cmd_event(args: PackedStringArray) -> void:
	var sub := args[0].to_lower() if args.size() > 0 else "show"
	var rest := args.slice(1)
	match sub:
		"show":
			_event_show()
		"list":
			_event_list()
		"pool":
			_event_pool()
		"force":
			_event_force(rest[0] if rest.size() > 0 else "")
		"resolve":
			_event_resolve(rest)
		"clear":
			_event_clear()
		"reload":
			EventLibrary.reload()
			_print("已重读 %s：%d 条" % [EventLibrary.PATH, EventLibrary.count()])
		_:
			_print_err("event 的子指令只有 list / pool / show / force / resolve / clear / reload")


func _event_list() -> void:
	var all := EventLibrary.all()
	if all.is_empty():
		_print_err("事件表是空的（%s 读不到？）" % EventLibrary.PATH)
		return
	_print("事件表：%d 条 —— %s" % [all.size(), EventLibrary.PATH])
	for e: EventData in all:
		var when := "任意周" if e.week == 0 else "第 %d 周" % e.week
		var flags := "可重复" if e.repeatable else "一次"
		var gate := ""
		if e.require_money_min >= 0:
			gate += " · 钱≥%d" % e.require_money_min
		if e.require_acting_min >= 0:
			gate += " · 演技≥%d" % e.require_acting_min
		_print("  %s %s · %s(%s) · 优先级 %d · %s%s" % [
				String(e.id).rpad(18), when, e.speaker_name, String(e.speaker),
				e.priority, flags, gate])


func _event_pool() -> void:
	if Game.state == null:
		_print_err("Game.state 还没有")
		return
	var st := Game.state
	var wk := Game.week()
	var plan := EventScheduler.week_plan(st, wk)
	var offered := EventScheduler.offered_count(st, wk)
	_print("第 %d 周计划：%s；今天第 %d 天" % [
			wk, _plan_text(plan), st.day_of_week()])
	_print("本周已排 %d 条（挂着的 %d + 履历里的）" % [offered, st.pending_events.size()])
	var pool := EventScheduler.candidates(st, wk)
	_print("候选池 %d 条（已按周次/出现过/本周说话人/门槛筛过）：" % pool.size())
	for e: EventData in pool:
		_print("  %s %s · 优先级 %d" % [String(e.id).rpad(18), e.speaker_name, e.priority])
	var today := EventScheduler.pick(st, wk)
	if today == null:
		_print("今天再推进一天：不出事（原因见上面的计划与候选池）")
	else:
		_print("今天再推进一天会出：%s · %s" % [String(today.id), today.speaker_name])


func _event_show() -> void:
	var evs := Game.pending_events()
	if evs.is_empty():
		_print("现在没有挂着的事件。想直接看内容：event force <代号>")
		return
	for e: EventData in evs:
		_print("%s · %s（%s）" % [String(e.id), e.speaker_name, String(e.speaker)])
		_print("  " + e.intro)
		_show_options(e)


func _show_options(e: EventData) -> void:
	for i in e.options.size():
		var o: EventOption = e.options[i]
		_print("  [%d] %s" % [i, o.label])
		_print("      AP -%d · 钱 %s · 演技 %s · 知名度 %s · 风评 %s" % [
				o.ap_cost, _signed(o.money), _signed(o.acting),
				_signed(o.fame), _signed(o.reputation)])
		if not o.note.is_empty():
			_print("      结果：" + o.note)


func _event_force(id_text: String) -> void:
	var id := StringName(id_text.strip_edges())
	if id == &"":
		_print_err("用法：event force <代号>（event list 看代号）")
		return
	var e := EventLibrary.find(id)
	if e == null:
		_print_err("事件表里没有「%s」—— 先 event list 看代号，或 event reload" % id_text)
		return
	if Game.state.pending_events.has(String(id)):
		_print("「%s」已经挂着了（event show 看它）" % id_text)
		return
	for other: EventData in Game.pending_events():
		if other.speaker == e.speaker:
			_print("注意：%s 本周已有一条挂着，两条会挤进微信里同一个会话" % e.speaker_name)
	# 【和 `Game._roll_week_event` 同一步】加进状态 + 广播 —— 微信开着时会当场刷出来，
	# 手机左栏的未读角标也靠这条信号亮。
	Game.state.add_pending_event(e.id)
	EventBus.week_event_offered.emit(e.id)
	_print("已挂上并广播：%s · %s" % [String(e.id), e.speaker_name])
	_print("  " + e.intro)
	_show_options(e)
	_print("去手机的微信里看（已经开着微信的话会立刻出现）")


func _event_clear() -> void:
	var n := Game.state.pending_events.size()
	Game.state.pending_events.clear()
	# 【为什么借 `day_advanced`】「清空」在游戏里不存在（真实路径是处理或周末作废），
	# 所以没有对应信号；`day_advanced` 目前唯一的听众是手机左栏的角标重算 ——
	# 借它一下，角标才不会留着一个不存在的未读。
	EventBus.day_advanced.emit(Game.state.day, Game.week())
	_print("清掉 %d 条挂着的事件（手机角标已重算）" % n)


func _event_resolve(rest: PackedStringArray) -> void:
	var pending := Game.pending_events()
	if pending.is_empty():
		_print_err("没有挂着的事件 —— 先 event force <代号>")
		return
	var id := pending[0].id
	var index := 0
	# 两种写法：`event resolve 1`（回最早那条的第 1 项）/ `event resolve friend_loan 1`
	if rest.size() == 1 and rest[0].is_valid_int():
		index = int(rest[0])
	elif rest.size() >= 1:
		id = StringName(rest[0])
		if rest.size() >= 2 and rest[1].is_valid_int():
			index = int(rest[1])
	var r: Dictionary = Game.resolve_event(index, id)
	if not r.get("ok", false):
		_print_err(String(r.get("reason", "选不了")))
		return
	var opt: EventOption = r["option"]
	var picked: EventData = r["event"]
	_print("已选 %s · [%d] %s" % [String(picked.id), index, opt.label])
	_print("  " + opt.reply)
	_print("  现在：" + _state_line())
	# 履历是「效果真的落了吗」的最终证据 —— 事件记录里 choice / label / note 都在
	var last: Dictionary = Game.state.event_history.back() if not Game.state.event_history.is_empty() else {}
	if not last.is_empty():
		_print("  履历：第 %d 天 · %s · 选了「%s」" % [
				int(last.get("day", 0)), String(last.get("event", "")), String(last.get("label", ""))])


# ============================================================
# 时间 / 种子 / 数值
# ============================================================
## 推进 n 天。**必须走 `Game.end_day()`**：它才会发 `day_advanced`、才会在周一/第 2~5 天
## 调 `EventScheduler.pick` 排事件，也才会在周末结算。直接改 `state.day` 什么都不会发生。
func _cmd_day(args: PackedStringArray) -> void:
	var n := 1
	if args.size() > 0 and args[0].is_valid_int():
		n = clampi(int(args[0]), 1, 21)
	for i in n:
		if Game.state == null or Game.state.finished:
			_print("已经到结局了，不再推进")
			break
		var r: Dictionary = Game.end_day()
		_print("→ " + _state_line())
		if bool(r.get("settled", false)):
			_print("  └ 周末结算（自动存档已写 %s）" % SAVE_PATH)
		if Game.state.finished:
			_print("结局：%s" % String(Game.state.ending_id))
			break


func _cmd_seed(args: PackedStringArray) -> void:
	if Game.state == null:
		_print_err("Game.state 还没有")
		return
	if args.is_empty():
		_print("event_seed = %d（seed <n> 换一个，同种子可复现同一周）" % Game.state.event_seed)
		return
	var v := args[0].to_lower()
	Game.state.event_seed = randi() if v == "random" else int(v)
	_print("event_seed = %d（本周计划与抽签随之改变；已经挂着的事件不变）"
			% Game.state.event_seed)
	var plan := EventScheduler.week_plan(Game.state, Game.week())
	_print("第 %d 周计划：%s" % [Game.week(), _plan_text(plan)])


## `money 500` = 设为 500；`money +100` / `money -50` = 增减。
##
## 【一律转成增量】`Game.add_*` 是唯一带夹值 + 信号的写入口；直接赋 `state.money`
## 界面上的数字不会变（`money_changed` 才是让 HUD 重画的那条）。
func _cmd_stat(name: String, args: PackedStringArray) -> void:
	var cur := _stat_value(name)
	if args.is_empty():
		_print("%s = %d" % [name, cur])
		return
	var raw := args[0].strip_edges()
	var delta: int
	# 【先看符号再看是不是整数】`-50` 也是合法整数，但它的意思明显是「减 50」而已，
	# 不是「设为 -50」。所以带正负号的一律当增量，不带符号的当目标值。
	if raw.begins_with("+") or raw.begins_with("-"):
		delta = int(raw)
	elif raw.is_valid_int():
		delta = int(raw) - cur
	else:
		_print_err("看不懂的数值：%s（写 500 / +100 / -50）" % raw)
		return
	match name:
		"money":
			Game.add_money(delta)
		"acting":
			Game.add_acting(delta)
		"fame":
			Game.add_fame(delta)
		"reputation":
			Game.add_reputation(delta)
	_print("%s %s → %d" % [name, _signed(delta), _stat_value(name)])


func _stat_value(name: String) -> int:
	if Game.state == null:
		return 0
	match name:
		"money":
			return Game.money()
		"acting":
			return Game.acting()
		"fame":
			return Game.fame()
		"reputation":
			return Game.reputation()
	return 0


# ============================================================
# 存档保护
# ============================================================
## `day` 指令跨周时会写 `user://save.json`（产品的自动存档行为）。GM 一旦把进度推到
## 周末，玩家的真进度就被测试局覆盖了 —— 所以动手之前先 `backup`。
func _cmd_backup() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_print_err("没有存档可备份（%s 不存在）" % SAVE_PATH)
		return
	if _copy(SAVE_PATH, BACKUP_PATH):
		_print("已备份 %s → %s" % [SAVE_PATH, BACKUP_PATH])
	else:
		_print_err("备份失败")


func _cmd_restore() -> void:
	if not FileAccess.file_exists(BACKUP_PATH):
		_print_err("没有备份（%s 不存在）" % BACKUP_PATH)
		return
	if not _copy(BACKUP_PATH, SAVE_PATH):
		_print_err("还原失败")
		return
	# 还原只是把文件写回去；界面还停在当前局 —— 必须让 Game 重读一次才会「真的回去」
	Game.load_from()
	_print("已还原 %s 并重新读档（手机 / 日历已按新状态重画）" % SAVE_PATH)


func _copy(from: String, to: String) -> bool:
	var src := FileAccess.open(from, FileAccess.READ)
	if src == null:
		return false
	var data := src.get_buffer(src.get_length())
	src.close()
	var dst := FileAccess.open(to, FileAccess.WRITE)
	if dst == null:
		return false
	dst.store_buffer(data)
	dst.close()
	return true


# ============================================================
# 输出 / 小工具
# ============================================================
func _print(line: String) -> void:
	_lines.append(line)
	if _lines.size() > MAX_LINES:
		_lines = _lines.slice(_lines.size() - KEEP_LINES)
	_out.text = "\n".join(_lines)


func _print_err(line: String) -> void:
	_print("⚠ " + line)


func _state_line() -> String:
	if Game.state == null:
		return "（还没有状态）"
	return "第 %d 天 · 第 %d 周 · AP %d · %d 元 · 演技 %d · 知名度 %d · 风评 %d" % [
			Game.day(), Game.week(), Game.ap_left(), Game.money(),
			Game.acting(), Game.fame(), Game.reputation()]


## 一周 1~2 条。**只有 2 条时「第 2 条落在第几天」才有意义** ——
## 1 条的时候把那个数字也印出来，玩家会以为漏了一条。
func _plan_text(plan: Dictionary) -> String:
	if int(plan.get("count", 1)) < 2:
		return "1 条（周一）"
	return "2 条（周一 + 第 %d 天）" % int(plan.get("second_day", 0))


func _pending_ids() -> String:
	var evs := Game.pending_events()
	if evs.is_empty():
		return "（无）"
	var out: PackedStringArray = []
	for e: EventData in evs:
		out.append(String(e.id))
	return ", ".join(out)


func _signed(n: int) -> String:
	return ("+" if n > 0 else "") + str(n)
