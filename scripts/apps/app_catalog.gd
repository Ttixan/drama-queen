class_name AppCatalog
extends RefCounted
## 四个 App 的表 —— 手机屏的「左栏」直接照它铺
##
## 【为什么写死在代码里】它是**导航结构**（有哪几个 App 是玩法定义，不是数值），
## 与 `scripts/data/` 里那些「策划要改」的资源不是一类东西。配色沿用 `UiPalette` 的语义色。
##
## `mark` 是图标里的那个字。**必须显式写死**：按名字取首字会让「微信」和「微博」
## 都显示「微」，两个图标长得一模一样。
##
## `hint` 是**悬浮时显示的作用** —— 手机屏左栏拿它当说明文字，
## 所以它得是一句人话（「私聊 HR 就是投递」），不是标签。
const APPS: Array[Dictionary] = [
	{"name": "Boss直聘", "mark": "聘", "scene": "res://scenes/apps/boss.tscn",
		"color": UiPalette.BOSS, "hint": "看公司 · 解锁 HR"},
	{"name": "录像机", "mark": "录", "scene": "res://scenes/minigame/recorder.tscn",
		"color": UiPalette.ACCENT, "hint": "拼 3 帧表情包"},
	{"name": "微信", "mark": "信", "scene": "res://scenes/apps/wechat.tscn",
		"color": UiPalette.WECHAT, "hint": "私聊 HR 就是投递"},
	{"name": "微博", "mark": "博", "scene": "res://scenes/apps/weibo.tscn",
		"color": UiPalette.WEIBO, "hint": "《有瓜有戏》往期"},
]


## 按场景路径找一条（手机屏收到「打开某个 App」的请求时用）
static func by_scene(scene_path: String) -> Dictionary:
	for app: Dictionary in APPS:
		if String(app["scene"]) == scene_path:
			return app
	return {}
