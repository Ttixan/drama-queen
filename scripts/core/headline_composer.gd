class_name HeadlineComposer
extends RefCounted
## 从标题库里挑一条，把【报道对象】填对 —— 电子报《有瓜有戏》的头条就是它产出的
##
## 【为什么不能直接用 MailComposer 的 ctx】邮件的语境里玩家是**应聘者**，
## 电子报的语境里玩家是**被报道的人**。同一个玩家，两种称呼：
##   · 知名度 < 20 的龙套     → 不写名字，写角色名（「演【角色名】的那位」）
##   · 知名度 < 20 的主要角色 → 写角色定位（「主角」「配角」）
##   · 知名度 ≥ 20            → 直接上玩家名
## 这套规则来自 `data/news/README.md` 的「标题如何称呼玩家」表。
##
## 【为什么选择规则在代码里而不是数据里】「有没有演过烂剧」「是不是首次出圈」
## 是**玩家状态**，不是标题的属性。标题只负责提供文案，判断必须落在能读到 GameState 的地方。


## 一条作品的头条。`fame_now` = 算上本片之前那几部之后、**此刻**的知名度。
##
## 返回 {id, text, kind}；库里找不到对应标题时 text 为空串（周报会跳过，不会显示空的头条）。
static func compose(play: Dictionary, state: GameState, fame_now: int) -> Dictionary:
	var entry: Dictionary = play.get("entry", {})
	var code := String(entry.get("company_code", ""))
	var grade := int(play.get("grade", BalanceData.Grade.LOW))
	var cast := int(play.get("cast", BalanceData.Cast.EXTRA))
	var ctx := _context(entry, code, cast, fame_now)
	var bal := BalanceLibrary.data()

	if cast == BalanceData.Cast.EXTRA:
		# 首次出圈：龙套演出被注意到、且已经有点名气 —— 观众开始"找人"了。
		# 【只出一次】第一次之后观众就认识你了，再用「全网找人」就是假话。
		if grade == BalanceData.Grade.HIGH and fame_now >= bal.fame_named_threshold \
				and not state.extra_star_seen:
			return _fill(HeadlineLibrary.find_kind(Headline.KIND_EXTRA_STAR), {}, ctx)
		# 好剧 / 烂剧读的是**投递时写进履历的那一次抽签**，不是现在按公司档次重算。
		# 缺字段（旧存档）一律当「好剧」—— 与 GameState.count_bad_plays 同一个回退。
		var lv := 1 if bool(entry.get("play_is_good", true)) else 0
		return _fill(HeadlineLibrary.find_extra(grade, lv), {}, ctx)

	# 主要角色：两处需要换备选 —— 主表里的句子**预设了一段履历**，玩家没有那段履历就穿帮
	if code == "D" and grade == BalanceData.Grade.HIGH and state.count_bad_plays() == 0:
		# 「谁说【报道对象】只会演烂剧？」—— 人家根本没演过烂剧。
		# 【为什么按烂片数而不是按「演没演过 A/B」】口径改了：烂片是投递时摇出来的，
		# 在 A 厂也可能一部烂片都没演到 —— 那种人同样不该被问「只会演烂剧？」。
		return _fill(HeadlineLibrary.find_kind(Headline.KIND_FALLBACK_D_HIGH), {}, ctx)
	if code == "B" and grade == BalanceData.Grade.LOW and fame_now >= bal.fame_named_threshold:
		# 已经点得起名了，就别再写「《剧名》演员哪找的」这种泛指
		return _fill(HeadlineLibrary.find_kind(Headline.KIND_FALLBACK_B_LOW), {}, ctx)
	return _fill(HeadlineLibrary.find_main(code, grade), {}, ctx)


## 黑红 / 黑红重复曝光 —— 由负面曝光累计触发，与某部具体作品无关
static func compose_black_fame(state: GameState, repeat: bool) -> Dictionary:
	var kind := Headline.KIND_BLACK_FAME_REPEAT if repeat else Headline.KIND_BLACK_FAME
	return _fill(HeadlineLibrary.find_kind(kind), {}, _context({}, "", BalanceData.Cast.EXTRA,
			state.fame))


# ============================================================
## 电子报的替换字段表。**故意与邮件的 ctx 分开**：这里多一个【报道对象】，
## 而「日期 / 地点 / 截止时间」这些邮件专用字段一个都不给。
static func _context(entry: Dictionary, code: String, cast: int, fame_now: int) -> Dictionary:
	var bal := BalanceLibrary.data()
	var company := CompanyLibrary.by_code(code)
	var role_tier := int(entry.get("role_tier", 0))
	var cast_label := String(RoleRequirement.TIER_NAMES.get(role_tier, ""))
	var named := fame_now >= bal.fame_named_threshold
	var referent := String(entry.get("role_name", ""))
	if named:
		referent = _player_name()
	elif cast != BalanceData.Cast.EXTRA:
		referent = cast_label
	return {
		"玩家名": _player_name(),
		"公司名": company.display_name if company != null else code,
		"剧名": String(entry.get("play_title", "")),
		"角色名": String(entry.get("role_name", "")),
		"角色定位": cast_label,
		"报道对象": referent,
	}


static func _player_name() -> String:
	var pool := MailLibrary.casting_pool()
	return pool.player_name if pool != null else ""


## 取一条标题并填字段。取不到返回空 text（周报会跳过）。
## `extra` 用来覆盖个别字段 —— 保留这个口子是为了将来「同一事件两条标题」能复用。
static func _fill(h: Headline, extra: Dictionary, ctx: Dictionary) -> Dictionary:
	if h == null:
		return {"id": &"", "text": "", "kind": &""}
	var merged := ctx.duplicate()
	for k: String in extra:
		merged[k] = extra[k]
	return {
		"id": h.id,
		"text": MailComposer.fill(h.text, merged),
		"kind": h.kind,
	}
