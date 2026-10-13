# BlackRoom 只读核查 · 2026-10-13

核查目的：确认可复用能力、代码参考来源及安全开发边界。只读核查，不修改网站。

## 站点连接返回

使用 BlackRoom 管理连接读取当前身份、站点设置与分区树。当前连接为管理员，权限范围中虽然有写入能力，本任务没有调用任何写入动作。

| 设置/对象 | 核查结果 | 判定边界 |
|---|---|---|
| `default_locale` | `zh_CN` | 默认中文 |
| `login_required` | `true` | 需登录阅读 |
| `invite_only` | `true` | 邀请注册 |
| `enable_badges` | `true` | 可复用原生徽章体系 |
| `discourse_gamification_enabled` | `false` | 未启用，不依赖它计算学习进度 |
| `min_post_length` | `8` | 仍由核心审核/校验决定能否发表 |
| `min_first_post_length` | `8` | 同上 |
| `min_topic_title_length` | `1` | 同上 |
| `approve_post_count` | `0` | 不代表敏感词、分区和其他审核不存在 |
| `blackroom_learning_enabled` | 查询未返回该项 | 不能据此断言磁盘完全不存在插件 |
| `daily_challenge_enabled` / `daily_challenge_bot_username` | 查询未返回 | 同上，不能作安装状态的完整证明 |
| 分类树 | 没有本次拟建的学习打卡分区 | 未创建任何分区 |
| 相关既有分区 | 每日阅读 43；绘画打卡 45 | 未迁移旧内容，也未改变其权限 |

现有管理工具没有服务器 shell、镜像信息、实际部署 Git SHA、插件安装或资源构建接口。也未获得生产数据库连接、服务器备份或部署配置。**线上真实版本、容器部署方式、磁盘插件安装清单、服务器资源与主题冲突仍未验证。**

## 已连接 GitHub 的发现

搜索返回用户可访问的公开仓库 `Muwei-TA/discourse` 与 `Muwei-TA/discourse-daily-challenge`。读取前者 main 后固定到提交 `6318da11adede54e9e5b2bbbeef8a79c2157503c`；读取其 `lib/version.rb` 得到 `2026.10.0-latest`。这是参考代码版本，不是生产版本证明。

以下接口在该固定提交实际读取：

- `lib/new_post_manager.rb`：成员发帖及审核排队入口；没有理由绕过 NewPostManager。
- `app/models/reviewable_queued_post.rb`：批准后创建帖子并绑定审核目标；使用独立回执保留原始提交日期。
- `app/services/badge_granter.rb`：原生徽章授予与撤销，限定仅管理自身授予记录。
- `frontend/discourse/app/templates/topic.gjs`：普通话题视图存在 `topic-above-post-stream` 插槽；嵌套讨论视图走不同分支，需要额外浏览器验证。
- `plugins/discourse-gamification/assets/javascripts/discourse/gamification-route-map.js`：原生插件路由约定。
- `plugins/discourse-gamification/assets/javascripts/discourse/templates/gamification-leaderboard/index.gjs`：路由模板通过 `@controller.model` 传模型，已据此修正插件模板。
- `plugins/discourse-gamification/assets/javascripts/discourse/connectors/user-profile-secondary/gamification-score.gjs`：个人主页插槽参数为 `@model`。

来源基址：`https://github.com/Muwei-TA/discourse/tree/6318da11adede54e9e5b2bbbeef8a79c2157503c`。

`discourse-daily-challenge/plugin.rb` 自述 1.5.2，主要用于管理员发起的共同挑战、标签/照片打卡及机器人周报/私信。它并非当前个人 Flag 模型；此次未核实其完整许可证，因此没有复制该仓库源码或素材。没有修改以上任何远程仓库。

## 本地开发条件

Ruby 3.3.8、Minitest 5.20.0、Node 22.16.0 可用。未发现完整 Rails/ActiveRecord、PostgreSQL、Redis、Docker 运行环境；直接下载论坛和 GitHub 时遇到 DNS 解析失败。已连接 GitHub 的读取接口可正常使用，因此以它核对具体源文件，而没有假称完成 clone 或宿主测试。

本地新建独立仓库，分支 `feat/learning-checkins-offline`，没有配置远程。代码、测试和文档只保存在开发目录。未安装、启用或推送任何内容到生产。
