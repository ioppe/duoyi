# 主线集成与构建部署

`main` 汇总本仓库本地与 `origin` 的开发历史；外部 `upstream` 不在此次集成范围内。原有功能分支与工作区保留，未提交文件不属于分支提交历史，也不自动纳入发布。

## 集成的独立历史

初始 12 个本地/远端引用归并为以下三条独立历史，其余引用均被这些提交覆盖：

| 分支 | 集成的原始头提交 | 主要保留内容 |
| --- | --- | --- |
| `self-hosted-skydrow` | `2bb8fa9df214fb6edd943ce2329f637c1c32439a` | 任务详情自动保存、失败恢复、语言同步、本地 AI 与安全存储、安装包兼容修复 |
| `build/macos-dmg` | `e6dabd8fce7f2fc4461ba0c09e0d7dd087982964` | 批准 Logo、透明 macOS 图标、紧凑悬浮窗与跨屏几何、启动水合、持久会话、AI 周期档案、Web 延迟字体与受限部署 |
| `fix/android-input-settings-device-test` | `ac73ff69fc961ac335d5590e722b79b6e4a67632` | 平台字号比例与预览、专注应用选择、Android 小组件本地切页/刷新/后台控制、系统日历入口、输入布局修复 |

使用正常 merge 保留各条历史；不能用“版本号更大”代替祖先关系检查。合并后需要对以上完整 SHA 分别运行 `git merge-base --is-ancestor <SHA> main`，并检查新的远端提交。

## 合并后的共同约定

- 应用版本继续由 `pubspec.yaml` 与 `lib/core/app_version.dart` 共同维护。此次主线集成本身不重写已有标签，也不自动创建正式 Release。
- 批准 Logo 是 `#C85656` 红底与三块白色几何标记，母版为 `assets/logo/duoyi_app_logo.svg`，原始批准参考保持不变。Android 小组件及兼容生成入口复用同一母版；不引入第二套颜色或图形。见 [品牌资源](branding.md)。
- UI 继续使用 Noto Sans SC、400/500/600 语义字重和 Web 首帧后完整字体加载。字号基准与应用比例分开，Android 七档、其他平台八档；预览、保存取消和账号归属继续遵循 [配置契约](configuration.md)。
- 任务详情保留 600ms 防抖、串行保存、返回前写入与失败草稿恢复。桌面弹窗、键盘收起、四个一级导航和原生悬浮窗继续使用共享实现。 同步后的集合按批重载；单项失败仍完成其他集合及收尾动作，随后继续上报错误。旧导航迁移回写前重新核对偏好变更版本，避免覆盖并发用户设置。
- 应用 ID、签名身份、存储目录和 Web origin 保持稳定。账号私有缓存与凭据继续隔离，普通更新保留已保存的设备配置。

## 构建与发布

`.github/workflows/build-apk.yml` 是多平台构建入口。`main`、`self-hosted-skydrow`、`build/macos-dmg` 和 Android 测试分支 push 均保留安装包构建；Android、Web 与可复用 macOS 流程等待同一配置、分析与测试门禁。macOS 包仍未签名、未公证。

生产 Web 仅由 `main` 的 push 发布。部署任务下载同次 Actions 运行的桌面 Web 产物，验证完整提交 SHA 与压缩包 SHA-256，通过固定 SSH 主机密钥和受限发布器写入独立 release 目录，再原子切换 `current` 并进行 HTTPS 健康检查。标签和其他分支不发布生产 Web，GitHub Release 仍由版本标签触发。

生产发布只更新静态 Web。后端容器、数据库、Nginx 与凭据不随此流程修改；旧 Web release 保留以供回滚。服务器公共 profile 的 `branch` 与仓库 `config/web-deploy.json` 一致为 `main`。详见 [Web 自动部署](web-auto-deploy.md)。

交付必须同时核验：全部分支祖先关系、批准资源只读生成检查、Flutter 分析/测试、后端测试、相关原生检查，以及实际 `main` push 对应的构建与部署结果。线上 `duoyi-deployment.json`、`version.json`、服务器 `current` 与同次构建产物必须一致；本地测试通过或任务已启动均不能代替线上验证。
