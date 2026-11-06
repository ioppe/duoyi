# 同账号专注合并最新 main：验证记录

本记录对应本地分支集成，不代表发布、生产部署或新一轮真机验收。此前 `focus-sync`、`focus-sync-device` 和 `focus-cloud-mobile` 中的记录及哈希仍对应各自当时的源码/APK 快照；其中“未提交”“尚未合并”的文字描述的是当时的验证现场。

## 集成输入

- 功能提交：`9c2c0ca2222a31acc92bb54ac44e795a6809bb2e`，`feat(focus): synchronize account focus across devices`。
- 最新主线：`0cf0448f77a36f7a834ada736a3cbac6c2f9e142`，本地 `main`、`origin/main` 与 GitHub API 复核结果一致。
- 使用正常三方 merge 保留双方历史。四个重叠文件 `AGENTS.md`、`docs/cloud-sync-v2-contract.md`、`docs/manual-regression-checklist.md`、`lib/main.dart` 均由 Git 自动合并，无未解决冲突。
- 保留主线 Android 下拉同步及文档/产物清理，同时保留专注协调器启动、账号代际失效与远端历史水合。额外在 `docs/README.md` 增加专注运行态契约入口。

## 源码绑定

验证 Git 树：`31a0b82f4aa0f26bf9e4f2b41be4da3bd0f594d9`。

从暂存 Git 对象导出 ASCII 物理目录，排除历史 `evidence/`，共 **1,257 个普通文件**、0 个符号链接。离线执行 `flutter pub get --offline --enforce-lockfile`；分析后再次逐文件核对源码与副本 SHA-256，差异为 0，暂存树一致。提交时仅在该树之外新增本验证记录，不改变产品源码。

Logo、批准参考及图标生成器，Android/macOS 构建工作流，Web 部署配置，版本文件与 `pubspec.lock` 均通过与输入主线的只读差异检查，没有变化。

## 本轮验证

| 检查 | 实测结果 |
| --- | --- |
| 后端运行态、登录会话、访问令牌、迁移和两项路由契约 | **92 项通过**，2.583 秒 |
| Flutter 定向测试主运行 | **266 项通过**，退出码 0 |
| 五文件补充运行 | **62 项通过**，退出码 0 |
| 正式 `flutter analyze --no-pub` | **No issues found**，7.9 秒，退出码 0 |
| 暂存区空白/冲突检查 | `git diff --cached --check` 通过，无未解决 index 条目 |
| 合并文档一致性 | 未发现本次合并引入的代码/契约矛盾；规范索引已补齐 |

后端命令使用[基础验证清单](README.md)中的 92 项定向入口，隔离数据库与环境文件。Flutter 主运行指定同一清单中的 20 个文件及以下 3 个主线入口：

- `test/services/manual_sync_refresh_test.dart`
- `test/widgets/app_pull_to_sync_test.dart`
- `test/widgets/sync_status_card_test.dart`

主运行日志没有明确体现其中 5 个指定文件，因此不凭该次运行宣称它们已覆盖。随后以单并发命令明确补跑，全部通过：

```bash
flutter test --no-pub --concurrency=1 --reporter expanded \
  test/services/focus_runtime_background_control_test.dart \
  test/screens/pomodoro_strict_focus_static_test.dart \
  test/services/rounded_typography_static_test.dart \
  test/services/android_widget_resources_test.dart \
  test/services/manual_sync_refresh_test.dart
```

两批测试计数分别记录，不将它们解释为整仓测试结果。完整日志与 1,257 文件哈希清单位于本会话 scratch：`focus-merge-backend-tests.log`、`focus-merge-flutter-tests.log`、`focus-merge-flutter-supplement.log`、`focus-merge-flutter-analysis.log`、`focus-main-merged-check-manifest.json`。

## 工作区保护与未覆盖范围

落地前复核主线工作区的 **180 个无关未跟踪文件**，路径、大小、修改时间与预存清单一致；与待落地跟踪路径冲突为 0。主线此前删除的 **37 个文件**均未恢复。最终本地 `main` 指针及落地后的清单复核由 Git 集成步骤确认。

本轮未执行全仓测试、E2E、安装包构建、真机重新安装或完整 macOS Runner 构建。本机缺少完整 Xcode；此前独立原生悬浮窗检查和手机验证仍只适用于原记录中的源码/安装包。未推送、部署、打标签或变更版本。
