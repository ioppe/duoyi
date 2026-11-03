#!/bin/bash
set -euo pipefail

# Duoyi Web Production Deployment Script
#
# 公开部署参数来自 config/deployment.json 或 DUOYI_CONFIG_FILE。
# 显式环境变量优先；工具路径使用 FLUTTER_BIN/PYTHON_BIN 或 PATH。
# 仅检查参数：./scripts/deploy_web_prod.sh --check-config
#
# 功能：
#   1. 检查版本号一致性
#   2. 构建 Web 发布版本
#   3. 验证构建产物 (版本号、base href、无陈旧版本字符串)
#   4. 备份旧版本
#   5. 部署新版本
#   6. 验证部署

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_WEB_DIR="$PROJECT_ROOT/build/web"
source "$SCRIPT_DIR/deployment_common.sh"
require_deployment_value WEB_ROOT
require_deployment_value BACKUP_ROOT
if [ "${1:-}" = '--check-config' ]; then
    printf 'Web root: %s\nBackup root: %s\nBase href: %s\n' "$WEB_ROOT" "$BACKUP_ROOT" "$BASE_HREF"
    exit 0
fi

verify_web_build() {
    local dir="$1"
    local label="$2"

    echo "✅ Verifying $label..."

    if [ ! -d "$dir" ]; then
        echo "   ❌ Web build directory missing: $dir"
        exit 1
    fi

    local version_file="$dir/version.json"
    if [ ! -f "$version_file" ]; then
        echo "   ❌ version.json missing"
        exit 1
    fi

    local artifact_version
    local artifact_build
    artifact_version=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$version_file" | sed -E 's/.*"([^"]+)".*/\1/')
    artifact_build=$(grep -o '"build_number"[[:space:]]*:[[:space:]]*"[^"]*"' "$version_file" | sed -E 's/.*"([^"]+)".*/\1/')

    if [ "$artifact_version" != "$VERSION_NAME" ]; then
        echo "   ❌ version.json stale: expected $VERSION_NAME, got $artifact_version"
        exit 1
    fi
    if [ "$artifact_build" != "$VERSION_CODE" ]; then
        echo "   ❌ version.json build stale: expected $VERSION_CODE, got $artifact_build"
        exit 1
    fi
    echo "   ✓ version.json matches v$artifact_version (build $artifact_build)"

    if [ -f "$dir/index.html" ]; then
        echo "   ✓ index.html exists"
        if grep -q "<base href=\"$BASE_HREF\">" "$dir/index.html"; then
            echo "   ✓ base href is $BASE_HREF"
        else
            echo "   ❌ base href is not $BASE_HREF"
            exit 1
        fi
    else
        echo "   ❌ index.html missing"
        exit 1
    fi

    if [ -f "$dir/main.dart.js" ]; then
        local size
        size=$(du -h "$dir/main.dart.js" | cut -f1)
        echo "   ✓ main.dart.js exists ($size)"
        if grep -Fq "$VERSION_NAME" "$dir/main.dart.js"; then
            echo "   ✓ main.dart.js contains v$VERSION_NAME"
        else
            echo "   ❌ main.dart.js does not contain v$VERSION_NAME"
            exit 1
        fi
    else
        echo "   ❌ main.dart.js missing"
        exit 1
    fi

    local stale_versions
    local version_family
    version_family="${VERSION_NAME%.*}"
    stale_versions=$(
        grep -HnIroE "${version_family//./\\.}\\.[0-9]+" \
            "$version_file" "$dir/index.html" "$dir/main.dart.js" 2>/dev/null \
            | awk -F: -v current="$VERSION_NAME" '$3 != current { print }' \
            | sort -u \
            || true
    )
    if [ -n "$stale_versions" ]; then
        echo "   ❌ Stale version string(s) found in $label:"
        echo "$stale_versions" | head -20
        exit 1
    fi
    echo "   ✓ no stale version strings found in critical web artifacts"

    "$PYTHON_BIN" - "$dir" <<'PY'
import hashlib
import json
from pathlib import Path
import sys
root = Path(sys.argv[1])
policy = json.loads((root / 'assets/web-font-policy.json').read_text())
manifest = json.loads((root / 'assets/FontManifest.json').read_text())
families = [item for item in manifest if item.get('family') == 'NotoSansSC']
expected = 'assets/fonts/NotoSansSC-Startup.ttf'
if len(families) != 1 or families[0].get('fonts') != [{'asset': expected}]:
    raise SystemExit('Web startup font manifest is missing or still blocks on the full font')
startup = root / 'assets' / expected
if hashlib.sha256(startup.read_bytes()).hexdigest() != policy['startup_sha256']:
    raise SystemExit('Web startup font hash mismatch')
if not (root / 'assets' / policy['complete_asset']).is_file():
    raise SystemExit('Deferred complete font is missing')
if not (root / 'assets/assets/fonts/NotoSansSC-OFL.txt').is_file():
    raise SystemExit('Bundled font license is missing')
print('   ✓ startup font subset and deferred complete font verified')
PY
}

echo "=================================================="
echo "Duoyi Web Production Deployment"
echo "=================================================="
echo ""
echo "Project root: $PROJECT_ROOT"
echo "Web root: $WEB_ROOT"
echo "Backup root: $BACKUP_ROOT"
echo "Flutter: $FLUTTER_BIN"
echo ""

cd "$PROJECT_ROOT"

# 1. 检查版本号
echo "📋 Checking version..."
VERSION_NAME=$(grep "static const name = " lib/core/app_version.dart | sed -E "s/.*'([^']+)'.*/\1/")
VERSION_CODE=$(grep "static const build = " lib/core/app_version.dart | sed -E "s/.*= ([0-9]+);/\1/")
PUBSPEC_VERSION=$(grep "^version: " pubspec.yaml | sed -E "s/version: ([0-9.]+)\+.*/\1/")
PUBSPEC_BUILD=$(grep "^version: " pubspec.yaml | sed -E "s/version: [0-9.]+\+([0-9]+).*/\1/")

if [ "$VERSION_NAME" != "$PUBSPEC_VERSION" ]; then
    echo "❌ Version mismatch:"
    echo "   app_version.dart: $VERSION_NAME"
    echo "   pubspec.yaml: $PUBSPEC_VERSION"
    exit 1
fi
if [ "$VERSION_CODE" != "$PUBSPEC_BUILD" ]; then
    echo "❌ Build number mismatch:"
    echo "   app_version.dart: $VERSION_CODE"
    echo "   pubspec.yaml: $PUBSPEC_BUILD"
    exit 1
fi

echo "   Version: $VERSION_NAME (build $VERSION_CODE)"
echo ""

# 2. 构建 Web
echo "🔨 Building web (release)..."
rm -rf "$BUILD_WEB_DIR"
FLUTTER_BIN="$FLUTTER_BIN" "$PYTHON_BIN" "$PROJECT_ROOT/scripts/flutter_with_config.py" build web --release --base-href="$BASE_HREF"
verify_web_build "$BUILD_WEB_DIR" "fresh build output"
echo ""

# 3. 备份旧版本
if [ -d "$WEB_ROOT" ] && [ "$(ls -A "$WEB_ROOT" 2>/dev/null)" ]; then
    BACKUP_DIR="$BACKUP_ROOT/duoyi.backup.$(date +%Y%m%d_%H%M%S)"
    echo "💾 Backing up old version to $BACKUP_DIR..."
    mkdir -p "$BACKUP_ROOT"
    sudo cp -r "$WEB_ROOT" "$BACKUP_DIR"
    echo "   Old version backed up"
    echo ""
fi

# 4. 部署新版本
echo "🚀 Deploying to $WEB_ROOT..."
sudo mkdir -p "$WEB_ROOT"
sudo find "$WEB_ROOT" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
sudo cp -r "$BUILD_WEB_DIR"/. "$WEB_ROOT/"
echo "   Files copied"
echo ""

# 5. 验证部署
verify_web_build "$WEB_ROOT" "deployed web root"

echo ""
echo "=================================================="
echo "✅ Web deployment completed successfully!"
echo "=================================================="
echo ""
echo "Deployed: v$VERSION_NAME (build $VERSION_CODE)"
echo "Location: $WEB_ROOT"
echo "Access: ${DUOYI_PUBLIC_BASE%/}${BASE_HREF}"
echo ""
echo "Note: Users may need to hard refresh (Ctrl+Shift+R) to see the new version."
echo ""
