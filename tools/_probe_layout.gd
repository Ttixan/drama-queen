extends SceneTree
## 临时探针（跑完就删）：录像机嵌进手机右栏之后，到底哪一块装不下

const PHONE := "res://scenes/main/phone_screen.tscn"
const RECORDER := "res://scenes/minigame/recorder.tscn"

const P_CONTENT := "Page/BodyWrap/Body/ContentPanel/ContentMargin/ContentHost"
const P_PANEL := "Page/BodyWrap/Body/ContentPanel"
const P_COLUMN := "Page/BodyWrap/Body/AppColumn"

## 想知道 rect 的录像机内部节点（按树的路径）
const SPOTS: Array[String] = [
	"Page/TopBar",
	"Page/BodyWrap",
	"Page/BodyWrap/Body",
	"Page/BodyWrap/Body/PreviewPanel",
	"Page/BodyWrap/Body/PreviewPanel/PreviewMargin/PreviewBox",
	"Page/BodyWrap/Body/PreviewPanel/PreviewMargin/PreviewBox/ViewFinder",
	"Page/BodyWrap/Body/PreviewPanel/PreviewMargin/PreviewBox/ViewFinder/ViewCenter",
	"Page/BodyWrap/Body/PreviewPanel/PreviewMargin/PreviewBox/ViewFinder/ViewCenter/FaceCanvas",
	"Page/BodyWrap/Body/TabRail",
	"Page/BodyWrap/Body/TabRail/TabEyes",
	"Page/BodyWrap/Body/EditPanel",
	"Page/BodyWrap/Body/EditPanel/EditMargin/EditBox/EmotionStrip",
	"Page/BodyWrap/Body/EditPanel/EditMargin/EditBox/ListScroll",
	"Page/BodyWrap/Body/EditPanel/EditMargin/EditBox/ListScroll/PageEyes",
	"Page/BottomBar",
]


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var phone = load(PHONE).instantiate()
	root.add_child(phone)
	await process_frame
	print("")
	print("root(窗口) size      = ", root.size)
	phone.open_app(RECORDER)
	await process_frame
	await process_frame
	var app = phone._current
	var host: Control = phone.get_node(P_CONTENT)
	print("右栏可用区(ContentHost) = ", host.size)
	print("AppColumn 宽度           = ", (phone.get_node(P_COLUMN) as Control).size.x)
	print("录像机 rect              = ", app.size)
	print("录像机 最小尺寸          = ", app.get_combined_minimum_size())
	print("")
	for path: String in SPOTS:
		var n: Control = app.get_node_or_null(path)
		if n == null:
			print("  <没有> ", path)
			continue
		var deep := _deepest_overflow(n)
		print("  %-52s min=%s rect=%s%s" % [
			path.trim_prefix("Page/"), n.get_combined_minimum_size(), n.size,
			("  ← 内容溢出到 %s" % str(deep)) if not deep.is_empty() else ""])
	print("")
	print("窗口与右栏的差：宽 %d ／ 高 %d" % [
		root.size.x - int(host.size.x), root.size.y - int(host.size.y)])
	quit(0)


## 这个节点自己装不下时，返回最小的那个子节点 rect（用来一眼看出谁把谁顶出去了）
## 【ScrollContainer 不算】它的内容本来就允许比它高 —— 那就是「能滚」的定义。
func _deepest_overflow(node: Control) -> Array:
	if node is ScrollContainer or node.get_child_count() == 0:
		return []
	var worst: Array = []
	for c in node.get_children():
		if not (c is Control):
			continue
		var kid := c as Control
		if not kid.visible:
			continue
		# 容器的子节点超出去 = 布局按最小尺寸铺的，溢出了
		if kid.position.x + kid.size.x > node.size.x + 0.5 \
				or kid.position.y + kid.size.y > node.size.y + 0.5:
			var deeper := _deepest_overflow(kid)
			var pick := deeper if not deeper.is_empty() else [kid.name, kid.size]
			if worst.is_empty() or (pick[1] as Vector2).x > (worst[1] as Vector2).x:
				worst = pick
	return worst
