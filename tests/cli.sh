#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$PROJECT_DIR/install-matrix.sh"

[[ "$(bash "$INSTALLER" --version)" == "Install-Matrix v4.1.0" ]]
bash "$INSTALLER" --help | grep -Fq -- "--non-interactive"
bash "$INSTALLER" --help | grep -Fq -- "restore [DIR|latest]"
bash "$INSTALLER" --help | grep -Fq -- "verify-backup [DIR|latest]"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
cat > "$TEST_DIR/config.env" <<'EOF'
SERVER_NAME=example.com
DOMAIN=matrix.example.com
ADMIN_EMAIL=admin@example.com
EXTERNAL_IP=203.0.113.10
REGISTRATION_MODE=closed
FEDERATION_MODE=restricted
ENABLE_MAS=true
ENABLE_LIVEKIT=true
ENABLE_KETESA=true
ENABLE_ELEMENT_ADMIN=true
ENABLE_NTFY=true
MAS_DOMAIN=mas.example.com
LIVEKIT_DOMAIN=livekit.example.com
KETESA_DOMAIN=admin.example.com
ELEMENT_ADMIN_DOMAIN=element-admin.example.com
NTFY_DOMAIN=ntfy.example.com
EOF

bash "$INSTALLER" install --dry-run --config "$TEST_DIR/config.env" --yes >/dev/null

echo "CLI tests passed"
