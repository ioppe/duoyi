# Web 自动部署（自托管站点）

现有站点 <https://todo.skydrow.site> 由自托管服务器提供。开启自动部署后，推送到 `main` 的 Web 构建会在同一次 GitHub Actions 运行中，把本次 `web` 作业产出的桌面包发布到该站点；发布失败不会改变线上 `current`，也不需要手工拷贝文件到服务器。

各开发分支合并进入 `main` 后，生产站点以主线的同次构建产物为准。此部署链只发布 Web 静态资源，不重建后端、不迁移数据库、不修改 Nginx；线上版本与提交以公开的 `duoyi-deployment.json` 和 `version.json` 为准。

## 需要用户做什么

1. 在 GitHub 网页登录仓库，进入 **Settings → Secrets and variables → Actions → New repository secret**。
2. 名称只用一个：`DUOYI_WEB_DEPLOY_SSH_KEY`。值是该专用部署密钥的 **OpenSSH 私钥全文**（含 `-----BEGIN OPENSSH PRIVATE KEY-----` 与结束行）。
3. 保持分支 `main` 的现有 Web 构建可用；下一次推送到该分支即自动发布。

Secrets 只用网页登录管理，不需要 GitHub token 或命令行 `gh`。Secret 不随 Fork 复制；缺失时 `deploy-self-hosted-web` 作业会明确报错失败，不会假成功。

首次启用前必须先完成下一节的服务端入口安装并添加这个唯一 Secret；两项就绪后，下一次推送到 `main` 即自动发布。

## 已固定的服务器入口

主代理负责安装以下内容（已包含在代码库）：

- `/usr/local/sbin/duoyi-web-deploy`：将 `scripts/deploy_web_server.py` 安装为此路径（`root:root`、`0755`，只依赖 Python 3.12+ 标准库）。
- `/etc/duoyi/web-deploy.json`：公开 profile，对应仓库 `config/web-deploy.json`，仅含 host、port、user、branch、`public_url`、`web_root`、`releases_root`，不含私钥。
- `/root/.ssh/authorized_keys`：只给专用部署公钥加一条受限项，强制固定命令：

  ```text
  restrict,command="/usr/local/sbin/duoyi-web-deploy" ssh-ed25519 <部署公钥> duoyi-web-deploy
  ```

  该密钥只能执行 `status` 或 `deploy <40位提交SHA> <64位归档SHA256>`；程序不接受客户端传入的目录、URL 或命令，不经过 shell。
- 主机指纹已固定在仓库 `config/web-deploy.known_hosts`，CI 使用 `StrictHostKeyChecking=yes` 与 `UserKnownHostsFile`，不做绕过。

安装只需放脚本、写 profile、追加 authorized_keys；SSH 仍是现有 22 端口和 root，无需改 sshd。

首次启用时 `/var/www/duoyi/current` 指向 `/var/www/duoyi/releases/v1.1.47-1944aed-startup-sync` 的软链接，`releases` 是实体目录。服务器入口要求保持这一布局：`current` 不是软链接、`releases` 不是实体目录或旧目标不在 `releases` 内时直接拒绝发布，不会把普通目录当站点清空。

## 发布范围

- 仅 `github.event_name == 'push'` 且 `github.ref == 'refs/heads/main'`，并且同一次运行的 `web` 作业成功（`needs: [web]`）。
- 只取本次运行名为 `duoyi-web` 的 artifact 中的桌面包 `duoyi-web-desktop-YYYYMMDD-<sha7>.tar.gz`，文件名必须包含当前提交前 7 位；通用包与手机包不会用于发布。
- PR、非 `main` 分支、tag 与手动运行都不会触发自动部署；GitHub Pages 仍只在 `main` 部署，正式 Release 仍只在 `v*` tag 创建。
- 发布作业自身使用 concurrency `duoyi-production-web` 且 `cancel-in-progress: false`，因此多个发布作业之间不会互相取消；父工作流原有的 `build-<ref>` `cancel-in-progress: true` 仍然生效，同分支新推送仍可能取消整次运行（包括尚未完成的发布作业）。

## 发布协议与校验

`scripts/deploy_web_ci.py` 读取公开 profile，校验分支、完整 SHA、制品唯一性与私钥格式；私钥只从 `DUOYI_WEB_DEPLOY_SSH_KEY` 读取，写入 `0700` 临时目录中的 `0600` 文件，结束后立即删除，不打印内容。SSH 固定使用 `IdentitiesOnly=yes`、`BatchMode=yes`、`StrictHostKeyChecking=yes`、`ConnectTimeout=20`，远程命令严格为 `deploy <sha> <sha256>`，tar.gz 从 stdin 流入。

服务器端在 `/run/lock/duoyi-web-deploy.lock` 持排他锁，完成下载、校验、发布与回滚：

1. 流式计算归档 SHA256 并与参数比对，不匹配立即拒绝，站点不变。
2. 限制压缩包 512 MiB、展开 2 GiB、成员 20000；只接受普通文件与目录，拒绝绝对路径、`..`、符号链接、硬链接、设备/FIFO，归档不能逃出临时目录，也不执行包内任何内容。
3. 校验 `index.html`、`main.dart.js`、`version.json` 与 `index.html` 的 `<base href="/">`，`version.json` 的 `version`、`build_number` 必须有值；文件权限 644、目录 755，保证 Nginx 可读。
4. 在 `/var/www/duoyi/releases/` 生成 `<完整SHA>-<哈希前缀>` 目录，写入公开清单 `duoyi-deployment.json`（commit、archive_sha256、version、build、UTC 时间）；不覆盖已有目录。同一 SHA 重跑时核对该目录清单与哈希，幂等成功。
5. 先创建临时 symlink 再 `os.replace` 原子切换 `/var/www/duoyi/current`；旧版本目录保留，不清理。
6. 通过 `https://todo.skydrow.site/duoyi-deployment.json?sha=<sha>`（校验 TLS、超时、有限重试）核对线上清单的 commit 与 archive hash，并检查首页 HTTP 200。任何在线校验失败都会原子切回旧 symlink，作业以非零退出。

成功后可手工核对：

```bash
curl -fsS "https://todo.skydrow.site/duoyi-deployment.json?sha=<完整SHA>"
```

返回的 `commit`、`archive_sha256`、`version`、`build` 应与本次运行一致。

## 回滚与重跑

- 发布失败（校验、解包、Nginx 读取、线上清单不一致）：`current` 保持/恢复为旧版本，旧目录与站点继续可用，错误信息只含非敏感元数据。
- 发布进程收到 SIGTERM/SIGHUP 会转为可捕获错误并按上述逻辑回滚；SIGKILL/OOM 等无法捕获的终止可能留下 `releases/.stage-*` 临时目录。在切换 `current` 前被强杀时，线上指针保持不变；在切换与线上校验之间被强杀时，需人工确认 `current` 指向及站点健康。临时目录需运维确认没有发布运行后手工清理，发布程序不会自动扫描清理。
- 需要回退已发布版本：对引入问题的提交做普通 `git revert` 并再次推送到 `main`，新提交会发布新的 release 目录；服务器不会自动删除旧版本。
- 同一次运行重跑：同 SHA、同归档哈希会复用并校验既有 release 目录，再走一次在线校验，不会产生重复目录。
- 本地只读检查：

  ```bash
  python3 scripts/deploy_web_ci.py --check-config
  ```

## 安全边界

- 私钥只存在于 GitHub Secret 与 CI 的临时 0600 文件中；不进入仓库、制品、日志或本文档。
- 服务器入口固定读取 `/etc/duoyi/web-deploy.json`，无 shell、无任意命令、无站点树删除、不修改后端/数据库/Nginx，不清理老版本，也不引入第三方依赖。
- 前端发布只是写入独立 release 目录并切换 `current` symlink；后端数据（`/opt/duoyi/data`）和已登录账号不受影响。

## 常见失败

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 作业提示缺少 Secret | 未配置 `DUOYI_WEB_DEPLOY_SSH_KEY` | 按上文在网页添加后重跑 |
| `only pushes to refs/heads/main` | 分支或触发方式不符 | 从指定分支 push 触发 |
| `expected exactly one duoyi-web-desktop-*.tar.gz` | artifact 选错或构建未上传 | 确认同次运行的 `web` 成功并上传 `duoyi-web` |
| `Host key verification failed` | 服务器主机指纹变化 | 核实服务器后更新 `config/web-deploy.known_hosts`，不要关闭校验 |
| `online verification failed` | 线上清单/首页未更新或缓存异常 | 查看作业日志与 Nginx；`current` 已回滚 |
| `archive sha256 mismatch` | 传输或制品损坏 | 重跑同一次运行 |

维护时保持 profile、受限入口、manifest 校验与回滚语义；新增分支或改动目录布局必须先更新本文件与测试。
