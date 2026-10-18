extends Node
## 音效总线（Autoload 名：`Sfx`）—— 全游戏只在这一处 `.play()`。
##
## 【为什么要有这一层】音效调用点会散在十几个界面里（点击、投递、属性跳动…）。
## 每个界面自己 new 一个 AudioStreamPlayer 的话：音量各调各的、同一个音叠着响、
## 换个文件要改十个路径。这里统一成「一个代号一个音」，界面侧只写
## `Sfx.play(&"mail_sent")`，文件换名 / 调音量都只动这一个文件。
##
## 【UI 音效为什么是全局挂钩】按钮是各页面自己 `Button.new()` 出来的，几百个；
## 让每个地方都记得连一次点击音，迟早漏一个，而且新页面永远想不起来。
## 所以这里监听 `get_tree().node_added`：**只要是 BaseButton 就自动挂上**，
## 页面作者不用为音效写任何代码，也不用知道 `Sfx` 存在。
##
## 【本批素材缺两条】**没有 `bgm_main_theme`（表里"进行中"）**、
## **没有 `sfx_game_open_pack`（表里就写着缺）**。所以这里只有 7 条；
## 等文件到了：`STREAMS` 加一行 + 在对应信号上补一次 `play()` 即可。
##
## 【废弃的三条没有接】消息提示音 / 消息震动音 / 结局音（表里"已废弃"），
## 别在这里补 —— 废弃的意思是那条交互已经没有了。

## 代号 -> 音。代号用「这声音是干什么的」，不用文件名：
## 以后美术换一版素材，改的是右边那个路径，界面侧一行都不用动。
const STREAMS: Dictionary = {
	&"ui_click": preload("res://assets/sfx/ui_click_01.wav"),
	&"ui_hover": preload("res://assets/sfx/ui_click_02.wav"),
	&"mail_sent": preload("res://assets/sfx/email_send_success.wav"),
	&"mail_reply": preload("res://assets/sfx/email_reply.wav"),
	&"money_up": preload("res://assets/sfx/stat_money_up.wav"),
	&"skill_up": preload("res://assets/sfx/stat_skill_up.wav"),
	&"weibo": preload("res://assets/sfx/weibo_notify.wav"),
}

## 每条音的相对音量（dB）。**以"听清但不抢戏"为准**：
## 悬浮最轻（一划而过要好几次）、点击其次；钱 / 演技是正反馈，稍亮一点。
const VOLUME_DB: Dictionary = {
	&"ui_click": -6.0,
	&"ui_hover": -16.0,
	&"mail_sent": -4.0,
	&"mail_reply": -4.0,
	&"money_up": -6.0,
	&"skill_up": -6.0,
	&"weibo": -6.0,
}

## 同时能响几条。UI 音很短，但投递那一下会连响「发送 + 回信」两三条，
## 一条 AudioStreamPlayer 会互相打断 —— 所以用一个小池子轮着放。
const VOICES := 8

## 悬浮音的冷却：鼠标从一排按钮上划过去会连发 mouse_entered，
## 不拦的话就是一串"咔咔咔"。
const HOVER_GAP_MS := 70

## 测试用：最近播过的代号。headless 的 Dummy 音频驱动不会真的出声，
## 靠这个才能验证「信号确实接到了播放这一步」。
var played_log: Array[StringName] = []

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_hover_ms := 0


func _ready() -> void:
	# 暂停（周末结算浮层 / 结局）时音效也该照常响 —— 它是"界面在说话"
	process_mode = Node.PROCESS_MODE_ALWAYS

	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.name = "Voice%d" % i
		add_child(p)
		_players.append(p)

	# 所有按钮的点击 / 悬浮音，见文件头
	get_tree().node_added.connect(_on_node_added)

	EventBus.money_changed.connect(_on_money_changed)
	EventBus.acting_changed.connect(_on_acting_changed)
	EventBus.audition_submitted.connect(_on_audition_submitted)
	# 【回信音不在这里接了】`hr_replied` 是玩家点发送的**同一帧**发的，那时对方
	# 才刚开始"打字"（见 `wechat_app._typing`）。这一声得跟着气泡出现走，
	# 所以由 `wechat_app._finish_typing` 在气泡落地那一刻自己播。
	EventBus.broadcast_published.connect(_on_broadcast_published)


# ============================================================
# 对外唯一入口
# ============================================================
func play(code: StringName) -> void:
	var stream: AudioStream = STREAMS.get(code, null)
	if stream == null:
		# 代号写错要吵一点：静音失败最难查（"这功能怎么没声音"）
		push_warning("Sfx：没有代号为 %s 的音效" % code)
		return
	var p := _take_player()
	p.stream = stream
	p.volume_db = float(VOLUME_DB.get(code, 0.0))
	p.play()

	played_log.append(code)
	if played_log.size() > 32:
		played_log.pop_front()


## 找一个没在响的；全在响就轮到下一个（最老的那条被顶掉）
func _take_player() -> AudioStreamPlayer:
	for i in _players.size():
		var idx := (_next + i) % _players.size()
		if not _players[idx].playing:
			_next = (idx + 1) % _players.size()
			return _players[idx]
	var fallback := _players[_next]
	_next = (_next + 1) % _players.size()
	return fallback


# ============================================================
# UI：全局挂到每个按钮上
# ============================================================
func _on_node_added(node: Node) -> void:
	var b := node as BaseButton
	if b == null:
		return
	# 【防重复】同一个按钮可能因为被移出再挂回而再次触发 node_added
	if b.has_meta(&"sfx_hooked"):
		return
	b.set_meta(&"sfx_hooked", true)
	b.mouse_entered.connect(_on_button_hovered.bind(b))
	b.pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	play(&"ui_click")


func _on_button_hovered(b: BaseButton) -> void:
	# 灰掉的按钮不发声：它点不动，响一下反而像"点到了"
	if b.disabled:
		return
	var now := Time.get_ticks_msec()
	if now - _last_hover_ms < HOVER_GAP_MS:
		return
	_last_hover_ms = now
	play(&"ui_hover")


# ============================================================
# 玩法事件
# ============================================================
## 只有**增加**才响：上课扣钱、买 PS5 分期都是同一条信号，
## 扣钱时"叮"一声会让人以为赚了。
func _on_money_changed(_value: int, delta: int) -> void:
	if delta > 0:
		play(&"money_up")


func _on_acting_changed(_value: int, delta: int) -> void:
	if delta > 0:
		play(&"skill_up")


## 投递成功（录像机里把表情包发出去）。被拒的投递在核心层就 return 了，
## 根本不会发这条信号 —— 所以这里一定是"发出去了"。
func _on_audition_submitted(_result: Dictionary) -> void:
	play(&"mail_sent")


## HR 回信的音**故意不在这里**：它提示的是"有回音了"，那得等聊天里那排点打完、
## 回信真的落到屏幕上（`wechat_app._finish_typing`）。挂在信号上会早整整一段打字时间。


## 周报发刊 = 围脖上有新东西。**没有标题的那一周不响**（比如第 1 周），
## 免得每周固定"叮"一声、玩家把它当背景音。
func _on_broadcast_published(_week: int, headlines: Array) -> void:
	if headlines.is_empty():
		return
	play(&"weibo")
