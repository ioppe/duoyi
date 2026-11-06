# 文档索引

从 [项目首页](../README.md) 查看功能和快速启动，从 [部署入口](../DEPLOY.md) 查看部署与发布。需求、设计和功能契约统一维护在本目录；同一主题优先更新现有文档，避免新增一份互相漂移的总结。

## 需求、设计与实现基线

| 文档 | 用途 |
| --- | --- |
| [需求 v2](requirement-v2.md) | 当前需求、实现状态与验收标准 |
| [设计 v2](design-v2.md) | 共享界面、数据与交互约定 |
| [任务 v2](task-v2.md) | v2 任务组织与交付跟踪 |
| [早期需求](requirement.md)、[早期设计](design.md)、[早期任务](task.md) | 既有需求编号和实现基线；现行差异以 v2 与对应功能契约为准 |
| [对齐规格](../.kiro/specs/app-alignment-overhaul/requirements.md) | 自动化守卫和对齐任务仍引用的规格输入 |

## 配置、账号与数据

- [配置入口、优先级、语言与应用时区](configuration.md)
- [配置与登录会话持久化](configuration-persistence.md)
- [认证、角色与访问令牌](authentication.md)
- [云同步与冲突合并契约](cloud-sync-v2-contract.md)
- [AI 报告档案](ai-report-history.md)

## 功能约定

- [AI 待办拆解](ai-todo-breakdown.md)
- [任务详情与设置](task-detail-settings.md)
- [自定义清单选择器](list-group-picker.md)
- [统计周期与时区](statistics-periods.md)
- [目标需求矩阵](goal-requirement-matrix.md)
- [品牌 Logo 与资源来源](branding.md)

## 平台与构建部署

- [固定工具链配置](../config/toolchain.json)与[公开部署配置](../config/deployment.json)
- [Android 本地迭代与真机验证](android-local-testing.md)
- [Android 专注与应用更新](android-focus-updates.md)
- [macOS 客户端与打包](macos.md)
- [Web 字体加载](web-font-loading.md)、[Web 通知权限](web-notifications.md)
- [主线集成与发布核验](mainline-integration.md)
- [自托管构建与部署](self-hosting-skydrow.md)
- [受限 SSH Web 自动部署](web-auto-deploy.md)
- [版本发布说明](releases/)

## 验证与对齐依据

- [人工回归清单](manual-regression-checklist.md)
- [设备回归证据约定](device-regression-evidence.md)
- [空状态审计](empty-surface-audit.md)
- [功能对齐审计](zhijian-time-parity-audit.md)
- [竞品分析](competitive-analysis.md)

这些审计、规格和矩阵仍被脚本或测试引用，不能仅凭文件名包含“分析”就删除。正式版本说明、资源许可证及批准的 Logo 参考也属于应保留的项目资料。

## 文件归属

- 项目根目录保留项目入口、部署入口、代理开发指导、许可证和工具配置。
- `docs/` 存放持续维护的需求、设计、契约、操作说明与发布记录。
- `lib/`、`backend/`、各平台目录及 `assets/` 存放运行代码和实际资源；生成代码是否保留以工具链与仓库约定为准。
- `scripts/` 与 `test/` 存放可复用工具和回归检查。
- `evidence/` 存放关联源码或安装包的可核验结果；历史哈希清单记录的是当时的文件快照，不应随日常清理改写。
- `build/`、`dist/`、`web-artifacts/`、`test-results/` 等可再生产物由本地或 CI 生成，不提交到源码树。安装包从对应 Actions 产物或正式 Release 获取。
- 一次性 AI 分析、会话恢复提示词、临时交接和未整理的过程输出放在会话临时目录；需要长期保留的有效约定整理进对应文档。删除的旧文件可从 Git 历史追溯，无需另建一套归档副本。
