#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$PROJECT_DIR"

if grep -RInE --exclude-dir=.git --exclude-dir=.supply-check --exclude='supply-chain.sh' \
    '(releases/latest/download|raw/(refs/heads/)?main|curl[^#|]*\|[[:space:]]*(sudo[[:space:]]+)?bash)' .; then
    echo "Mutable or pipe-to-shell download found" >&2
    exit 1
fi

if grep -nE 'IMAGE_DEFAULT="[^\"]*:latest"' install-matrix.sh; then
    echo "A default container image uses latest" >&2
    exit 1
fi

while IFS= read -r image_default; do
    [[ "$image_default" =~ @sha256:[0-9a-f]{64}$ ]] || {
        echo "Default image is not pinned by OCI digest: $image_default" >&2
        exit 1
    }
done < <(sed -n 's/^[A-Z_]*IMAGE_DEFAULT="\([^"]*\)"$/\1/p' install-matrix.sh)

mapfile -t default_images < <(
    sed -n 's/^[A-Z_]*IMAGE_DEFAULT="\([^"]*\)"$/\1/p' install-matrix.sh | sort
)
mapfile -t scanned_images < <(
    sed -n 's/^[[:space:]]*-[[:space:]]*\([^[:space:]]*@sha256:[0-9a-f]\{64\}\)$/\1/p' \
        .github/workflows/security.yml | sort
)
if ! diff -u \
    <(printf '%s\n' "${default_images[@]}") \
    <(printf '%s\n' "${scanned_images[@]}"); then
    echo "Default images and the security scan matrix are out of sync" >&2
    exit 1
fi

while IFS= read -r action; do
    ref=${action##*@}
    [[ "$ref" =~ ^[0-9a-f]{40}$ ]] || {
        echo "GitHub Action is not pinned by full commit SHA: $action" >&2
        exit 1
    }
done < <(grep -RhoE 'uses:[[:space:]]*[^[:space:]#]+' .github/workflows | sed 's/^uses:[[:space:]]*//')

echo "Supply-chain policy checks passed"
