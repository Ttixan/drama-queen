class_name UiPalette
extends RefCounted
## 界面配色与样式工厂 —— **所有 App 共用一套**
##
## 【为什么要抽出来】录像机和微信各存一份色值的话，扉师改一次主色要改两个文件，
## 迟早改漏一个，两个界面就开始慢慢跑偏。颜色是视觉身份，必须单一来源。
##
## 【为什么不是 Godot Theme 资源】`.tres` 的 Theme 改不了「代码里动态建的部件卡」
## 和「按状态换描边」这类事。这里只放"色值 + 基础 StyleBox"，语义化的样式仍由各 App 自己组。
##
## 【颜色编号与占位图同源】EMOTION_COLORS 必须和 `tools/gen_placeholder_art.gd` 一致，
## 否则开发期「标签颜色对不上缩略图」，向量对不对就看不出来了。


## —— 字体 ——
## 全局正文/标题都用这一支：Kaisei Tokumin ExtraBold + 系统字体兜底
## （本体在 `assets/fonts/main_font.tres`，全局主题也指向它）。
## 【为什么代码里还要存一份】需要**量字宽**的地方（聊天气泡、标题截断）必须和
## 真正渲染的字体用同一套度量 —— 拿 `ThemeDB.fallback_font` 量、拿这支画，
## 气泡就会算窄或算宽。那几处都不是 Label 节点，拿不到"主题字体重画"的时机。
const FONT := preload("res://assets/fonts/main_font.tres")

## —— 底色 ——
const BG := Color("16161a")
const PANEL := Color("232329")
const PANEL_SOFT := Color("2b2b33")
const LINE := Color("3a3a45")

## —— 纸面（底部条，剪纸拼贴的浅色层）——
const PAPER := Color("f5f1e8")
const PAPER_SOFT := Color("e3ddd0")
const PAPER_HOVER := Color("efeadf")
const PAPER_DISABLED := Color("ddd6c8")
const PAPER_LINE := Color("cfc8b8")
const INK := Color("16161a")

## —— 二级页面（台历 / 笔记本）的纸面 ——
## 【为什么和上面的 PAPER 系分开】那套是奶白色的剪纸层，配深色底；
## 台历与笔记本的纸是**青色插画**，字必须压深蓝墨，套奶白纸的色号会糊成一片。
## 两页共用这几个值 —— 以后调"纸上的墨色"只改这里。
const PAGE_INK := Color("1d3446")
const PAGE_INK_SOFT := Color("4e6678")
const PAGE_INK_FAINT := Color("8199a8")
const PAGE_CARD := Color(1, 1, 1, 0.55)
const PAGE_CARD_HOVER := Color(1, 1, 1, 0.92)
const PAGE_CARD_PRESSED := Color(0.92, 0.97, 1, 0.95)
## 纸面上卡片的描边：墨色半透明，压在插画上不抢线稿
const PAGE_LINE := Color(0.11, 0.2, 0.27, 0.35)
const PAGE_LINE_OFF := Color(0.11, 0.2, 0.27, 0.14)

## —— 文字 ——
const TEXT := Color("f5f1e8")
const TEXT_DIM := Color("a0a0aa")
const TEXT_ON_PAPER_DIM := Color("8a8478")
const TEXT_DISABLED := Color("9a948a")

## —— 功能色 ——
const ACCENT := Color("ffd447")   ## 选中 / 强调
const POSITIVE := Color("4caf6e")
const DANGER := Color("e5484d")
## 微信的品牌色。**目前与「成功绿」`POSITIVE` 同值** —— 从图标、顶栏、按钮到选中的档位
## 全用这一个色（原注释说「偏冷，和成功区分开」，对不上实际值，改准了）。
## 哪天想把两者分开（比如换成微信真正的 `#07C160`），改这一处即可，别在别处硬写绿。
const WECHAT := Color("4caf6e")
const WEIBO := Color("ff7a45")    ## 微博的品牌色（橙红）——《有瓜有戏》是它的内容
## 剧本（HR 在微信里发过来的那份 `.docx`）的橘色：文件卡的描边、剧本页的标题与正文。
##
## 【为什么和 WEIBO 分开】两个都是橙色系，值也接近 —— 但语义完全不同：
## 一个是「这个 App 是微博」，一个是「这是你的剧本」。共用一个色号的话，
## 哪天调微博的主色会顺手把剧本页也改掉，而它们本来没有任何关系。
const SCRIPT := Color("ff9d4d")
## 文件卡上那个「W」图标的蓝 —— 照真 Word 文档图标取的色，
## 让玩家一眼认出「这是个文档」，而不是自己拼的一张图片。
const DOCX := Color("2b579a")
## 「简历拿来」（Boss直聘 的戏仿名）的品牌色 —— 青。
## 【它和全局 ACCENT 不是一回事】ACCENT 是「选中 / 强调」的通用黄；
## 这个色只属于这个 App，Boss 页的顶栏描边、品牌、按钮全都用它。
## 公司档位里的 C 档另有一份自己的字面值（曾经与它同色，现在无关了）。
const BOSS := Color("15b3b4")
## 周初事件的说话人（导演 / 老同学 / 发小…）。
## 【为什么必须另开一个色】它会和公司档位头像出现在**同一个联系人列表**里，
## 用档位色里任何一个都会让玩家以为「这家公司又来了个联系人」。
const EVENT := Color("4dd0e1")
## 【微信的气泡不再单开色号】自己那条直接用品牌绿 `WECHAT`，字压 `INK`（深色）——
## 品牌绿太亮，白字发虚；绿底深字也正是真微信的做法。
## 对面那条走 `PANEL_SOFT` 中性灰：**别人的话不该抢品牌色**（与「简历拿来」同一条道理）。
## 这条口径是提提 10-16 定的：同一个聊天里只允许两种气泡底色，
## 不再按成败（绿/红）与哪条会话（事件的青）换色。
## 「简历拿来」的聊天气泡：自己那条用**品牌青压暗** ——
## 品牌色直接铺太亮（`#15b3b4` 上压白字发虚），压暗之后才压得住字。
## 对面那条不用品牌色，继续走中性灰：**别人的话不该抢品牌色**。
const BOSS_CHAT_SELF := Color("12575a")
const BOSS_CHAT_TEXT := Color("e6fbfa")  ## 压在青气泡上的字

## 公司档位配色 —— Boss直聘 与微信的联系人头像共用。
## 从灰到黄是一条「越往上越亮」的梯度：玩家不用看字就知道哪家更高级。
const COMPANY_TIER_COLORS := {
	CompanyData.Tier.A_LOW: Color("8b8b8b"),
	CompanyData.Tier.B_SMALL: Color("a855f7"),
	CompanyData.Tier.C_COMMERCIAL: Color("4a7fe5"),
	CompanyData.Tier.D_ARTHOUSE: Color("ff7ab6"),
	CompanyData.Tier.E_MAJOR: Color("ffd447"),
}

## 与 tools/gen_placeholder_art.gd 的 EMO_COLORS 一一对应
const EMOTION_COLORS := {
	Emotion.Kind.JOY: Color("ffd447"),
	Emotion.Kind.ANGER: Color("e5484d"),
	Emotion.Kind.SORROW: Color("4a7fe5"),
	Emotion.Kind.SHOCK: Color("a855f7"),
	Emotion.Kind.CHARM: Color("ff7ab6"),
	Emotion.Kind.AWKWARD: Color("8b8b8b"),
}


## 某一帧应该用什么颜色标情绪。空帧走中性灰 —— 不能返回「喜」的黄色。
static func frame_color(v: PackedFloat32Array) -> Color:
	if Emotion.is_empty(v):
		return TEXT_DIM
	return EMOTION_COLORS[Emotion.dominant(v)]


# ============================================================
# StyleBox 工厂
# ============================================================
static func panel(bg: Color, radius := 16, border := 0, border_color := LINE) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border > 0:
		sb.set_border_width_all(border)
		sb.border_color = border_color
	return sb


## 按钮/卡片用。content_lift 用「上下留白差」做视觉上浮 ——
## 容器会覆盖子节点的 position，所以在容器里动不了 position，只能这么抬。
static func button(bg: Color, border := Color(0, 0, 0, 0), width := 0,
		radius := 14, content_lift := 0, pad := 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(width)
	sb.border_color = border
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = maxi(pad - content_lift, 2)
	sb.content_margin_bottom = pad + content_lift
	return sb


static func rounded(bg: Color, radius := 5) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	return sb


## 给 Label / Button 一次性设字号与颜色（对 Control 通用）
static func text(node: Node, size: int, color: Color) -> void:
	var c := node as Control
	if c == null:
		return
	c.add_theme_font_size_override("font_size", size)
	c.add_theme_color_override("font_color", color)
