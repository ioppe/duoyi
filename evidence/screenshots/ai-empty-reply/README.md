# 推理模型的“空回复”修复

## 复现（修复前，真实配置）

实例：本机 18655，`ai_base_url=https://skydrow.site`，`ai_model=deepseek-v4.1-flash`，真实密钥（未写入任何文件或日志）。

| 请求 | max_tokens | finish_reason | content | reasoning_tokens |
|---|---|---|---|---|
| 管理端探针“回复一个 ok” | 8 | `length` | **空** | 8 |
| AI 解读（真实周报格式） | 900 | `length` | **空** | 900 |
| 同一解读请求 | 1800 | `stop` | 1106 字符 | 738 |

结论：该模型先写 `reasoning_content`，思考与正文共享 `max_tokens`；预算被思考吃光时上游仍返回 HTTP 200，但 `content` 为空。后端只读 `message.content` 且不检查 `finish_reason`，于是管理页显示绿色“可达…空回复”，客户端把空串当成功，统计页渲染出只有“云端个性化解读”标题的空白卡片。

附带发现：默认 `Python-urllib/3.13` User-Agent 会被网关的 Cloudflare 规则以 `error code: 1010` 拦截（403）；换普通 UA 即可通过。

## 修复

- 后端只认正文（`message.content` 字符串/分片、旧式 `choices[0].text`、`output_text`），`reasoning_content` 永不回显；正文为空返回 502，并给出 `finish_reason` 与思考 token 数。
- 上游请求显式发送 `User-Agent: duoyi-backend/1.1` 与 `Accept: application/json`。
- 管理端测试预算 8 → 256，返回 `ok`、`finish_reason`、`reasoning_tokens`，失败时给出可读原因；表单任一字段变化即清除上次结论。
- 客户端 `_chat` 对空正文抛 `AiException`，统计页空正文转为错误提示。
- 预算按“思考+正文”留量：解读 2200、拆解 2000、日记 1600、日程 1200、周回顾 1200、周期报告 1000。

## 修复后验证（同一真实网关）

- 管理端测试：`http=200 ok=True sample='ok' finish='stop'`。
- 真实解读：`http=200`，正文 716 字符，`content` 以 `## 多仪 · 本周效率报告解读` 开头。
- 故意 `max_tokens=8`：`http=502`，`detail=模型把输出预算全部用于思考，正文为空（finish_reason=length，思考 8 tokens）。请调大 max_tokens 或改用非推理模型。`

## 自动化回归

- 后端 164 项通过，其中新增：内容分片/旧式 `text` 解析、`reasoning_content` 不外泄、`/api/ai/chat` 空正文 502 说明、管理端测试预算与诊断字段、非默认 `User-Agent`。
- Flutter：`flutter analyze` 无问题；`ai_reply_guard_test`、`admin_ai_settings_test`、`ai_todo_breakdown_test`、统计/日记静态回归共 44 项通过。
- Web release 构建通过，18655 预览已切换到该构建。

未部署生产环境；本记录不含密钥、账号口令或用户数据。
