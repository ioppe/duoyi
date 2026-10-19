#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/deployment_common.sh"
require_deployment_value DUOYI_BACKEND_SERVICE
require_deployment_value DUOYI_PUBLIC_BASE
require_deployment_value DUOYI_LOCAL_BASE

if [ "${1:-}" = '--check-config' ]; then
  printf 'Backend: %s (%s)\nLocal: %s\nPublic: %s\n' "$DUOYI_BACKEND_SERVICE" "$DUOYI_BACKEND_RUNNER" "$DUOYI_LOCAL_BASE" "$DUOYI_PUBLIC_BASE"
  exit 0
fi

CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/duoyi-deploy.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT

echo "Restarting $DUOYI_BACKEND_SERVICE ($DUOYI_BACKEND_RUNNER)..."
backend_restart
for _ in $(seq 1 30); do
  if curl -fsS "$DUOYI_LOCAL_BASE/api/config" >"$CHECK_DIR/local.json"; then break; fi
  sleep 1
done
if ! curl -fsS "$DUOYI_LOCAL_BASE/api/config" >"$CHECK_DIR/local.json"; then
  backend_status >&2 || true
  exit 1
fi

curl -fsS "$DUOYI_PUBLIC_BASE/api/config" >"$CHECK_DIR/public.json"
theme_status="$(curl -sS -o "$CHECK_DIR/theme.json" -w '%{http_code}' \
  -X POST "$DUOYI_PUBLIC_BASE/api/theme-shop/apply" \
  -H 'Content-Type: application/json' -d '{"theme_id":"defaultBrand"}')"
if [ "$theme_status" != 401 ]; then
  echo "Expected theme route to return 401 without authentication, got $theme_status" >&2
  exit 1
fi
focus_status="$(curl -sS -o "$CHECK_DIR/focus.json" -w '%{http_code}' \
  "$DUOYI_PUBLIC_BASE/api/focus-rooms/deep_work_room/ranking")"
if [ "$focus_status" != 401 ]; then
  echo "Expected focus ranking to return 401 without authentication, got $focus_status" >&2
  exit 1
fi
"$PYTHON_BIN" - "$CHECK_DIR/public.json" <<'PY'
import json
from pathlib import Path
import sys
payload = json.loads(Path(sys.argv[1]).read_text())
print('Backend verified: current_version={version}, routes_hash={routes}'.format(
    version=payload.get('current_version'), routes=payload.get('required_routes_hash')))
PY
