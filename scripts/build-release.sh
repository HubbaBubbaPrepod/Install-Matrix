#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DESTINATION=${1:-dist}
if [[ "$DESTINATION" != /* ]]; then
    DESTINATION="$PROJECT_DIR/$DESTINATION"
fi

mkdir -p "$DESTINATION"
install -m 0755 "$PROJECT_DIR/install-matrix.sh" "$DESTINATION/install-matrix.sh"
install -m 0644 "$PROJECT_DIR/LICENSE" "$DESTINATION/LICENSE"
install -m 0644 "$PROJECT_DIR/README.MD" "$DESTINATION/README.MD"
install -m 0644 "$PROJECT_DIR/README.en.md" "$DESTINATION/README.en.md"
install -m 0644 "$PROJECT_DIR/CHANGELOG.md" "$DESTINATION/CHANGELOG.md"
install -m 0644 "$PROJECT_DIR/CHANGELOG.ru.md" "$DESTINATION/CHANGELOG.ru.md"
(
    cd "$DESTINATION"
    sha256sum install-matrix.sh LICENSE README.MD README.en.md \
        CHANGELOG.md CHANGELOG.ru.md > SHA256SUMS
)
printf 'Release assets created in %s\n' "$DESTINATION"
