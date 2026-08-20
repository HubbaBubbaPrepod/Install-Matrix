#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TOOLS_DIR=$(mktemp -d)
trap 'rm -rf "$TOOLS_DIR"' EXIT

TRIVY_VERSION=0.74.0
TRIVY_CHECKSUMS_SHA256=bc701c3c3ee8b9acbea2c23257e41381e3854888f51281616a6ba5dc96963821
GITLEAKS_VERSION=8.30.1
GITLEAKS_CHECKSUMS_SHA256=061476c21adaf5441516f96f185c1a4706a83cd6329b9b38762271b3d4a52fae

curl -fsSL --retry 3 \
    "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_checksums.txt" \
    -o "$TOOLS_DIR/trivy-checksums.txt"
echo "$TRIVY_CHECKSUMS_SHA256  $TOOLS_DIR/trivy-checksums.txt" | sha256sum --check --status
curl -fsSL --retry 3 \
    "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" \
    -o "$TOOLS_DIR/trivy.tar.gz"
(cd "$TOOLS_DIR" && grep "trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" trivy-checksums.txt \
    | sed "s#trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz#trivy.tar.gz#" | sha256sum --check --status)
tar -xzf "$TOOLS_DIR/trivy.tar.gz" -C "$TOOLS_DIR" trivy
"$TOOLS_DIR/trivy" config --severity HIGH,CRITICAL --exit-code 1 "$PROJECT_DIR"
"$TOOLS_DIR/trivy" fs --scanners secret --exit-code 1 "$PROJECT_DIR"

curl -fsSL --retry 3 \
    "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_checksums.txt" \
    -o "$TOOLS_DIR/gitleaks-checksums.txt"
echo "$GITLEAKS_CHECKSUMS_SHA256  $TOOLS_DIR/gitleaks-checksums.txt" | sha256sum --check --status
curl -fsSL --retry 3 \
    "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
    -o "$TOOLS_DIR/gitleaks.tar.gz"
(cd "$TOOLS_DIR" && grep "gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" gitleaks-checksums.txt \
    | sed "s#gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz#gitleaks.tar.gz#" | sha256sum --check --status)
tar -xzf "$TOOLS_DIR/gitleaks.tar.gz" -C "$TOOLS_DIR" gitleaks
"$TOOLS_DIR/gitleaks" dir --redact --no-banner --config "$PROJECT_DIR/.gitleaks.toml" "$PROJECT_DIR"
"$TOOLS_DIR/gitleaks" git --redact --no-banner --config "$PROJECT_DIR/.gitleaks.toml" "$PROJECT_DIR"

echo "Security tool checks passed"
