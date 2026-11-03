# Web 字体延迟加载验证

## 已执行

实际 Flutter 3.44.1 release 构建；本地只读静态预览使用公开 API 配置快照，无真实账号登录/写入。浏览器为独立会话，未使用原有用户登录态。

- `validation.json`：实际 Resource Timing、Performance marks 和真实 CDP 输入记录。
- `loaded-login.png`：完整字体后台成功注册后的空登录页。
- `loaded-input-retained.png`：CDP 鼠标点击并输入后，完整字体注册完成，用户名仍为 `font-input-kept`。此图与空登录页为不同截图。
- `blocked-font-ready.png`：完整字体返回 503 后，页面仍可操作。
- `chinese-startup-subset.png`：使用子集显示的中文登录页。
- `rare-glyph-fallback.png`：完整字体 503，仍能显示并保留“测试密码龘”，回退切片均返回 200。

| 本地冷启动观测 | 实测 |
|---|---:|
| 启动子集请求次数 | 1 |
| 子集原始字节 | 2,098,692 |
| 子集 gzip 传输（含响应头） | 1,417,924 |
| Flutter 首帧标记 | 3.45 s |
| 浏览器 FCP | 3.99 s |
| 完整字体开始 | 18.46 s |
| 完整字体后台完成 | 18.95 s |
| 完整字体请求次数 | 1 |

时长只代表该浏览器/本地预览，不是生产速度承诺。核心验收是完整字库开始晚于 Flutter 首帧标记约 15 秒，且首屏不等它。

失败场景由独立预览服务器对完整字体真实返回 503；启动子集仍 200，`duoyi-font-error` 被记录，登录表单仍可切换密码显示。输入保持最终使用 CDP 真实鼠标点击和 `Input.insertText` 验证：完整字体尚未请求时输入 `font-input-kept`，注册完成后值仍保留。另输入并显示“测试密码龘”，CanvasKit 约 94 KB 的回退切片均返回 200，完整字体失败后输入仍保留。早期 CLI 拦截/填值无效尝试未记为产品通过。没有发送登录请求。

## 自动验证

- Python 字体构建政策与既有部署配置：28 tests 通过。
- Flutter 延迟加载、typography、l10n、Web 部署和启动静态门禁：25 tests 通过。
- 全项目 `dart analyze`：0 issues；新增 Dart 格式检查：0 changes。
- Web release：通过；manifest 只有一个变量子集登记，完整字库仅保留为延迟 asset，OFL 存在。

## 未覆盖/边界

- 未执行真实账号同步、完整 Android/macOS 应用构建或全仓回归门禁。
- 未宣称任意语言首次离线可显示：子集外罕见字保留 CanvasKit 按需字形回退，可能下载额外小字库；完整字库下载失败不阻塞已有界面。
- 网络/省流/后台 skip 和下载超时由定向服务测试覆盖。公网冷启动数据已补入 `validation.json`，见下节。

## 公网部署复验

已发布至 `https://todo.skydrow.site/`，release 目录 `v1.1.47-9332b18-webfonts`（实现提交 `9332b18`），保留旧 preload 目录回滚；后端容器未修改。

- 公网 JS、bootstrap、FontManifest 和字体政策文件与本地构建 SHA-256 一致；HTML 仅多了 Cloudflare 注入脚本，没有完整字体 preload，响应 `no-store`。
- 全新浏览器正常打开无查询参数首页：启动子集只请求 1 次，传输 1,470,060 B；Flutter 首帧标记 6.71 s，FCP 7.24 s。
- 首帧时完整字体请求数为 0；21.71 s 才开始一次完整字体请求，25.47 s 完成后台注册，延后 15.00 s。
- 公网该会话完整字体实际传输 17,772,600 B（含响应头），但已完全移出首屏关键链路。另用 curl Brotli 请求子集为 1,401,042 B，浏览器和 curl 使用的压缩编码/缓存响应可能不同。
- `production-login.png` 为公网实际 release 页面。时长仅为这次测量，不能当作所有用户的加载承诺。
