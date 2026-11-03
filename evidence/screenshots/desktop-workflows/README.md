# 今日昵称、桌面弹窗、主导航与任务截止期验证

本轮版本为 `1.1.47+140013`。截图来自本机隔离 fixture 中实际运行的 Release Web 包；使用可丢弃账号与固定 AI 回复，不包含生产登录或真实模型调用。

本轮行为：

- “今日”和“我的”共用显示名解析，优先使用已登录账号昵称，资料变更后立即更新，并保留空白、默认名及账号切换回退。
- Web（包括窄屏）及原生 macOS 的共享底部模态入口改为居中弹窗，使用轻淡入与小幅缩放；减少动画设置直接到位。Android/iOS 原生底部面板保留。
- 一级导航默认保留“今日 / 习惯 / 专注 / 我的”。旧导航偏好中的“待办”入口会定向清洗，其他有效设置保留；任务数据、任务业务、四象限和旧深链继续可用。
- 新建任务可独立选择截止日期和可选时刻，支持清除时刻或全部清除。自然语言与 AI 可回填；手动确认或清除后的值拥有优先权。截止期与任务进入日期、提醒分开；纯日期保持纯日期，夏令时不存在的时刻会阻止保存。

自动验证详情见 [validation.json](validation.json)：

| 检查 | 结果 |
| --- | --- |
| 固定工具链 | Flutter 3.44.1 / Dart 3.12.1，测试 `TZ=UTC` |
| 完整 Flutter 测试 | 345 个文件，2,392 passed，0 failed / errors / skipped |
| 后端完整 unittest | 308 passed |
| 全项目 Dart 分析 | 0 issues |
| 29 个变更或新增 Dart 文件格式检查 | 0 changed |
| `git diff --check` | 通过 |
| Release Web | 403 个构建输入前后稳定；120 个运行时文件，107,520,656 字节 |
| 主 JS SHA-256 | `f4fa7a0d51c45531636852f1488b76dd174a620cc16ac56d17b7df036152a021` |
| 原始工作区只读保护 | 27 个重叠文件内容不变，均与隔离仓库使用不同文件对象 |

浏览器实际交互结果见 [browser-validation.json](browser-validation.json)：9 个必需场景全部通过，1 个可选场景未执行；1280×1000、390×844、320×720 三种视口，12 张截图，控制台和页面异常记录为空。覆盖真实昵称修改与刷新、弹窗关闭与焦点循环、嵌套选择器、手动/AI 截止期及保存值、迟到 AI 清除保护、目标/便签、旧导航偏好迁移。可选深色、减少动画和文字放大未在浏览器中验证，相关 Flutter 测试通过。

验收中的 AI 行为观察已与改动前实现核对，结论见 [observation-disposition.json](observation-disposition.json)。AI 标题建议、进入日期安排和明确未来时刻的自动提醒保持既有行为；手动截止期只管理独立截止期，不代替提醒开关。

以下为实际截图：

| 截图 | 内容 |
| --- | --- |
| [01](01-today-1280x1000-login-nickname.png) | 登录后首页及四项主导航 |
| [02](02-profile-nickname-typed-before-save.png) | 在个人资料实际输入新昵称 |
| [03](03-today-nickname-updated.png) | 首页显示更新后的昵称 |
| [04](04-new-task-sheet-1280x1000.png) | 居中新建任务弹窗 |
| [05](05-nested-date-picker-1280x1000.png) | 弹窗内嵌套日期选择器 |
| [06](06-manual-due-date-time-1280x1000.png) | 独立设置截止日期与时刻 |
| [07](07-ai-prefill-2030-01-08-1530.png) | AI 回填具体日期、时刻和子任务 |
| [08](08-ai-date-only-2030-01-09.png) | AI 纯日期结果 |
| [09](09-late-ai-result-cleared-due-date.png) | 手动清除后迟到 AI 不覆盖截止期 |
| [10](10-goal-create-sheet-1280x1000.png) | 居中目标创建弹窗 |
| [11](11-mobile-390x844-today-nav.png) | 390×844 四项一级导航 |
| [12](12-mobile-320x720-nested-picker.png) | 320×720 居中嵌套日期选择器 |

验证边界：本机未安装验证原生 macOS 应用，也未验证签名、公证或 Gatekeeper；原生 macOS 呈现使用 Flutter 平台变体测试覆盖。没有测试真实 Android/iOS 软件键盘；浏览器缩放不等同于 Flutter `textScaler`。本目录的本地构建结果与最终提交、CI 安装包及生产发布之间的对应关系需要单独核验，不以截图替代发布收据。
