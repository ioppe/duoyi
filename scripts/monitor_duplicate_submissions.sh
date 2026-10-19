#!/bin/bash
# 监控重复提交保护日志
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/deployment_common.sh"
require_deployment_value DUOYI_LOCAL_BASE

echo "=================================================="
echo "Duoyi 重复提交监控"
echo "=================================================="
echo ""
echo "监控时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# 检查后端日志中的重复提交相关错误
echo "📊 后端日志分析（最近 500 条）:"
backend_logs 500 | grep -ic "duplicate\|重复" | xargs -I {} echo "  重复提交相关日志: {} 条" || true

# 检查后端错误
echo ""
echo "❌ 后端错误（最近 100 条）:"
backend_logs 100 | grep -E "ERROR|Exception|Traceback" | tail -5 || true

# 检查 API 响应时间
echo ""
echo "⏱️  API 响应统计（最近 50 个请求）:"
backend_logs 200 | grep "INFO.*HTTP" | tail -50 | awk '{
    if ($0 ~ /200 OK/) ok++;
    else if ($0 ~ /4[0-9][0-9]/) client_error++;
    else if ($0 ~ /5[0-9][0-9]/) server_error++;
    total++;
}
END {
    print "  总请求: " total
    print "  200 OK: " ok " (" (total ? ok/total*100 : 0) "%)"
    print "  4xx: " client_error
    print "  5xx: " server_error
}' || true

# 检查强制更新配置
echo ""
echo "🔄 强制更新配置:"
curl -fsS "$DUOYI_LOCAL_BASE/api/config" | "$PYTHON_BIN" -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(f\"  force_update_required: {data.get('force_update_required', 'N/A')}\")
    print(f\"  current_version: {data.get('current_version', 'N/A')}\")
    print(f\"  latest_version: {data.get('latest_version', 'N/A')}\")
    print(f\"  minimum_supported_version: {data.get('minimum_supported_version', 'N/A')}\")
except Exception as e:
    print(f\"  ❌ 配置读取失败: {e}\")
"

echo ""
echo "=================================================="
echo "✅ 监控完成"
echo "=================================================="
