#!/usr/bin/env bash
# Source this module to load validated public deployment values only.
DUOYI_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
DUOYI_PUBLIC_EXPORTS="$("$PYTHON_BIN" "$DUOYI_PROJECT_ROOT/scripts/project_config.py" shell)" || return $?
eval "$DUOYI_PUBLIC_EXPORTS"
unset DUOYI_PUBLIC_EXPORTS
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"

require_deployment_value() {
  if [ -z "${!1}" ]; then
    echo "Missing deployment value: $1 (configure DUOYI_CONFIG_FILE or the environment)" >&2
    return 2
  fi
}

backend_restart() {
  require_deployment_value DUOYI_BACKEND_SERVICE || return $?
  case "$DUOYI_BACKEND_RUNNER" in
    docker) sudo docker restart "$DUOYI_BACKEND_SERVICE" ;;
    systemd) sudo systemctl restart "$DUOYI_BACKEND_SERVICE" ;;
  esac
}

backend_status() {
  case "$DUOYI_BACKEND_RUNNER" in
    docker) sudo docker inspect --format '{{.State.Status}}' "$DUOYI_BACKEND_SERVICE" ;;
    systemd) sudo systemctl status "$DUOYI_BACKEND_SERVICE" --no-pager ;;
  esac
}

backend_logs() {
  require_deployment_value DUOYI_BACKEND_SERVICE || return $?
  case "$DUOYI_BACKEND_RUNNER" in
    docker) sudo docker logs --tail "${1:-100}" "$DUOYI_BACKEND_SERVICE" 2>&1 ;;
    systemd) sudo journalctl -u "$DUOYI_BACKEND_SERVICE" -n "${1:-100}" --no-pager ;;
  esac
}
