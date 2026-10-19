# 配置抽离验证记录

验证对象：`self-hosted-skydrow` 分支上的客户端、后端、CI 与部署配置重构。

工具链：Flutter 3.44.1、Dart 3.12.1、Python 3.13（本地后端测试），CI Python 版本由 `config/toolchain.json` 固定为 3.12。

| 检查 | 实际结果 |
| --- | --- |
| 后端 API、启动配置、公共配置与构建入口测试 | 189 项通过 |
| 配置相关 Flutter 测试（含更新、权限、网络和设备脚本） | 124 项通过 |
| Flutter analyze | 0 个问题 |
| Web release 构建 | 成功，产物中包含自建后端与 Fork 更新源 |
| Web 编译参数核对 | `https://todo.skydrow.site`、`ioppe/duoyi`、根路径 `/`；未包含旧后端地址 |
| GitHub Actions actionlint | 通过 |
| Python / Shell 语法检查 | 通过 |
| 部署脚本 `--check-config` | 通过，没有重启或覆盖服务 |

Flutter 分析器在中文目录中出现过 LSP JSON 初始化错误，因此最终分析和 Flutter 检查在 scratch 内的等价 ASCII 副本执行。验证没有部署构建产物。

## 全量测试的既有问题

首次完整 Flutter 测试为 1676 项通过、4 项失败。其中 1 项为本次配置默认值迁移后静态测试扫描位置未更新，修复后已在上述限定复验中通过。

其余与原 HEAD 相同的代码/测试问题：

- `test/screens/todo_batch_static_test.dart:122` 对 `_TodoViewMode.list` 后的换行与缩进做了精确匹配，与现有 `todo_screen.dart` 的格式不一致。此次未修改该代码或测试。
- `test/screens/almanac_screen_test.dart` 中两项日期详情测试受本机夏令时影响；单独以 `TZ=UTC` 运行该文件，8 项全部通过。此次未修改黄历实现。

上述四个待办/黄历实现与测试文件已逐字与 HEAD 比对，内容一致。本记录不宣称全量门禁全绿。

## 复现入口

```bash
python3 scripts/project_config.py validate
python3 scripts/flutter_with_config.py test test/core/client_deployment_config_test.dart
python3 scripts/flutter_with_config.py analyze
python3 scripts/flutter_with_config.py build web --release
bash scripts/deploy_backend_prod.sh --check-config
bash scripts/deploy_web_prod.sh --check-config
```

后端测试应使用临时 `DUOYI_DB_PATH`，并设置 `DUOYI_ENV_FILE=`、`APP_UPDATE_REPOSITORY=` 来隔离实例配置与网络更新源。真实私密环境文件、已有密码 salt 和数据目录需在发布时保留。
