# 接口与数据约定

全部接口继承 Discourse 当前会话、登录与 CSRF 防护；不需要在浏览器放管理员 API 密钥。客户端无权指定作者、奖励数额、原始提交时间或审核结果。`/learning` 为页面；数据接口使用 `/learning/data.json`。

| 方法/路径 | 参数 | 返回 |
|---|---|---|
| GET `/learning/data.json` | 可选 `page`、`username`、`goal_id` | `goals`、`my_goals`、`next_page`、`summary`、服务器日期、Flag链接 |
| POST `/learning/goals.json` | `name`、`commitment`、`starts_on`、`ends_on`、`target_days`、`request_key` | 当前目标、提交状态；发布201/审核202 |
| POST `/learning/checkins.json` | `goal_id`、`title`、`raw`、`request_key` | 同上 |
| POST `/learning/goals/:id/cancel.json` | 无作者/日期参数 | 成功200，保留旧记录 |

POST 表单可提供普通编辑器使用的 `typing_duration_msecs` 与 `composer_open_duration_msecs`。不以伪造长输入时间逃避新用户检查，也不设置 `skip_guardian`、`skip_validations` 等参数。

`request_key` 是前端生成的 UUID。同一成员、同一编号、同一内容重试返回原结果；相同编号但内容不同返回409，不另创建帖子。网络断开时先原样重试或刷新确认；收到明确结果前不要另生成编号重发。参数或目标状态错误返回422；访问错误由核心拒绝。

`receipt.submitted_at` 来自服务器，在排队审核时就固定。`receipt.post_id` 在实际发表后绑定；审核导致的延迟不改变原始归属日期。只有明确关联的正常首帖计入，回复/私信/普通未关联话题不计。源话题移出原分类、首帖被移动到别的话题、隐藏/删除均失效。

XP 表为追加日志。展示数据在当前读者权限下从实时源状态投影，以免等待异步修复时泄露/显示已隐藏内容；落库有效日期与XP流水通过即时提交重算、after_commit任务和每小时补偿任务保持最终一致。插件没有接入 Gamification 全站积分，不影响其记分配置。

数据库有5张独立业务表；不新增或修改 Discourse 核心表列。用户删除通过数据库外键级联清理业务表，真实账号匿名化/合并和后台批处理行为仍必须做宿主集成验收。
