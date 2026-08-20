#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$PROJECT_DIR/install-matrix.sh"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

curl -fsSL --retry 3 "$XRAY_INSTALL_URL" -o "$TEST_DIR/install-release.sh"
echo "$XRAY_INSTALL_SHA256  $TEST_DIR/install-release.sh" | sha256sum --check --status

curl -fsSL --retry 3 \
    "https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/download/$XRAY_GEO_RELEASE/geosite.dat" \
    -o "$TEST_DIR/geosite.dat"
curl -fsSL --retry 3 \
    "https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/download/$XRAY_GEO_RELEASE/geoip.dat" \
    -o "$TEST_DIR/geoip.dat"
echo "$XRAY_GEOSITE_SHA256  $TEST_DIR/geosite.dat" | sha256sum --check --status
echo "$XRAY_GEOIP_SHA256  $TEST_DIR/geoip.dat" | sha256sum --check --status

echo "Pinned external download checks passed"
