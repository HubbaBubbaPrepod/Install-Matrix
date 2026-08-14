#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
bash -n "$PROJECT_DIR/install-matrix.sh"

# The installer writes production files as root. This render test uses an isolated tree.
source "$PROJECT_DIR/install-matrix.sh"
chown() { :; }

[[ "$(normalize_domain '@alice:Matrix.ORG')" == "matrix.org" ]]
[[ "$(normalize_domain 'https://matrix.example.com/path')" == "matrix.example.com" ]]
[[ "$(normalize_domain 'matrix.example.com:8448')" == "matrix.example.com" ]]
is_valid_domain "matrix.example.com"
! is_valid_domain "bad_domain"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
MATRIX_DIR="$TEST_DIR"
ENV_FILE="$MATRIX_DIR/.env"
COMPOSE_FILE="$MATRIX_DIR/docker-compose.yml"
HOMESERVER_FILE="$MATRIX_DIR/data/synapse/homeserver.yaml"
FEDERATION_FILE="$MATRIX_DIR/federation-domains.txt"
BACKUP_ROOT="$MATRIX_DIR/data/backups"
mkdir -p "$MATRIX_DIR/data/synapse"

SERVER_NAME="example.com"
DOMAIN="matrix.example.com"
ADMIN_EMAIL="admin@example.com"
EXTERNAL_IP="203.0.113.10"
DB_PASSWORD="dbpass"
MAS_DB_PASSWORD="masdbpass"
REG_SHARED_SECRET="regsecret"
MACAROON_SECRET="macsecret"
FORM_SECRET="formsecret"
TURN_SECRET="turnsecret"
MAS_DOMAIN="mas.example.com"
MAS_SECRET="massecret"
LIVEKIT_DOMAIN="livekit.example.com"
LIVEKIT_KEY="livekitkey"
LIVEKIT_SECRET="livekitsecret"
KETESA_DOMAIN="admin.example.com"
ELEMENT_ADMIN_DOMAIN="element-admin.example.com"
NTFY_DOMAIN="ntfy.example.com"
NTFY_ADMIN_USER="admin"
CONTAINER_PROXY_URL="http://host.docker.internal:10809"
REGISTRATION_MODE="closed"
FEDERATION_MODE="public"
MAX_UPLOAD_SIZE="2048M"
REMOTE_MEDIA_LIFETIME="14d"
PRESENCE_ENABLED="false"
RETENTION_ENABLED="true"
RETENTION_DEFAULT_MIN_LIFETIME="1d"
RETENTION_DEFAULT_MAX_LIFETIME="365d"
RETENTION_ALLOW_ADMIN_OVERRIDE="true"
LOCAL_MEDIA_LIFETIME="30d"
set_image_defaults

generate_compose true true true true true >/dev/null
generate_homeserver true true >/dev/null

python3 - "$COMPOSE_FILE" "$HOMESERVER_FILE" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as handle:
    compose = yaml.safe_load(handle)
with open(sys.argv[2], encoding="utf-8") as handle:
    homeserver = yaml.safe_load(handle)

expected = {
    "postgres", "synapse", "coturn", "mas-db", "mas", "livekit",
    "lk-jwt-service", "ketesa", "element-admin", "ntfy",
}
assert expected <= set(compose["services"])
assert homeserver["server_name"] == "example.com"
assert homeserver["public_baseurl"] == "https://matrix.example.com/"
assert "federation_domain_whitelist" not in homeserver
assert homeserver["enable_registration"] is False
PY

printf '%s\n' matrix.org example.net > "$FEDERATION_FILE"
FEDERATION_MODE="restricted"
generate_homeserver true true >/dev/null
python3 - "$HOMESERVER_FILE" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as handle:
    homeserver = yaml.safe_load(handle)
assert homeserver["federation_domain_whitelist"] == ["matrix.org", "example.net"]
PY

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    docker compose -f "$COMPOSE_FILE" config --quiet
fi

echo "Static render tests passed"
