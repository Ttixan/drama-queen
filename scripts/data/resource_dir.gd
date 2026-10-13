class_name ResourceDir
extends RefCounted
## 读 `res://` 目录下的 `.tres` —— **编辑器与导出包两种形态都得出全**
##
## 【这是踩过坑的地方，动它之前先读完】
## 导出时 Godot 会把文本资源转成二进制：真身 `xxx.res` 被塞进
## `res://.godot/exported/<id>/`，原路径上只留一个叫 `xxx.tres.remap`
## 的跳板文件，里面写着「真身在哪」。于是同一条目录，两种形态：
##
##     brows_00.tres              ← 编辑器里
##     brows_00.tres.remap        ← 打包之后（DirAccess 返回的就是这个）
##
## 所以 `if not f.ends_with(".tres"): continue` 这种写法在编辑器里全对，
## 一打包就**一个都匹配不上** —— 32 件部件读成 0 件，录像机没有表情、
## 微信没有回信模板。这个坑在编辑器里跑任何测试都看不出来，
## 只有真打一次包才会现形。
##
## 【为什么剥掉 .remap 之后仍要 load 原路径】
## `ResourceLoader` 自己会去找 `<路径>.remap` 并顺着它拿到真身。
## 正确姿势是「还原出原始 .tres 路径 → load 它」，而不是去 load 那个 .remap。
##
## 【约定】凡是要「列出某目录下的 .tres」，都必须走这里，别再手写 DirAccess 循环。


## 列出 dir_path 下所有 `.tres` 的**原始资源路径**（可直接交给 load）。
##
## 顺序按文件名升序 —— `DirAccess` 的天然顺序不保证稳定，而部件页签、
## 联系人列表的顺序一变，玩家的肌肉记忆就废了。
static func list_tres(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("[ResourceDir] 打不开目录 " + dir_path)
		return out
	var names := dir.get_files()
	names.sort()
	for f: String in names:
		var name := strip_remap(f)
		if name.ends_with(".tres"):
			out.append("%s/%s" % [dir_path, name])
	return out


## `xxx.tres.remap` → `xxx.tres`；导出包与编辑器两种名字都收敛到后者。
## 【为什么公开】测试要能直接验这一步 —— 它是整条链上唯一认得出导出形态的地方。
static func strip_remap(file_name: String) -> String:
	return file_name.trim_suffix(".remap")
