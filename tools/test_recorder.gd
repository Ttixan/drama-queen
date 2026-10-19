extends SceneTree
## 录像机交互验证 —— headless 跑，不需要渲染，也不需要人手点
##
##   godot --headless --path <项目> --script res://tools/test_recorder.gd
##
## 【为什么必须机器验】录像机最关键的一条正确性是「空帧显示『平静』而不是『喜』」。
## 那是已经犯过一次的 bug（Emotion.dominant 在全零向量上返回 JOY）。靠肉眼看三次
## 是看不住的，必须钉成断言。
##
## 【为什么能 headless 验】全部交互都落在 Clip 上，而 Clip 是纯 RefCounted。
## 这条链路能跑通，本身就是「场景层没有偷偷藏逻辑」的证明。

const SCENE := "res://scenes/minigame/recorder.tscn"

var _failures: Array[String] = []
var _checks := 0
var _app                      ## 故意不标类型：要动态访问场景脚本的成员
var _emitted: Array[Clip] = []


func _initialize() -> void:
	# 【踩坑 · 会让脚本静默挂死】不能在 _initialize() 里直接断言。
	# `--script` 模式下，此刻 SceneTree 的 root 还没执行 _set_tree()，
	# 于是 add_child 进去的节点**不会走 _ready** —— 场景脚本等于没初始化，
	# 访问它的成员拿到的是 null。而 GDScript 的运行时报错只中断当前函数，
	# 到不了后面的 quit()，进程就永远停在那里、输出被管道缓住，看起来就是「没反应」。
	# 正确做法：等第一帧（root 已就位、_ready 已触发）再验。
	_app = load(SCENE).instantiate()
	root.add_child(_app)
	process_frame.connect(_run_all, CONNECT_ONE_SHOT)


func _run_all() -> void:
	print("")
	print("=== 录像机交互验证 ===")
	print("")

	if _app._clip == null:
		print("❌ 场景 _ready() 没有跑起来，后面的断言全都没有意义")
		quit(1)
		return

	var bus := root.get_node_or_null("EventBus")
	_check("EventBus autoload 可用", bus != null, true)
	if bus != null:
		bus.recorder_finished.connect(func(c: Clip) -> void: _emitted.append(c))

	print("[1] 初始状态（三帧空 Frame，不该需要再补）")
	_check("帧数", _app._clip.frame_count(), 3)
	_check("三帧都空 → 不完整", _app._clip.is_complete(), false)
	_check("确认按钮置灰", _app._confirm_button.disabled, true)
	_check("空帧标签 = 平静（历史 bug 回归）", _app._clip.frame_label(0), "平静")
	_check("界面上的情绪标签也是平静", _app._emotion_value.text, "平静")
	# 帧序列早就从顶栏搬到 `FrameInfo` 了（顶栏整条让给状态图标）——
	# 旧断言还在读 `_sequence_label`，属性不存在会中断 _run_all，进程就挂在那里
	_check("帧序列初始为三连平静", _app._frame_info.text, "帧 1 / 3 · 平静 → 平静 → 平静")
	_check("部件明细为空", _app._emotion_parts.text, "—")

	print("")
	print("[2] 选件写进当前帧")
	_pick(PartData.Slot.EYES, "eyes_04")   # 喜悦：喜 + 魅 → 主导情绪「喜」
	_check("帧1 的眼 = eyes_04", String(_app._clip.frames[0].eyes.id), "eyes_04")
	_check("情绪标签随之变「喜」", _app._emotion_value.text, "喜")
	_check("部件明细", _app._emotion_parts.text, "喜悦")
	_check("选中的卡亮起", _card(PartData.Slot.EYES, "eyes_04").button_pressed, true)
	_check("同槽位其他卡不亮", _card(PartData.Slot.EYES, "eyes_07").button_pressed, false)

	print("")
	print("[3] 三帧互相独立，切帧要回填")
	_select_frame(1)
	_check("帧1 的选择不影响帧2", _app._clip.frames[1].eyes, null)
	_check("帧2 空 → 平静", _app._emotion_value.text, "平静")
	_check("切帧后帧1 的卡不再亮着", _card(PartData.Slot.EYES, "eyes_04").button_pressed, false)
	_pick(PartData.Slot.EYES, "eyes_03")   # 含泪：哀
	_check("帧2 的眼 = eyes_03", String(_app._clip.frames[1].eyes.id), "eyes_03")
	_check("帧2 情绪 = 哀", _app._emotion_value.text, "哀")
	_select_frame(0)
	_check("切回帧1 标签回到「喜」", _app._emotion_value.text, "喜")
	_check("切回帧1 卡片回填", _card(PartData.Slot.EYES, "eyes_04").button_pressed, true)
	_check("帧2 的眼没被覆盖", String(_app._clip.frames[1].eyes.id), "eyes_03")

	print("")
	print("[4] 其他可以留空（组合数 ×7 的那 1 种）")
	_check("初始 extra 为空", _app._clip.frames[0].extra, null)
	_pick(PartData.Slot.EXTRA, "extra_04")   # 脸红
	_check("挂上别的部件", String(_app._clip.frames[0].extra.id), "extra_04")
	_pick(PartData.Slot.EXTRA, "")           # 留空那张卡
	_check("还能选回留空", _app._clip.frames[0].extra, null)
	_check("留空卡亮起", _card(PartData.Slot.EXTRA, "").button_pressed, true)
	_pick(PartData.Slot.EXTRA, "extra_04")

	print("")
	print("[4b] 肤色：写进帧、但不进判定")
	_check("没选过时帧里是 null（渲染按默认肤色）", _app._clip.frames[0].skin, null)
	_check("默认肤色那张卡亮着", _card(PartData.Slot.SKIN, "skin_00").button_pressed, true)
	# 前后对比而不是写死「喜」：上一步挂了脸红的配件，这里的情绪本来就不是单纯的喜
	var emo_before: String = _app._emotion_value.text
	var parts_before: String = _app._emotion_parts.text
	_pick(PartData.Slot.SKIN, "skin_02")     # 黑
	_check("帧1 的肤色 = skin_02", String(_app._clip.frames[0].skin.id), "skin_02")
	_check("肤色卡亮起", _card(PartData.Slot.SKIN, "skin_02").button_pressed, true)
	_check("换肤色不改情绪", _app._emotion_value.text, emo_before)
	_check("换肤色不改部件明细", _app._emotion_parts.text, parts_before)
	_check("画面上的肤色层跟着换", _app._layer_skin.texture, _app._clip.frames[0].skin.texture)

	print("")
	print("[5] 清空本帧")
	_app._clear_button.emit_signal("pressed")
	_check("眼被清掉", _app._clip.frames[0].eyes, null)
	_check("其他也被清掉", _app._clip.frames[0].extra, null)
	_check("肤色回到默认（不是「没有脸皮」）", _app._clip.frames[0].skin, null)
	_check("画面回落到默认肤色", _app._layer_skin.texture, PartLibrary.default_skin().texture)
	_check("回到平静", _app._emotion_value.text, "平静")

	print("")
	print("[6] 没拼完不能确认")
	_check("确认按钮仍置灰", _app._confirm_button.disabled, true)
	var before := _emitted.size()
	_app._confirm_button.emit_signal("pressed")
	_check("缺件时按了也不发信号", _emitted.size(), before)

	print("")
	print("[7] 拼满三帧 → 确认产出 Clip")
	_build_full_clip()
	_check("三帧齐全", _app._clip.is_complete(), true)
	_check("确认按钮解禁", _app._confirm_button.disabled, false)
	_app._confirm_button.emit_signal("pressed")
	_check("发了一次 recorder_finished", _emitted.size(), 1)
	if _emitted.size() == 1:
		var got: Clip = _emitted[0]
		_check("交出去的 Clip 完整", got.is_complete(), true)
		_check("交出去的是同一个对象（录像机不做二次包装）", got == _app._clip, true)
		print("   帧序列：%s" % " → ".join(got.all_labels()))
		print("   摘要：%s" % got.summarize())

	print("")
	print("[8] 七层叠加的结构保证（占位图规格：共用画布 / 人脸中心 = 画布中心）")
	# 从下往上：纸 → 肤色 → 空白脸 → 眉 → 眼 → 嘴 → 其他
	var layers: Array = [_app._layer_paper, _app._layer_skin, _app._layer_base,
			_app._layer_brows, _app._layer_eyes, _app._layer_mouth, _app._layer_extra]
	var parent: Node = _app._layer_eyes.get_parent()
	for l: TextureRect in layers:
		_check("%s 与眼层同一个父节点" % l.name, l.get_parent() == parent, true)
		_check("%s 四边锚点拉满（直接重合即对齐）" % l.name,
				[l.anchor_right, l.anchor_bottom], [1.0, 1.0])
		_check("%s 使用同一套拉伸模式" % l.name,
				[l.expand_mode, l.stretch_mode], [layers[1].expand_mode, layers[1].stretch_mode])
	# 预览必须跟着「当前帧」走 —— 切帧换贴图是四层叠加之外的另一半正确性
	_select_frame(0)
	var f1: Clip.Frame = _app._clip.frames[0]
	_check("帧1：眼层贴图 = eyes_04 的贴图", _app._layer_eyes.texture, f1.eyes.texture)
	_check("帧1：眉层贴图 = brows_02 的贴图", _app._layer_brows.texture, f1.brows.texture)
	# 底图不随帧变：纸与空白脸建一次就够，空帧也必须看得见一张脸
	_check("纸底层已加载", _app._layer_paper.texture != null, true)
	_check("空白脸层已加载", _app._layer_base.texture != null, true)
	_check("没选过肤色 → 画的是默认肤色",
			_app._layer_skin.texture, PartLibrary.default_skin().texture)

	# 【正片叠底不能丢】眼白 / 牙齿是白色填充，普通叠加贴到深肤色上就是一块白纸。
	# 守的是「三层五官必须挂着 MUL 材质」—— 掉了不会报错，只会重新长出白边。
	# 前提是素材已经预乘过（import_emoji_layers.py 的 MULTIPLY_SLOTS），
	# 所以这两件事要一起验：材质对了、素材也得是那个形态。
	for l: TextureRect in [_app._layer_brows, _app._layer_eyes, _app._layer_mouth]:
		_check("%s 挂着正片叠底材质" % l.name,
				l.material is CanvasItemMaterial
						and l.material.blend_mode == CanvasItemMaterial.BLEND_MODE_MUL, true)
	_check("五官素材已预乘（透明区是白，不是黑）", _is_multiply_ready(_app._layer_eyes.texture), true)
	# 配件是「挂在脸前面的东西」，不走正片叠底 —— 乘上去深肤色会把镜框压成暗红
	_check("配件层不套正片叠底", _app._layer_extra.material, null)
	_check("帧1：角标显示帧 1", _app._frame_badge.text, "帧 1")
	_check("帧1：情绪标签 = 喜", _app._emotion_value.text, "喜")
	_select_frame(2)
	var f3: Clip.Frame = _app._clip.frames[2]
	_check("切到帧3：眼层换成 eyes_03 的贴图", _app._layer_eyes.texture, f3.eyes.texture)
	_check("帧3：角标显示帧 3", _app._frame_badge.text, "帧 3")
	_check("帧3：情绪标签 = 哀", _app._emotion_value.text, "哀")

	print("")
	print("[9] 页签与帧槽的互斥")
	var pressed_tabs := 0
	for t: Button in _app._tabs:
		if t.button_pressed:
			pressed_tabs += 1
	_check("同时只有一个页签亮", pressed_tabs, 1)
	var pressed_slots := 0
	for s: Button in _app._slot_buttons:
		if s.button_pressed:
			pressed_slots += 1
	_check("同时只有一个帧槽亮", pressed_slots, 1)

	print("")
	print("[10] 帧数可增删（1..5）")
	_check("初始 3 帧", _app._clip.frame_count(), 3)
	_check("帧槽键面只写数字", _app._slot_buttons[0].text, "1")
	_app._frame_add.emit_signal("pressed")
	_check("加一帧 → 4", _app._clip.frame_count(), 4)
	_check("加完跳到新帧", _app._frame, 3)
	_check("帧槽按钮跟着变多", _app._slot_buttons.size(), 4)
	_app._frame_add.emit_signal("pressed")
	_check("再加 → 5", _app._clip.frame_count(), 5)
	_check("到上限置灰", _app._frame_add.disabled, true)
	_app._frame_add.emit_signal("pressed")
	_check("满了再加不动", _app._clip.frame_count(), 5)
	# 删的是**当前帧**，不是末尾：停在第 2 帧按减号，消失的该是它
	_select_frame(1)
	var kept: Clip.Frame = _app._clip.frames[0]
	_app._frame_remove.emit_signal("pressed")
	_check("删当前帧 → 4", _app._clip.frame_count(), 4)
	_check("第 1 帧没被连带删掉", _app._clip.frames[0], kept)
	_check("删除后当前帧仍是合法下标", _app._frame, 1)
	for i in 3:
		_app._frame_remove.emit_signal("pressed")
	_check("删到只剩 1 帧", _app._clip.frame_count(), 1)
	_check("只剩一帧时置灰", _app._frame_remove.disabled, true)
	_app._frame_remove.emit_signal("pressed")
	_check("最后一帧删不掉", _app._clip.frame_count(), 1)
	_check("帧槽也只剩一个", _app._slot_buttons.size(), 1)

	print("")
	print("[11] 两种解锁门：灰着的卡点不动，且写明为什么")
	# 【为什么不写死「第 1 周」】录像机读的是 `Game.state` 的周次，而 headless 跑测试时
	# 机器上可能躺着一份第 2 周的存档。这里断言的是**状态与界面一致**，不是某个具体周次。
	# 【为什么不用 `Game` 这个标识符】`--script` 的主脚本在 autoload 注册成全局名之前
	# 就被编译了，直接写 `Game` 会是「Identifier not found」（这个坑只在这个测试里踩得到）。
	var game: Node = root.get_node_or_null("Game")
	var locked_seen := 0
	var free_seen := 0
	for slot: int in PartLibrary.TAB_ORDER:
		for part: PartData in PartLibrary.by_slot(slot):
			var card := _card(slot, String(part.id))
			var unlocked: bool = game.is_part_unlocked(part) if game != null \
					else part.is_unlocked_at(1)
			_check("%s 的卡可用状态与状态层一致" % part.id, card.disabled, not unlocked)
			if not unlocked:
				locked_seen += 1
				# 两种门写两种话：等得起 vs 得去翻牌
				var want := "第 %d 周解锁" % part.unlock_week
				if not String(part.set_id).is_empty():
					want = "翻牌获得"
				_check("%s 的卡写明了解锁方式" % part.id, card.tooltip_text, want)
			else:
				free_seen += 1
	_check("已解锁的卡都点得动（%d 件）" % free_seen, free_seen > 0, true)
	# 真·开局：9 件翻牌（三套）+ 6 件第 3 周 = 15
	if game != null and game.state != null and game.state.week() == 1:
		_check("第 1 周确实有 15 件灰着", locked_seen, 15)
	# 「留空」不是部件，永远不该被锁
	_check("「其他」的留空卡永远可用", _card(PartData.Slot.EXTRA, "").disabled, false)

	print("")
	print("共 %d 项断言" % _checks)
	if _failures.is_empty():
		print("✅ 全部通过")
		quit(0)
	else:
		print("❌ %d 项失败：" % _failures.size())
		for msg: String in _failures:
			print("   - " + msg)
		quit(1)


# ============================================================
## 素材是不是「正片叠底友好」的形态：找一块**完全透明**的像素，RGB 应该是白。
## 没预乘的话那块是 (0,0,0)，MUL 上去会把整块画板压成黑 —— 这条断言就是那个坑的守门人。
func _is_multiply_ready(tex: Texture2D) -> bool:
	if tex == null:
		return false
	var img := tex.get_image()
	if img == null:
		return false
	if img.is_compressed():
		img.decompress()
	for p: Vector2i in [Vector2i(4, 4), Vector2i(img.get_width() / 2, 4)]:
		var c := img.get_pixelv(p)
		if c.a == 0.0:
			return c.r > 0.9 and c.g > 0.9 and c.b > 0.9
	return false


func _card(slot: int, key: String) -> Button:
	return _app._cards[slot][key]


## 走真实控件路径：程序化设置 button_pressed 会触发 toggled，处理器照常跑
func _pick(slot: int, key: String) -> void:
	_card(slot, key).button_pressed = true


func _select_frame(index: int) -> void:
	_app._slot_buttons[index].button_pressed = true


## 拼一段「喜 → 平 → 哀」——顺带把 D 公司的递减曲线摆出来，方便 eyeball
func _build_full_clip() -> void:
	_select_frame(0)
	_pick(PartData.Slot.EYES, "eyes_04")     # 喜悦
	_pick(PartData.Slot.MOUTH, "mouth_03")   # 喜悦
	_pick(PartData.Slot.BROWS, "brows_02")   # 惊讶
	_select_frame(1)
	_pick(PartData.Slot.EYES, "eyes_00")     # 信任
	_pick(PartData.Slot.MOUTH, "mouth_00")   # 认真脸
	_pick(PartData.Slot.BROWS, "brows_00")   # 信任
	_select_frame(2)
	_pick(PartData.Slot.EYES, "eyes_03")     # 含泪
	_pick(PartData.Slot.MOUTH, "mouth_08")   # 嚎啕
	_pick(PartData.Slot.BROWS, "brows_05")   # 八字


func _check(label: String, got: Variant, want: Variant) -> void:
	_checks += 1
	if got != want:
		_failures.append("%s: 期望 %s，实际 %s" % [label, want, got])
