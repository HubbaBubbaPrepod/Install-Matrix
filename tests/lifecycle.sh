#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$PROJECT_DIR/install-matrix.sh"
chown() { :; }

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
MATRIX_DIR="$TEST_DIR/matrix"
ENV_FILE="$MATRIX_DIR/.env"
COMPOSE_FILE="$MATRIX_DIR/docker-compose.yml"
HOMESERVER_FILE="$MATRIX_DIR/data/synapse/homeserver.yaml"
FEDERATION_FILE="$MATRIX_DIR/federation-domains.txt"
BACKUP_ROOT="$MATRIX_DIR/data/backups"
mkdir -p "$MATRIX_DIR/data/synapse"
: > "$FEDERATION_FILE"

SERVER_NAME=example.com
DOMAIN=matrix.example.com
ADMIN_EMAIL=admin@example.com
EXTERNAL_IP=203.0.113.10
DB_PASSWORD=db-password
REG_SHARED_SECRET=registration-secret
MACAROON_SECRET=macaroon-secret
FORM_SECRET=form-secret
TURN_SECRET=turn-secret
REGISTRATION_MODE=closed
FEDERATION_MODE=restricted
MAX_UPLOAD_SIZE=2048M
REMOTE_MEDIA_LIFETIME=14d
LOCAL_MEDIA_LIFETIME=30d
PRESENCE_ENABLED=false
RETENTION_ENABLED=true
RETENTION_DEFAULT_MIN_LIFETIME=1d
RETENTION_DEFAULT_MAX_LIFETIME=365d
PROXY_ENABLED=false
CONTAINER_PROXY_URL=
IMAGE_POLICY=managed
set_image_defaults
save_env
generate_compose false false false false false >/dev/null
generate_homeserver false false >/dev/null

docker() {
    case "$*" in
        *"pg_dump"*) printf 'mock-postgres-dump\n' ;;
        *"config --images"*) printf '%s\n' "$POSTGRES_IMAGE" "$SYNAPSE_IMAGE" ;;
        *) return 0 ;;
    esac
}

run_spinner() {
    local _message="$1"
    shift
    "$@"
}

create_backup >/dev/null
[[ -f "$LAST_BACKUP_DIR/synapse.dump" ]]
[[ -f "$LAST_BACKUP_DIR/configuration.tar.gz" ]]
[[ -f "$LAST_BACKUP_DIR/MANIFEST.txt" ]]
[[ -f "$LAST_BACKUP_DIR/SHA256SUMS" ]]
verify_backup "$LAST_BACKUP_DIR" >/dev/null
[[ "$(resolve_backup_dir latest)" == "$LAST_BACKUP_DIR" ]]
RESTORE_SOURCE="$LAST_BACKUP_DIR"
verify_backup_command >/dev/null

cp -a "$LAST_BACKUP_DIR" "$TEST_DIR/corrupt"
printf 'corruption' >> "$TEST_DIR/corrupt/synapse.dump"
if (verify_backup "$TEST_DIR/corrupt" >/dev/null 2>&1); then
    echo "Corrupt backup unexpectedly passed verification" >&2
    exit 1
fi

cp -a "$LAST_BACKUP_DIR" "$TEST_DIR/unsafe"
python3 - "$TEST_DIR/unsafe/configuration.tar.gz" <<'PY'
import io
import sys
import tarfile

with tarfile.open(sys.argv[1], "w:gz") as archive:
    payload = b"must not escape\n"
    entry = tarfile.TarInfo("../../escape")
    entry.size = len(payload)
    archive.addfile(entry, io.BytesIO(payload))
PY
(
    cd "$TEST_DIR/unsafe"
    sha256sum synapse.dump configuration.tar.gz MANIFEST.txt > SHA256SUMS
)
if (verify_backup "$TEST_DIR/unsafe" >/dev/null 2>&1); then
    echo "Unsafe backup archive unexpectedly passed verification" >&2
    exit 1
fi

echo "Lifecycle tests passed"
