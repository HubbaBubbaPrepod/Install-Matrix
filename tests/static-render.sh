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

set_mas_registration_flags
[[ "$MAS_REGISTRATION_ENABLED" == "false" && "$MAS_REGISTRATION_TOKEN_REQUIRED" == "false" ]]
REGISTRATION_MODE="token"
set_mas_registration_flags
[[ "$MAS_REGISTRATION_ENABLED" == "true" && "$MAS_REGISTRATION_TOKEN_REQUIRED" == "true" ]]
REGISTRATION_MODE="open"
set_mas_registration_flags
[[ "$MAS_REGISTRATION_ENABLED" == "true" && "$MAS_REGISTRATION_TOKEN_REQUIRED" == "false" ]]
REGISTRATION_MODE="closed"
FEDERATION_MODE="public"
MAX_UPLOAD_SIZE="2048M"
REMOTE_MEDIA_LIFETIME="14d"
PRESENCE_ENABLED="false"
RETENTION_ENABLED="true"
RETENTION_DEFAULT_MIN_LIFETIME="1d"
RETENTION_DEFAULT_MAX_LIFETIME="365d"
LOCAL_MEDIA_LIFETIME="30d"
set_image_defaults

# Render every valid optional-component combination. LiveKit and Element Admin require MAS.
for mask in $(seq 0 31); do
    has_mas=$((mask & 1)); has_livekit=$((mask & 2)); has_ketesa=$((mask & 4))
    has_element_admin=$((mask & 8)); has_ntfy=$((mask & 16))
    ((has_livekit == 0 || has_mas == 1)) || continue
    ((has_element_admin == 0 || has_mas == 1)) || continue
    bools=()
    for bit in "$has_mas" "$has_livekit" "$has_ketesa" "$has_element_admin" "$has_ntfy"; do
        [[ "$bit" == 0 ]] && bools+=(false) || bools+=(true)
    done
    generate_compose "${bools[@]}" >/dev/null
    generate_homeserver "${bools[0]}" "${bools[1]}" >/dev/null
    cp "$COMPOSE_FILE" "$TEST_DIR/render-${mask}-compose.yml"
    cp "$HOMESERVER_FILE" "$TEST_DIR/render-${mask}-homeserver.yml"
done

python3 - "$TEST_DIR" <<'PY'
import pathlib
import sys
import yaml

root = pathlib.Path(sys.argv[1])
for compose_file in root.glob("render-*-compose.yml"):
    mask = int(compose_file.name.split("-")[1])
    homeserver_file = root / compose_file.name.replace("compose", "homeserver")
    with compose_file.open(encoding="utf-8") as handle:
        compose = yaml.safe_load(handle)
    with homeserver_file.open(encoding="utf-8") as handle:
        homeserver = yaml.safe_load(handle)
    expected = {"postgres", "synapse", "coturn"}
    for bit, services in enumerate([
        {"mas-db", "mas"}, {"livekit", "lk-jwt-service"}, {"ketesa"},
        {"element-admin"}, {"ntfy"},
    ]):
        if mask & (1 << bit):
            expected |= services
    assert set(compose["services"]) == expected, compose_file
    assert homeserver["server_name"] == "example.com"
    assert homeserver["public_baseurl"] == "https://matrix.example.com/"
    assert "federation_domain_whitelist" not in homeserver
    assert homeserver["enable_registration"] is False
PY

# Registration modes remain intentionally supported.
for registration_case in closed token open; do
    REGISTRATION_MODE="$registration_case"
    generate_homeserver false false >/dev/null
    python3 - "$HOMESERVER_FILE" "$registration_case" <<'PY'
import sys
import yaml
with open(sys.argv[1], encoding="utf-8") as handle:
    config = yaml.safe_load(handle)
mode = sys.argv[2]
assert config["enable_registration"] is (mode != "closed")
assert config.get("registration_requires_token", False) is (mode == "token")
assert config.get("enable_registration_without_verification", False) is (mode == "open")
PY
done
REGISTRATION_MODE="closed"

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

# Config files are data, not shell programs.
cat > "$TEST_DIR/config.env" <<'EOF'
SERVER_NAME=config.example.com
DOMAIN=matrix.config.example.com
ADMIN_EMAIL=admin@config.example.com
REGISTRATION_MODE=token
ENABLE_MAS=true
EOF
load_config_file "$TEST_DIR/config.env"
[[ "$SERVER_NAME" == "config.example.com" ]]
[[ "$ENABLE_MAS" == "true" ]]

echo 'UNSUPPORTED_KEY=value' > "$TEST_DIR/invalid.env"
if (load_config_file "$TEST_DIR/invalid.env" >/dev/null 2>&1); then
    echo "Unknown config key was unexpectedly accepted" >&2
    exit 1
fi

echo "Static render tests passed"
