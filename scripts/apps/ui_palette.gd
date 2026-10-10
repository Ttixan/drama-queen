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

## —— 文字 ——
const TEXT := Color("f5f1e8")
const TEXT_DIM := Color("a0a0aa")
const TEXT_ON_PAPER_DIM := Color("8a8478")
const TEXT_DISABLED := Color("9a948a")

## —— 功能色 ——
const ACCENT := Color("ffd447")   ## 选中 / 强调
const POSITIVE := Color("4caf6e")
const DANGER := Color("e5484d")
const WECHAT := Color("4caf6e")   ## 微信的品牌色，用一个偏冷的绿把它和「成功」区分开
const CHAT_SELF := Color("3d4a2a") ## 自己发的消息气泡底色

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
