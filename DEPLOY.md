# 多仪 部署与发布

部署参数统一维护于 `config/deployment.json`；私密启动参数来自环境或 `backend/.env`。完整配置优先级、兼容与迁移说明见 [docs/configuration.md](docs/configuration.md)。

## 总体架构

- **安装客户端**：登录页可配置服务器地址并通过访问令牌连接；**Web**：默认使用当前站点后端；
- **后端 (FastAPI)**：单一 SQLite，自持全部数据；
- **管理员**：登录后进入"管理员后台"远程配置 AI / 云端备份 / 公告 / 用户；
- **普通用户**：注册登录后直接用，看不到任何技术细节。

```
┌─────────────────────┐         ┌────────────────────┐
│  APK / Web 客户端   │         │  FastAPI (SQLite)  │
│  安装端: 地址+令牌  │────────▶│  /api/auth         │
│  Web: 当前站点后端  │         │  /api/sync         │
│                     │         │  /api/ai/chat (代理)│
└─────────────────────┘         │  /api/admin/*      │
         ▲                      └────────────────────┘
         │  管理员登录同一个 APP 进入"管理员后台"
         │  → 改 AI key / 开关云备份 / 维护模式 …
```

## Android 全屏提醒权限说明

**Android 10+ (API 29+) 需要用户手动授权全屏 Intent 权限**，否则锁屏/后台时提醒只会响铃，不会弹出全屏界面。

应用已在 `AndroidManifest.xml` 中声明：
```xml
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
```

用户首次使用提醒功能时，系统会提示授权。如果用户跳过，可在以下位置手动开启：
- **设置 → 应用 → 多仪 → 通知 → 允许全屏通知**

该权限仅影响锁屏/后台时的全屏弹窗，不影响通知栏提醒和响铃。

## 1. 后端

```bash
cd backend
pip install -r requirements.txt

cp .env.example .env
# 编辑私有 .env：新建管理员需 ADMIN_BOOTSTRAP_PASSWORD。
# 公开后端地址、更新仓库和部署路径来自 config/deployment.json。
# AI/注册/邮件等环境值只补齐缺失的数据库设置，管理员已保存的值继续生效。

uvicorn main:app --host 0.0.0.0 --port 8000
```

首次启动创建 `duoyi.db`；已有旧库会按兼容规则继续使用。同名 bootstrap 管理员存在时不会重置密码，升级必须保留原密码 salt。

### 生产后端发布

GitHub Release 发布客户端产物；后端代码、配置模块与镜像需按部署流程更新。运行器、容器/服务名和健康检查地址由公开 profile 提供。先检查目标：

```bash
bash scripts/deploy_backend_prod.sh --check-config
```

确认已更新后端文件；Docker 发布需构建镜像并重建容器，保留现有数据目录和私密环境配置，再执行重启验证：

```bash
./scripts/deploy_backend_prod.sh
```

脚本会执行并验证：

- 重启配置指定的 Docker 容器或 systemd 服务；
- 本机 `/api/config` 可访问；
- 公网 `/api/config` 可访问；
- `/api/theme-shop/apply` 路由已加载，未登录时应返回 401 而不是 404；
- `/api/focus-rooms/deep_work_room/ranking` 路由已加载，未登录时应返回 401 而不是 404。

### 管理员登录后可做什么

进入 "我的 → 管理员后台" → 8 个 Tab：

| Tab | 内容 |
|---|---|
| 概览 | 用户 / 反馈 / 公告 / 邀请码 KPI + 7 日注册趋势 + 当前连接的服务器地址提示 |
| 全站设置 | 允许注册 · 是否需要邀请码 · 维护模式 + 维护文案 |
| **AI 配置** | 启用开关 · Base URL · API Key · 模型 · 每日限额 · **一键测试连接** |
| **云端备份** | 启用开关 · 单用户最大 payload · 最小自动同步间隔 · 保留天数 + **按用户看备份大小 / 清空某用户云端数据** |
| 用户 | 搜索 / 提权 / 禁用 / 重置密码 / 删除 |
| 公告 | 发布 · 编辑 · 草稿 / 上下架 |
| 反馈 | 过滤状态 · 回复 · 删除 |
| 邀请码 | 批量生成 · 复制 · 删除未使用 |

API Key / 其他敏感字段都只驻留后端 SQLite，读出时返回掩码 (`sk-***xyz`)；前端永远拿不到明文。

## 2. APK 客户端

**构建值仅作为安装端初始服务器地址，可在登录页修改**：

```bash
# 读取经过校验的公开部署配置
python3 scripts/flutter_with_config.py build apk --release

# 或明确覆盖某个公开值
python3 scripts/flutter_with_config.py build apk --release --dart-define=DUOYI_SERVER_URL=https://duoyi.example.com
```

安装后可填写自己的服务器地址和访问令牌。令牌在网页版“我的 → 个人资料 → 访问令牌”创建并单独撤销，完整令牌只显示一次。账号密码与邮箱登录入口继续可用。

## 3. Web 客户端

### 默认使用当前站点后端

```bash
python3 scripts/flutter_with_config.py build web --release --base-href=/duoyi/
```

Web 的 `/api/*`、`/ws/*` 默认请求当前站点，`DUOYI_SERVER_URL` 不会将 Web 凭据重定向到其他实例。静态文件与后端分开托管时，在前端域名设置 API 和 WebSocket 反向代理。

### 同域反代部署 (推荐)

```bash
# 留空: 走相对路径
python3 scripts/flutter_with_config.py build web --release --base-href=/duoyi/ --dart-define=DUOYI_SERVER_URL=
```

nginx 配置：

```nginx
server {
  listen 443 ssl;
  server_name duoyi.example.com;

  root /var/www/duoyi/web;
  index index.html;

  location /api/ {
    proxy_pass http://127.0.0.1:8000;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $remote_addr;
  }
  location /ws/ {
    proxy_pass http://127.0.0.1:8000;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 3600s;
  }
  location / {
    try_files $uri $uri/ /index.html;
  }
}
```

同域时 CORS 不用配，前端直接打 `/api/…`。

## 4. 普通用户视角

Web 用户直接登录账号；安装版用户填写服务器地址与访问令牌，或使用账号密码入口。

AI Key、代理模型密钥和数据库配置仍由管理员在后端管理。用户可在“个人资料 → 访问令牌”查看自己的设备连接、最近使用时间与有效期。

界面语言与应用时区默认跟随系统。用户可在“我的 → 个性设置 → 日期与日历 → 界面语言”固定语言，或在同处的“应用时区”固定 IANA 时区；两者都会立即生效并保存在本机，不需要重启。所选时区只改变应用内的壁钟语义（今日、日历、按天统计、习惯周期、提醒时刻、日期格式），同步时间戳与计时已流逝时长仍按真实瞬时处理。详见 [docs/configuration.md](docs/configuration.md#语言与应用时区)。

他们可以使用：
- 所有功能模块 (待办/习惯/日历/专注/笔记/日记/纪念日/目标/课程表/黄历/倒数日)
- 每天登录后在后台自动同步(管理员未关闭的话)
- "我的 → 立即同步" 一键按钮
- 当 AI 可用时，任务拆解 + 每周 AI 回顾

如果管理员关掉云备份或关掉 AI，对应入口就不会显示，用户也不会看到"未配置"之类的提示。

## 5. 数据迁移与安全

- `sync_data` 表启动时自动 `ALTER TABLE ADD COLUMN` 补齐字段；
- 最后一位活跃管理员不能被降权/禁用/删除(服务端兜底)；
- 禁用用户或重置密码会立刻吊销其 token；
- 同步 payload 默认限制 2048 KB，防止恶意用户塞满磁盘；
- AI 调用按 `user_id + 当天` 计数，超限 HTTP 429；
- API Key 读接口只返回掩码，且写入时如传入包含 `***` 的旧值会被视为"不修改"。
