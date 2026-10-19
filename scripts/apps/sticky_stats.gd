extends Control
## 桌上的便利贴状态栏：第 X 天 / 第 Y 周 / 星期 Z + 行动点、金钱、演技、名声
##
## 【为什么不塞进 desk_screen】桌子管的是「三样东西点开哪一个」；状态栏只读状态、
## 不碰热点。混在一起之后，每次调界面都要在一份脚本里同时想两件事。
##
## 【为什么每次刷新都重读 Game，而不是各自接增量】数值的写入口有打工、上课、
## 结算、事件四五条路径，增量信号只带 delta —— 漏接一条，贴纸上就会留一个旧数字。
## 全量重读最多多调 4 次 getter，但永远不会对不上。
##
## 【位置怎么来的】贴图 `assets/ui/desk/desk_sticky.png` 是 599×288，
## 从 `主界面-便利贴显示属性.png`（1920×1080）按 alpha 包围盒裁出来的，
## 底图上的落点就是素材原坐标 (1299, 15)。
## 下面几个 RECT 是贴纸内的坐标：图标在格左，数字填在格右。

## 字重走标题那支（Bold）：贴纸是手绘风，正文的 Light 压在纸纹上会糊
const FONT := preload("res://assets/fonts/title_font.tres")
## 数字用黑色：贴纸是浅米底，红字在缩到 1080p 以下时偏粉、和图标里的橙红撞色；
## 黑字和图标那圈手绘黑描边是同一支笔，反而更像「写上去的」
const INK := Color("141414")

## 顶部绿色胶带区
const DAY_RECT := Rect2(22, 4, 500, 48)
## 2×2 网格：四个数字的**垂直中心**要落在图标的中心线上。
## 图标中心实测：上排 y≈104（闪电 82~126、金币 82~126），下排 y≈205
## （面具 179~232、星星 188~232）。左格 0~276、右格 276~599。
const AP_RECT := Rect2(94, 74, 140, 60)
const MONEY_RECT := Rect2(360, 74, 170, 60)
const ACTING_RECT := Rect2(94, 180, 140, 60)
const FAME_RECT := Rect2(360, 180, 170, 60)

const WEEKDAYS := ["一", "二", "三", "四", "五", "六", "日"]

var _day: Label
var _ap: Label
var _money: Label
var _acting: Label
var _fame: Label


func _ready() -> void:
	_build()
	EventBus.ap_changed.connect(_on_ap_changed)
	EventBus.money_changed.connect(_on_value_changed)
	EventBus.acting_changed.connect(_on_value_changed)
	EventBus.fame_changed.connect(_on_value_changed)
	EventBus.day_advanced.connect(_on_day_changed)
	EventBus.state_reset.connect(_refresh)
	_refresh()


func _build() -> void:
	_day = _label(DAY_RECT, 30)
	_ap = _label(AP_RECT, 38)
	_money = _label(MONEY_RECT, 38)
	_acting = _label(ACTING_RECT, 38)
	_fame = _label(FAME_RECT, 38)


func _label(rect: Rect2, size: int) -> Label:
	var l := Label.new()
	l.position = rect.position
	l.size = rect.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", INK)
	add_child(l)
	return l


# ============================================================
# 刷新
# ============================================================
func _refresh() -> void:
	if Game.state == null:
		# 单场景调试 / 测试可能先于 autoload 建界面：留空比抛空指针好
		_day.text = "第-天 / 第-周"
		_ap.text = "-"
		_money.text = "-"
		_acting.text = "-"
		_fame.text = "-"
		return

	_day.text = "第%d天 / 第%d周 / 星期%s" % [
			Game.day(), Game.week(), WEEKDAYS[Game.state.day_of_week() - 1]]
	_ap.text = str(Game.ap_left())
	_money.text = str(Game.money())
	_acting.text = str(Game.acting())
	_fame.text = str(Game.fame())


## 行动点：`ap_changed(left)` —— 只带剩余量
func _on_ap_changed(_left: int) -> void:
	_refresh()


## 金钱 / 演技 / 名声：`xxx_changed(value, delta)`
func _on_value_changed(_value: int, _delta: int) -> void:
	_refresh()


func _on_day_changed(_day: int, _week: int) -> void:
	_refresh()
