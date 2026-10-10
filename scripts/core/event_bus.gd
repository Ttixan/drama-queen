extends Node
## 信号总线（Autoload 名：EventBus）
##
## 界面之间不互相引用，全部通过这里通信。
## 注意：这里是**唯一**允许继承 Node 的 core 类 —— 它只做信号转发，不含逻辑，
## 数值模拟器完全不加载它。

# ---- 时间 ----
signal day_advanced(day: int, week: int)
signal week_settled(report: Dictionary)
signal game_finished(ending_id: StringName)

# ---- 行动点 ----
signal ap_changed(left: int)

# ---- 属性变化 ----
signal money_changed(value: int, delta: int)
signal acting_changed(value: int, delta: int)
signal fame_changed(value: int, delta: int)
signal reputation_changed(value: int, delta: int)

# ---- 投递 ----
## 玩家在录像机完成了拼装并发送
signal audition_submitted(result: Dictionary)
## HR 回信（成功/失败），投递瞬间触发
signal hr_replied(company_code: String, passed: bool, mail: Dictionary)
## 表情包一次性消耗后进入作品集／履历
signal clip_recorded(clip_summary: String, labels: Array)

# ---- 录像机 → 微信 ----
## 玩家在录像机点「确认」，产出一段完整的 3 帧表情包。
## 这是录像机与投递之间的**唯一接口** —— 录像机不认识任何公司，也不知道怎么投递。
signal recorder_finished(clip: Clip)
## 微信里新解锁了一个 HR（先在 Boss直聘 逛过该公司）
signal hr_unlocked(company_code: String)

# ---- 播出反馈 ----
## 本周末的《有瓜有戏》
signal broadcast_published(week: int, headlines: Array)
## 黑红条件触发（不做成成就系统，只发一条标题）
signal black_fame_triggered()

# ---- 其他 ----
signal hint_received(company_code: String, text: String)
signal save_requested()
## 整个状态被换掉了（`Game.new_game()` 开新局 / `load_from()` 读档）。
## 界面收到后必须**清掉自己的全部显示状态** —— 否则重开时玩家会看到上一局的
## 联系人和待投递表情包还挂在那里。两者对界面来说没有区别，所以共用一条信号。
signal state_reset()
