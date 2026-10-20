class_name ScriptDoc
extends Resource
## 一份「只包含一个角色」的剧本 —— 微信里 HR 发过来的那个 `.docx`
##
## 【它和 `data/scripts/剧本N_*.md` 的关系】md 是内容源（docx 的可读副本），
## 但 **md 进不了导出包**，所以由 `tools/gen_scripts.gd` 转成 `.tres` ——
## 与邮件 / 招聘页 / 事件同一套。改文案改 md，然后重跑那个脚本。
##
## 【一份 = 一个视角】md 里每份剧本有三节「## 视角N：角色名」，
## **一节就是一份文档**：只包含这个角色的戏，别的角色不会出现在他的文档里。
## 视角顺序就是档位顺序（1 = 龙套 / 2 = 配角 / 3 = 主角）——
## 这条口径 md 里没写，是提提 10-16 按「场景数 1 → 2~3 → 4~5 递增」定的，
## 生成脚本里有完整理由。
##
## 【body 原文照搬】含 `[试镜批注]` 段落与 `【拼贴表情轮 → 条件见 playX_vY_sZ】` 标记
## （10-16 拍的板：先照搬，内部机制露出来也认）。只剥掉 markdown 的**壳** ——
## `> ` 引用符号、`| a | b |` 的表格线、标题的 `###`：Label 不认 markdown，
## 留着就是给玩家看乱码。

@export var id: StringName = &""          ## `play1_v3` —— 与 md 里的「角色代号」一致
@export var play_index: int = 0            ## 1 / 2 / 3 —— 抽签抽的是「三份里的哪一份」
@export var play_title: String = ""        ## 青春嘉豪 / 穿越宫斗 / 极寒末世
@export var role_name: String = ""         ## 男主 / 贵妃 / 白月光
@export var tier: int = 0                  ## RoleRequirement.Tier
@export var scene_count: int = 0           ## 这个视角有几场戏（md 的「场景数」）
@export_multiline var body: String = ""    ## 正文，原文照搬（见类注释）

## 每场戏的**拼贴需求**（关键词表「三个剧本 - 表情拼贴轮需求数值汇总」那段）。
## 外层下标 = 场景号 - 1（长度应等于 scene_count）；内层是这场要**同时**演出的几个
## 复合情绪，每项 `{"name": "支配", "parts": {"愤怒": 25, "信任": 25}}` ——
## parts 的键是关键词表那 8 种基础情绪，值的和就是这条需求的满分。
## 【只给录像机 UI 用】真正的试镜判定仍走公司的 AuditionCondition，两套别混。
@export var scene_demands: Array = []


func tier_name() -> String:
	return String(RoleRequirement.TIER_NAMES.get(tier, "?"))


## 聊天窗口里那个文件名。格式：**剧本标题-角色名·档位名.docx**
## 【为什么两样都写】文件名是玩家唯一能一眼看出「这份是给谁的、哪个档」的地方 ——
## 只写角色名（男主）看不出档位，只写档位（主角）看不出演谁。
func file_name() -> String:
	return "%s-%s·%s.docx" % [play_title, role_name, tier_name()]


## 像真微信那样在文件卡上标一个大小。按 UTF-8 字节数算 —— 中文一个字 3 字节，
## 一份几百字的剧本落在几 K 到十几 K，与真 .docx 是同一个量级。
func size_text() -> String:
	return "%.1fK" % (float(body.to_utf8_buffer().size()) / 1024.0)
