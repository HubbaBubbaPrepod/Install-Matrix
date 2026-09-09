#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$PROJECT_DIR/install-matrix.sh"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
MATRIX_DIR="$TEST_DIR/matrix"
CREDS_FILE="$MATRIX_DIR/credentials.txt"
COMMAND_LOG="$TEST_DIR/docker-commands.log"
ADMIN_PASSWORD_FILE="$TEST_DIR/admin-password"
mkdir -p "$MATRIX_DIR"
printf 'base credentials\n' > "$CREDS_FILE"
printf 'mas-admin-password-test\n' > "$ADMIN_PASSWORD_FILE"

NON_INTERACTIVE=true
ADMIN_USER="admin"
SERVER_NAME=example.com
MAS_DOMAIN=mas.example.com
REGISTRATION_MODE=token
PROMOTE_EXISTING=false

docker() {
    printf '%s\n' "$*" >> "$COMMAND_LOG"
    case "$*" in
        *"manage promote-admin admin"*)
            if [[ "$PROMOTE_EXISTING" == "true" ]]; then
                printf 'User promoted to admin\n' >&2
                return 0
            fi
            printf 'User not found\n' >&2
            return 1
            ;;
        *"manage register-user"*)
            printf 'User registered\n' >&2
            ;;
        *"manage issue-compatibility-token"*)
            printf 'Compatibility token issued: test-compatibility-token\n' >&2
            ;;
        *"manage issue-user-registration-token"*)
            printf 'Created user registration token: test-registration-token\n' >&2
            ;;
        *) return 0 ;;
    esac
}

ensure_mas_administrator >/dev/null

grep -Fq 'Matrix ID:            @admin:example.com' "$CREDS_FILE"
grep -Fq 'Password:             mas-admin-password-test' "$CREDS_FILE"
grep -Fq 'Compatibility token:  test-compatibility-token' "$CREDS_FILE"
grep -Fq 'Registration token:   test-registration-token' "$CREDS_FILE"
grep -Fq 'manage register-user --yes --admin --password mas-admin-password-test admin' "$COMMAND_LOG"
grep -Fq 'manage issue-compatibility-token admin --yes-i-want-to-grant-synapse-admin-privileges' "$COMMAND_LOG"
[[ "$(stat -c '%a' "$CREDS_FILE")" == "600" ]]

command_count=$(wc -l < "$COMMAND_LOG")
ensure_mas_administrator >/dev/null
[[ "$(wc -l < "$COMMAND_LOG")" -eq "$command_count" ]]
[[ "$(grep -Fc '# BEGIN MAS ADMIN' "$CREDS_FILE")" -eq 1 ]]

# The normal syn2mas path migrates the initial Synapse user. Verify that this
# path promotes the existing account, updates its password and does not try to
# register a duplicate.
PROMOTE_EXISTING=true
MATRIX_DIR="$TEST_DIR/migrated-matrix"
CREDS_FILE="$MATRIX_DIR/credentials.txt"
COMMAND_LOG="$TEST_DIR/migrated-docker-commands.log"
mkdir -p "$MATRIX_DIR"
printf 'base credentials\n' > "$CREDS_FILE"
REGISTRATION_MODE=closed

ensure_mas_administrator >/dev/null

grep -Fq 'manage promote-admin admin' "$COMMAND_LOG"
grep -Fq 'manage set-password admin mas-admin-password-test' "$COMMAND_LOG"
if grep -Fq 'manage register-user' "$COMMAND_LOG"; then
    echo "Migrated administrator was registered twice" >&2
    exit 1
fi
grep -Fq 'Compatibility token:  test-compatibility-token' "$CREDS_FILE"
if grep -Fq 'Registration token:' "$CREDS_FILE"; then
    echo "Closed registration unexpectedly produced a token" >&2
    exit 1
fi

echo "MAS administrator tests passed"
