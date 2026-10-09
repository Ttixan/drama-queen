extends SceneTree
## 邮件模板 + 定角抽签验证 —— headless 跑
##
##   godot --headless --path <项目> --script res://tools/test_mail.gd
##
## 【为什么值得单测】邮件是玩家唯一能读到的「判定结果解释」。它坏掉的表现是
## 玩家收到一封写着「《【剧名】》试镜通过」的信 —— 而那是最难察觉、最掉价的一种脏。
## 这里把「没有漏网的方块」钉成断言。

const COMPANY_DIR := "res://data/companies"
const CODES: Array[String] = ["A", "B", "C", "D", "E"]
const TIERS := [RoleRequirement.Tier.EXTRA, RoleRequirement.Tier.SUPPORTING,
		RoleRequirement.Tier.LEAD]

var _failures: Array[String] = []
var _checks := 0
var _companies: Dictionary = {}


func _initialize() -> void:
	print("")
	print("=== 邮件模板 + 定角抽签验证 ===")
	print("")

	MailLibrary.reload()
	for code: String in CODES:
		_companies[code] = load("%s/%s.tres" % [COMPANY_DIR, code])

	print("[1] 模板库：五家公司一一对应")
	_check("模板数", MailLibrary.count(), 5)
	for code: String in CODES:
		var t := MailLibrary.for_company(code)
		_check("%s 有模板" % code, t != null, true)
		if t == null:
			continue
		_check("%s 的 company_code 对得上" % code, t.company_code, code)
		for passed in [true, false]:
			var letter := t.letter(passed)
			var tag := "%s %s" % [code, "成功" if passed else "失败"]
			_check("%s 有信" % tag, letter != null, true)
			if letter == null:
				continue
			_check("%s 主题非空" % tag, not letter.subject.strip_edges().is_empty(), true)
			_check("%s 正文非空" % tag, not letter.body.strip_edges().is_empty(), true)
			_check("%s 署名非空" % tag, not letter.signature.strip_edges().is_empty(), true)

	print("")
	print("[2] 定角池")
	var pool := MailLibrary.casting_pool()
	_check("定角池存在", pool != null, true)
	if pool == null:
		_finish()
		return
	_check("定角池没有空桶", str(pool.missing_buckets()), "[]")
	_check("主角名已定", not pool.player_name.strip_edges().is_empty(), true)
	print("   剧名 %d 个 / 地点 %d 个 / 角色名 龙套%d 配角%d 主角%d" % [
		pool.play_titles.size(), pool.places.size(),
		pool.role_names_extra.size(), pool.role_names_support.size(), pool.role_names_lead.size()])
	print("   当前主角名（占位）：%s" % pool.player_name)

	print("")
	print("[3] 抽签：可复现 + 按档位分池")
	var a := MailComposer.roll_casting(pool, 12345, RoleRequirement.Tier.LEAD)
	var b := MailComposer.roll_casting(pool, 12345, RoleRequirement.Tier.LEAD)
	_check("同 seed 抽两次结果一致", a == b, true)
	var titles := {}
	var seeds_ok := true
	for i in 40:
		var c := MailComposer.roll_casting(pool, i * 7919, RoleRequirement.Tier.EXTRA)
		titles[c["剧名"]] = true
		if not pool.role_names_extra.has(c["角色名"]):
			seeds_ok = false
		_check_quiet("抽出的地点在池子里", pool.places.has(c["地点"]), true)
	_check("不同 seed 至少抽出 3 种剧名（不是恒定值）", titles.size() >= 3, true)
	_check("龙套档的角色名全部来自龙套池", seeds_ok, true)
	for tier: int in TIERS:
		var got := MailComposer.roll_casting(pool, 2026 + tier, tier)
		_check("档位 %d 的角色名在对应池里" % tier, pool.role_names_for(tier).has(got["角色名"]), true)

	print("")
	print("[4] 填字段：五家 × 成败 × 三档，一封都不能有漏网的方块")
	var worst := ""
	var total := 0
	for code: String in CODES:
		var co: CompanyData = _companies[code]
		var t := MailLibrary.for_company(code)
		for tier: int in TIERS:
			var role := co.role_of(tier)
			var casting := MailComposer.roll_casting(pool, co.code.length() * 31 + tier, tier)
			for passed in [true, false]:
				var got := MailComposer.compose_reply(t, co, role, casting, 1, passed)
				total += 1
				var leftovers := MailComposer.find_leftovers(got["text"])
				if not leftovers.is_empty():
					worst = "%s/%s/%s: %s" % [code, role.tier_name(),
							"成功" if passed else "失败", str(leftovers)]
				_check_quiet("%s 主题无残留" % code, MailComposer.find_leftovers(got["subject"]).is_empty(), true)
				_check_quiet("%s 正文无残留" % code, MailComposer.find_leftovers(got["body"]).is_empty(), true)
				_check_quiet("%s 整封无残留" % code, leftovers.is_empty(), true)
	_check("10 家次 × 3 档 × 2 结果 = %d 封邮件全部填满" % total, worst, "")
	print("   抽查（A 公司 / 龙套 / 成功）：")
	var sample := MailComposer.compose_reply(
			MailLibrary.for_company("A"), _companies["A"],
			_companies["A"].role_of(RoleRequirement.Tier.EXTRA),
			MailComposer.roll_casting(pool, 20261009, RoleRequirement.Tier.EXTRA), 1, true)
	for line: String in sample["text"].split("\n"):
		print("     " + line)

	print("")
	print("[5] 公司真名的替换与回退")
	var fake := CompanyData.new()
	fake.code = "A"
	var ctx := {
		"玩家名": "某人", "剧名": "某剧", "角色名": "某角色", "角色定位": "龙套",
		"日期": "10 月 12 日", "地点": "某地", "截止时间": "10 月 10 日",
		"code": "A",
	}
	_check("无真名时保留裸公司名", MailComposer.fill("**A公司｜选角组**", ctx), "**A公司｜选角组**")
	var named := ctx.duplicate()
	named["company_name"] = "星河影业"
	named["公司名"] = "星河影业"
	_check("有真名时替换署名", MailComposer.fill("**A公司｜选角组**", named), "**星河影业｜选角组**")
	_check("有真名时替换【公司名】", MailComposer.fill("【公司名】的戏", named), "星河影业的戏")

	print("")
	print("[6] 日期推导（Day 1 = 2026-10-09）")
	_check("Day 1", MailComposer.date_label(1), "10 月 9 日")
	_check("Day 21（最后一天）", MailComposer.date_label(21), "10 月 29 日")
	_check("Day 23 跨月", MailComposer.date_label(23), "10 月 31 日")
	_check("Day 24 进入 11 月", MailComposer.date_label(24), "11 月 1 日")
	var dl := MailComposer.date_labels(1)
	_check("进组日期 = 投递日 + 3", dl["日期"], "10 月 12 日")
	_check("回复期限 = 投递日 + 1", dl["截止时间"], "10 月 10 日")

	_finish()


# ============================================================
func _check(label: String, got: Variant, want: Variant) -> void:
	_checks += 1
	if got != want:
		_failures.append("%s: 期望 %s，实际 %s" % [label, want, got])


## 循环里的断言：只累计失败，成功不刷屏
func _check_quiet(label: String, got: Variant, want: Variant) -> void:
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
