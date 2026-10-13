extends SceneTree
## 数据目录读取的验证 —— 重点是**导出包形态**（`.tres.remap`）能不能认出来。
##
## 【为什么这条测试必须存在】
## 打包后 `DirAccess` 列出来的是 `xxx.tres.remap`，而编辑器里是 `xxx.tres`。
## 只判 `.tres` 结尾的写法在编辑器里全绿、一打包就 0 件 —— 录影机没有表情、
## 微信没有回信，都是这么来的。之前 11 条测试链全绿也没拦住它，
## 因为它们跑的全是编辑器形态。
##
## 这里用 `user://` 造一份**假的导出目录**（里面就放 `.tres.remap` 命名的空文件），
## 把「名字归一化」这一步钉死。真机验证另见 `docs/开发计划.md` 的打包装机流程。

const PROBE_DIR := "user://_resdir_probe"

var _failures: Array[String] = []
var _total := 0


func _initialize() -> void:
	_test_strip_remap()
	_test_export_shaped_dir()
	_test_real_dirs()
	_finish()


func _test_strip_remap() -> void:
	print("[1] 名字归一化")
	_check("导出包形态", ResourceDir.strip_remap("brows_00.tres.remap"), "brows_00.tres")
	_check("编辑器形态原样返回", ResourceDir.strip_remap("brows_00.tres"), "brows_00.tres")
	_check("两形态归一后相等",
			ResourceDir.strip_remap("A.tres.remap") == ResourceDir.strip_remap("A.tres"), true)
	# 只剥一层，别把正经后缀当 remap 切掉
	_check("不碰别的后缀", ResourceDir.strip_remap("headlines.md"), "headlines.md")
	print("   .tres.remap 与 .tres 收敛到同一个名字")


func _test_export_shaped_dir() -> void:
	print("[2] 假的导出目录：只认 .tres，且必须是原始路径")
	_wipe()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROBE_DIR))
	_write("b_rows.tres.remap")
	_write("a_col.tres.remap")
	_write("plain.tres")
	_write("note.md")
	_write("readme.txt")

	var got := ResourceDir.list_tres(PROBE_DIR)
	var want := PackedStringArray([
		"user://_resdir_probe/a_col.tres",
		"user://_resdir_probe/b_rows.tres",
		"user://_resdir_probe/plain.tres",
	])
	_check("数量（.md/.txt 不算）", got.size(), 3)
	_check("内容与顺序（升序、去掉 .remap）", Array(got), Array(want))
	# 返回值必须是**能直接 load 的原始路径**，不是 .remap
	for p: String in got:
		_check("%s 不带 .remap" % p.get_file(), p.ends_with(".remap"), false)
	_wipe()
	print("   3 个 .tres（含 2 个 .remap 形态）被认出，.md/.txt 被排除")


func _test_real_dirs() -> void:
	print("[3] 真实数据目录：游戏里那几个库真的读得到东西")
	for d: String in ["res://data/parts", "res://data/mails", "res://data/companies"]:
		_check("%s 非空" % d, ResourceDir.list_tres(d).size() > 0, true)
	# 返回的路径要真的能 load 出对应类型的资源 —— 这一步同时盯住「目录写错」
	var first := ResourceDir.list_tres("res://data/parts")
	if first.size() > 0:
		var res: Resource = load(first[0])
		_check("%s 能 load 出 PartData" % first[0].get_file(), res is PartData, true)

	PartLibrary.reload()
	MailLibrary.reload()
	_check("PartLibrary 读到 32 件", PartLibrary.count(), 32)
	_check("MailLibrary 读到 5 封", MailLibrary.count(), 5)
	print("   parts=%d  mails=%d（编辑器形态）" % [PartLibrary.count(), MailLibrary.count()])
	print("   ★打包后的形态由真机/导出包复查，见开发计划里的装机确认清单")


# ============================================================
func _write(name: String) -> void:
	var f := FileAccess.open("%s/%s" % [PROBE_DIR, name], FileAccess.WRITE)
	if f != null:
		f.store_string("x")
		f.close()


func _wipe() -> void:
	var abs_dir := ProjectSettings.globalize_path(PROBE_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		return
	var d := DirAccess.open(PROBE_DIR)
	if d == null:
		return
	for f: String in d.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [PROBE_DIR, f]))
	DirAccess.remove_absolute(abs_dir)


func _check(label: String, got: Variant, want: Variant) -> void:
	_total += 1
	if got == want:
		return
	_failures.append("%s：期望 %s，实际 %s" % [label, var_to_str(want), var_to_str(got)])


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("✅ 共 %d 项断言，全部通过" % _total)
		quit(0)
	else:
		print("❌ %d 项失败：" % _failures.size())
		for f: String in _failures:
			print("   - " + f)
		quit(1)
