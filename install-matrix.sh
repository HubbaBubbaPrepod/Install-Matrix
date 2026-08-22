#!/bin/bash

# ============================================================
#  MATRIX SERVER INSTALLER v4.1.0
#  by zxchubbabubba
#  Поддерживает: Ubuntu 20.04/22.04/24.04/26.04, Debian 11/12/13 (amd64)
#  Меню: Matrix, MAS, LiveKit, federation, admin UIs, ntfy, Xray, backup
# ============================================================

set -Ee -o pipefail
umask 077

INSTALLER_VERSION="4.1.0"
INSTALLER_REPOSITORY="https://github.com/HubbaBubbaPrepod/Install-Matrix"
NON_INTERACTIVE=false
ASSUME_YES=false
DRY_RUN=false
ALLOW_OPEN_REGISTRATION=false
CLI_COMMAND="menu"
RESTORE_SOURCE=""
UNINSTALL_MODE=""
IMAGE_POLICY="managed"
RUNTIME_DIR=""
declare -A USER_OVERRIDES=()

# ════════════════════════════════════════
#  ЦВЕТА
# ════════════════════════════════════════
RED='\033[0;31m'
BRED='\033[1;31m'
GREEN='\033[0;32m'
BGREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BCYAN='\033[1;36m'
PURPLE='\033[0;35m'
BPURPLE='\033[1;35m'
WHITE='\033[1;37m'
DIM='\033[2m'
NC='\033[0m'
BOLD='\033[1m'

# ════════════════════════════════════════
#  ОБЩИЕ ПЕРЕМЕННЫЕ
# ════════════════════════════════════════
MATRIX_DIR="/root/matrix-server"
ENV_FILE="$MATRIX_DIR/.env"
COMPOSE_FILE="$MATRIX_DIR/docker-compose.yml"
HOMESERVER_FILE="$MATRIX_DIR/data/synapse/homeserver.yaml"
FEDERATION_FILE="$MATRIX_DIR/federation-domains.txt"
BACKUP_ROOT="$MATRIX_DIR/data/backups"

# Проверенные стабильные версии на 2026-08-14. Их можно переопределить в .env.
POSTGRES_IMAGE_DEFAULT="postgres:16.15-alpine@sha256:cf78e76683b9ca8c5733cbbdce6c9262b45b6767934dd0a95e671f9a0fc20685"
SYNAPSE_IMAGE_DEFAULT="ghcr.io/element-hq/synapse:v1.158.0@sha256:5f868df1f5772907c6dbe973a9b69ab530a5d6bb317c011a3788f7ad78eb1292"
COTURN_IMAGE_DEFAULT="coturn/coturn:4.17.2-r0@sha256:aa68aab64a3b929d57fc2924c98ea447bf996cf8dade2508e7b71eaf23f1f14e"
MAS_IMAGE_DEFAULT="ghcr.io/element-hq/matrix-authentication-service:1.22.0@sha256:8cb319ec41706adc1ed8b5b63e1de2f067073cc33a304686226f658f5e83c8b3"
LIVEKIT_IMAGE_DEFAULT="livekit/livekit-server:v1.13.5@sha256:3497163e15c48fef6e7830c78716f9e9d5edc28abf7aa90b61c86e93bbc306b1"
LK_JWT_IMAGE_DEFAULT="ghcr.io/element-hq/lk-jwt-service:0.5.0@sha256:29918567e6b7cd920e2853b4cd6848ce01b79947c3d19a9f1ed5b74f0a2a88bf"
KETESA_IMAGE_DEFAULT="ghcr.io/etkecc/ketesa:v1.4.0@sha256:ec8216e940f9b1490539bff8dde303846a4809b17f6c5ad31603701a3f575c3e"
ELEMENT_ADMIN_IMAGE_DEFAULT="oci.element.io/element-admin:0.1.12@sha256:01ecadf363e5729dcd6e3606389cfbd08a3171cf8bf5efc68e54290112048f7d"
NTFY_IMAGE_DEFAULT="binwiederhier/ntfy:v2.27.0@sha256:f2419f405127afa868f10985c1a41449e673477cee1eb19994339a5ae8b592e7"
XRAY_VERSION_DEFAULT="v26.3.27"
# Immutable upstream revision. Update it deliberately and record the change in CHANGELOG.md.
XRAY_INSTALL_COMMIT="e741a4f56d368afbb9e5be3361b40c4552d3710d"
XRAY_INSTALL_URL="https://raw.githubusercontent.com/XTLS/Xray-install/${XRAY_INSTALL_COMMIT}/install-release.sh"
XRAY_INSTALL_SHA256="7f70c95f6b418da8b4f4883343d602964915e28748993870fd554383afdbe555"
XRAY_GEO_RELEASE="202608171005"
XRAY_GEOIP_SHA256="22c21a664cecd0702b61dba17a903b44fabad7b4458900fa19625b297cf62541"
XRAY_GEOSITE_SHA256="76fdbe01687a6cc7683b50c38ceea84941458e8371d215918daf555665a537cd"

# ════════════════════════════════════════
#  HELPERS
# ════════════════════════════════════════
log_ok() {
    echo -e "  ${BGREEN}✓${NC}  ${WHITE}$1${NC}"
}

log_warn() {
    echo -e "  ${YELLOW}⚠${NC}  ${YELLOW}$1${NC}"
}

log_error() {
    echo -e "\n  ${BRED}✗  $1${NC}\n"
    exit 1
}

log_step() {
    echo ""
    echo -e "${BCYAN}  ┌─────────────────────────────────────────────${NC}"
    echo -e "${BCYAN}  │  ${BOLD}${WHITE}$1${NC}"
    echo -e "${BCYAN}  └─────────────────────────────────────────────${NC}"
}

run_spinner() {
    local msg="$1"; shift
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    local log_file
    log_file=$(mktemp "${RUNTIME_DIR:-/tmp}/command.XXXXXX")

    "$@" >"$log_file" 2>&1 &
    local pid=$!

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}${frames[$i]}${NC}  ${DIM}%s...${NC}          " "$msg"
        i=$(( (i+1) % ${#frames[@]} ))
        sleep 0.08
    done

    if ! wait "$pid"; then
        printf "\r  ${BRED}✗${NC}  ${RED}%s — ошибка!${NC}\n\n" "$msg"
        echo -e "${DIM}"
        tail -25 "$log_file"
        echo -e "${NC}"
        rm -f -- "$log_file"
        return 1
    fi

    rm -f -- "$log_file"
    printf "\r  ${BGREEN}✓${NC}  ${WHITE}%s${NC}                    \n" "$msg"
}

initialize_runtime_dir() {
    RUNTIME_DIR=$(mktemp -d /tmp/install-matrix.XXXXXX)
    chmod 700 "$RUNTIME_DIR"
    trap '[[ -n "${RUNTIME_DIR:-}" && "$RUNTIME_DIR" == /tmp/install-matrix.* ]] && rm -rf -- "$RUNTIME_DIR"' EXIT
}

wait_for_url() {
    local url="$1"
    local name="$2"
    local timeout="${3:-120}"
    local elapsed=0

    while ! curl --fail --silent --show-error --max-time 10 "$url" >/dev/null 2>&1; do
        sleep 2
        elapsed=$((elapsed + 2))
        if [[ $elapsed -ge $timeout ]]; then
            log_error "$name не ответил за ${timeout}с: $url"
        fi
    done
    log_ok "$name отвечает"
}

wait_for_http_status() {
    local url="$1"
    local expected="$2"
    local name="$3"
    local timeout="${4:-120}"
    local elapsed=0
    local status

    while true; do
        status=$(curl --silent --output /dev/null --max-time 10 \
            --write-out '%{http_code}' "$url" || true)
        if [[ "$status" == "$expected" ]]; then
            log_ok "$name отвечает с ожидаемым HTTP $expected"
            return
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        if [[ $elapsed -ge $timeout ]]; then
            log_error "$name вернул HTTP $status вместо $expected: $url"
        fi
    done
}

generate_secret() {
    local length="${1:-32}"
    openssl rand -hex "$(( (length + 1) / 2 ))" | cut -c1-"$length"
}

confirm_action() {
    local prompt="$1"
    if [[ "$ASSUME_YES" == "true" ]]; then
        return 0
    fi
    [[ "$NON_INTERACTIVE" == "false" ]] \
        || log_error "$prompt: требуется --yes"
    local answer
    echo -ne "  ${YELLOW}$prompt [y/N]: ${NC}"
    read -r answer
    [[ "$answer" =~ ^[YyДд]$ ]]
}

validate_registration_mode() {
    case "${REGISTRATION_MODE:-closed}" in
        closed|token) return 0 ;;
        open)
            [[ "$ALLOW_OPEN_REGISTRATION" == "true" ]] \
                || log_error "Открытая регистрация требует --allow-open-registration или интерактивного подтверждения"
            ;;
        *) log_error "REGISTRATION_MODE должен быть closed, token или open" ;;
    esac
}

set_mas_registration_flags() {
    MAS_REGISTRATION_ENABLED=false
    MAS_REGISTRATION_TOKEN_REQUIRED=false
    case "${REGISTRATION_MODE:-closed}" in
        closed) ;;
        token)
            MAS_REGISTRATION_ENABLED=true
            MAS_REGISTRATION_TOKEN_REQUIRED=true
            ;;
        open)
            MAS_REGISTRATION_ENABLED=true
            ;;
        *) log_error "REGISTRATION_MODE должен быть closed, token или open" ;;
    esac
}

run_with_retry() {
    local description="$1"; shift
    local attempts="${RETRY_ATTEMPTS:-5}"
    local delay="${RETRY_DELAY_SECONDS:-5}"
    local attempt

    for ((attempt=1; attempt<=attempts; attempt++)); do
        if "$@"; then
            return 0
        fi
        if [[ $attempt -lt $attempts ]]; then
            log_warn "$description: попытка $attempt/$attempts не удалась, повтор через ${delay}с"
            sleep "$delay"
        fi
    done
    log_error "$description не выполнено после $attempts попыток"
}

is_valid_domain() {
    local domain="${1,,}"
    [[ ${#domain} -le 253 ]] || return 1
    [[ "$domain" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]
}

normalize_domain() {
    local value="$1"
    value="${value//[[:space:]]/}"
    if [[ "$value" =~ ^@[^:]+:(.+)$ ]]; then
        value="${BASH_REMATCH[1]}"
    fi
    value="${value#http://}"
    value="${value#https://}"
    value="${value#matrix://}"
    value="${value%%/*}"
    value="${value%%:*}"
    value="${value%.}"
    printf '%s' "${value,,}"
}

read_domain() {
    local prompt="$1"
    local default_value="${2:-}"
    local value
    while true; do
        echo -ne "  ${CYAN}▶${NC}  $prompt" >&2
        [[ -n "$default_value" ]] && echo -ne " [${default_value}]" >&2
        echo -ne ": " >&2
        read -r value
        value="${value:-$default_value}"
        value="$(normalize_domain "$value")"
        if is_valid_domain "$value"; then
            printf '%s' "$value"
            return
        fi
        log_warn "Некорректное доменное имя: $value" >&2
    done
}

set_image_defaults() {
    POSTGRES_IMAGE="${POSTGRES_IMAGE:-$POSTGRES_IMAGE_DEFAULT}"
    SYNAPSE_IMAGE="${SYNAPSE_IMAGE:-$SYNAPSE_IMAGE_DEFAULT}"
    COTURN_IMAGE="${COTURN_IMAGE:-$COTURN_IMAGE_DEFAULT}"
    MAS_IMAGE="${MAS_IMAGE:-$MAS_IMAGE_DEFAULT}"
    LIVEKIT_IMAGE="${LIVEKIT_IMAGE:-$LIVEKIT_IMAGE_DEFAULT}"
    LK_JWT_IMAGE="${LK_JWT_IMAGE:-$LK_JWT_IMAGE_DEFAULT}"
    KETESA_IMAGE="${KETESA_IMAGE:-$KETESA_IMAGE_DEFAULT}"
    ELEMENT_ADMIN_IMAGE="${ELEMENT_ADMIN_IMAGE:-$ELEMENT_ADMIN_IMAGE_DEFAULT}"
    NTFY_IMAGE="${NTFY_IMAGE:-$NTFY_IMAGE_DEFAULT}"
    XRAY_VERSION="${XRAY_VERSION:-$XRAY_VERSION_DEFAULT}"
}

load_config_file() {
    local file="$1" line key value
    [[ -f "$file" ]] || log_error "Файл конфигурации не найден: $file"
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]] \
            || log_error "Некорректная строка в $file: $line"
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        if [[ "$value" == \"*\" && "$value" == *\" ]]; then
            value="${value:1:${#value}-2}"
        elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
            value="${value:1:${#value}-2}"
        fi
        case "$key" in
            SERVER_NAME|DOMAIN|ADMIN_EMAIL|EXTERNAL_IP|DB_PASSWORD|REGISTRATION_MODE|FEDERATION_MODE|MAX_UPLOAD_SIZE|REMOTE_MEDIA_LIFETIME|PRESENCE_ENABLED|RETENTION_ENABLED|RETENTION_DEFAULT_MIN_LIFETIME|RETENTION_DEFAULT_MAX_LIFETIME|LOCAL_MEDIA_LIFETIME|MAS_DOMAIN|LIVEKIT_DOMAIN|KETESA_DOMAIN|ELEMENT_ADMIN_DOMAIN|NTFY_DOMAIN|NTFY_ADMIN_USER|PROXY_ENABLED|CONTAINER_PROXY_URL|POSTGRES_IMAGE|SYNAPSE_IMAGE|COTURN_IMAGE|MAS_IMAGE|LIVEKIT_IMAGE|LK_JWT_IMAGE|KETESA_IMAGE|ELEMENT_ADMIN_IMAGE|NTFY_IMAGE|XRAY_VERSION|IMAGE_POLICY)
                printf -v "$key" '%s' "$value"
                USER_OVERRIDES["$key"]="$value"
                ;;
            ENABLE_MAS|ENABLE_LIVEKIT|ENABLE_KETESA|ENABLE_ELEMENT_ADMIN|ENABLE_NTFY|ADMIN_USER|ADMIN_PASSWORD_FILE)
                printf -v "$key" '%s' "$value"
                USER_OVERRIDES["$key"]="$value"
                ;;
            *) log_error "Неизвестный параметр в $file: $key" ;;
        esac
    done < "$file"
    set_image_defaults
}

validate_non_interactive_config() {
    [[ -n "${SERVER_NAME:-}" ]] || log_error "В config требуется SERVER_NAME"
    [[ -n "${DOMAIN:-}" ]] || log_error "В config требуется DOMAIN"
    [[ -n "${ADMIN_EMAIL:-}" ]] || log_error "В config требуется ADMIN_EMAIL"
    is_valid_domain "$SERVER_NAME" || log_error "Некорректный SERVER_NAME: $SERVER_NAME"
    is_valid_domain "$DOMAIN" || log_error "Некорректный DOMAIN: $DOMAIN"
    [[ "$ADMIN_EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] \
        || log_error "Некорректный ADMIN_EMAIL"
    validate_registration_mode
    case "${FEDERATION_MODE:-public}" in
        restricted|public) ;;
        *) log_error "FEDERATION_MODE должен быть restricted или public" ;;
    esac
}

detect_components() {
    HAS_MAS=false
    HAS_LIVEKIT=false
    HAS_KETESA=false
    HAS_ELEMENT_ADMIN=false
    HAS_NTFY=false
    [[ -n "${MAS_DOMAIN:-}" && -f "$MATRIX_DIR/data/mas/config.yaml" ]] && HAS_MAS=true
    [[ -n "${LIVEKIT_DOMAIN:-}" && -f "$MATRIX_DIR/data/livekit/livekit.yaml" ]] && HAS_LIVEKIT=true
    [[ -n "${KETESA_DOMAIN:-}" && -f "$MATRIX_DIR/data/ketesa/config.json" ]] && HAS_KETESA=true
    [[ -n "${ELEMENT_ADMIN_DOMAIN:-}" && -f "$MATRIX_DIR/data/element-admin/.installed" ]] && HAS_ELEMENT_ADMIN=true
    [[ -n "${NTFY_DOMAIN:-}" && -f "$MATRIX_DIR/data/ntfy/server.yml" ]] && HAS_NTFY=true
    return 0
}

set_nginx_http2_syntax() {
    local nginx_version
    nginx_version=$(nginx -v 2>&1 \
        | sed -n 's#^nginx version: nginx/\([0-9][0-9.]*\).*$#\1#p')

    # Директива `http2 on` появилась в Nginx 1.25.1. Старым версиям
    # нужен прежний параметр `http2` в директиве listen.
    NGINX_HTTP2_LISTEN=" http2"
    NGINX_HTTP2_DIRECTIVE=""
    if [[ -n "$nginx_version" ]] \
        && dpkg --compare-versions "$nginx_version" ge "1.25.1"; then
        NGINX_HTTP2_LISTEN=""
        NGINX_HTTP2_DIRECTIVE="    http2 on;"
    fi
}

update_nginx_http2_config() {
    local config_file="$1"
    [[ -f "$config_file" ]] || return

    set_nginx_http2_syntax
    if [[ -z "$NGINX_HTTP2_LISTEN" ]]; then
        sed -Ei \
            's/^([[:space:]]*listen[[:space:]]+[^;]*443[[:space:]]+ssl)[[:space:]]+http2;/\1;/' \
            "$config_file"
        sed -i '/^[[:space:]]*http2 on;$/d' "$config_file"
        sed -i '/listen \[::\]:443 ssl;/a\    http2 on;' "$config_file"
    else
        sed -i '/^[[:space:]]*http2 on;$/d' "$config_file"
        sed -Ei \
            '/^[[:space:]]*listen[[:space:]]+[^;]*443[[:space:]]+ssl;$/s/ssl;/ssl http2;/' \
            "$config_file"
    fi
}

ensure_nginx_upload_limit() {
    local conf="$1"
    local tmp line
    [[ -f "$conf" ]] || return 0
    tmp=$(mktemp "${conf}.upload-limit.XXXXXX")
    awk -v domain="$DOMAIN" -v limit="$MAX_UPLOAD_SIZE" '
        {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            if (line ~ /^client_max_body_size[[:space:]]/) {
                next
            }
            print
            if (line == "server_name " domain ";") {
                print "    client_max_body_size " limit ";"
            }
        }
    ' "$conf" > "$tmp"
    chmod --reference="$conf" "$tmp"
    chown --reference="$conf" "$tmp"
    mv -f "$tmp" "$conf"
}

# ════════════════════════════════════════
#  ПРОВЕРКА СИСТЕМЫ
# ════════════════════════════════════════
check_system() {
    [[ $EUID -ne 0 ]] && log_error "Запустите от root: sudo ./install-matrix.sh"

    if ! command -v lsb_release &>/dev/null; then
        log_error "lsb_release не найден. Только Ubuntu/Debian."
    fi

    DISTRO=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
    VERSION=$(lsb_release -rs | cut -d. -f1)
    ARCHITECTURE=$(dpkg --print-architecture)
    [[ "$ARCHITECTURE" == "amd64" ]] \
        || log_error "Архитектура $ARCHITECTURE пока не проходит release E2E; поддерживается amd64"

    case "$DISTRO" in
        ubuntu)
            case "$VERSION" in
                20|22|24|26) log_ok "ОС: Ubuntu $VERSION ($ARCHITECTURE)" ;;
                *) log_error "Непроверенная Ubuntu $VERSION. Поддерживаются 20.04, 22.04, 24.04 и 26.04." ;;
            esac
            ;;
        debian)
            case "$VERSION" in
                11|12|13) log_ok "ОС: Debian $VERSION ($ARCHITECTURE)" ;;
                *) log_error "Непроверенный Debian $VERSION. Поддерживаются 11, 12 и 13." ;;
            esac
            ;;
        *)
            log_error "Неподдерживаемый дистрибутив: $DISTRO. Используйте Ubuntu или Debian."
            ;;
    esac
}

offer_swap_for_small_server() {
    local memory_kb swap_kb
    memory_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
    swap_kb=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
    if [[ "$memory_kb" -ge 4194304 || "$swap_kb" -gt 0 ]]; then
        return
    fi
    if [[ -e /swapfile ]]; then
        log_warn "Файл /swapfile уже существует, но не активен; автоматическая настройка пропущена"
    fi
    log_warn "На сервере меньше 4 ГБ RAM и нет swap"
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        [[ "$ASSUME_YES" == "true" ]] \
            || log_error "Создание swap-файла 2 ГБ требует --yes в non-interactive режиме"
        log_ok "Non-interactive режим: создаётся swap-файл 2 ГБ"
    else
        echo -ne "  Создать swap-файл 2 ГБ? [Y/n]: "
        local swap_choice
        read -r swap_choice
        if [[ -n "$swap_choice" && ! "$swap_choice" =~ ^[YyДд]$ ]]; then
            log_warn "Swap не создан"
            return
        fi
    fi
    if ! fallocate -l 2G /swapfile 2>/dev/null; then
        dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
    fi
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    grep -Fq '/swapfile none swap sw 0 0' /etc/fstab \
        || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    log_ok "Создан и включён swap 2 ГБ"
}

# ════════════════════════════════════════
#  УСТАНОВКА БАЗОВЫХ ПАКЕТОВ
# ════════════════════════════════════════
install_base_packages() {
    log_step "Установка базовых пакетов"

    # Обновляем список пакетов
    run_spinner "Обновление списка пакетов" \
        run_with_retry "apt-get update" apt-get update -qq

    # Устанавливаем необходимые зависимости (кроме Docker)
    run_spinner "Установка nginx, certbot, ufw, git и пр." \
        run_with_retry "Установка базовых пакетов" apt-get install -y -qq \
            apt-transport-https ca-certificates curl gnupg lsb-release \
            software-properties-common nginx certbot python3-certbot-nginx \
            ufw git jq dnsutils python3

    # Установка Docker из официального репозитория
    log_step "Установка Docker (официальный репозиторий)"

    # Добавляем ключ Docker
    local docker_key_file
    docker_key_file=$(mktemp "${RUNTIME_DIR:-/tmp}/docker-repository.XXXXXX.gpg")
    run_with_retry "Загрузка ключа Docker" \
        curl -fsSL "https://download.docker.com/linux/$DISTRO/gpg" \
        -o "$docker_key_file"
    gpg --batch --yes --dearmor \
        -o /usr/share/keyrings/docker-archive-keyring.gpg "$docker_key_file"
    chmod 0644 /usr/share/keyrings/docker-archive-keyring.gpg
    rm -f -- "$docker_key_file"

    # Добавляем репозиторий
    DOCKER_ARCH=$(dpkg --print-architecture)
    echo "deb [arch=$DOCKER_ARCH signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$DISTRO $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Обновляем список с Docker
    run_spinner "Обновление списка пакетов (Docker)" \
        run_with_retry "Обновление индекса Docker" apt-get update -qq

    # Устанавливаем Docker и Compose Plugin
    run_spinner "Установка docker-ce, docker-compose-plugin" \
        run_with_retry "Установка Docker" apt-get install -y -qq \
            docker-ce docker-ce-cli containerd.io docker-compose-plugin

    run_spinner "Запуск Docker" \
        bash -c "systemctl enable docker && systemctl start docker"

    # Проверяем, что docker compose работает
    if ! docker compose version &>/dev/null; then
        log_error "docker compose (плагин) не работает"
    fi
    log_ok "Docker и Compose готовы"
}

# ════════════════════════════════════════
#  ПОЛУЧЕНИЕ SSL СЕРТИФИКАТА
# ════════════════════════════════════════
get_ssl_cert() {
    local domain="$1"
    log_step "SSL сертификат для $domain"

    systemctl stop nginx 2>/dev/null || true
    if ! run_spinner "Получение сертификата для $domain" \
        run_with_retry "Certbot для $domain" certbot certonly --standalone -d "$domain" \
            --non-interactive --agree-tos \
            --email "$ADMIN_EMAIL" --no-eff-email; then
        systemctl start nginx >/dev/null 2>&1 || true
        log_error "Не удалось получить сертификат для $domain"
    fi

    CERT_EXPIRY=$(openssl x509 -noout -enddate \
        -in "/etc/letsencrypt/live/$domain/fullchain.pem" 2>/dev/null | cut -d= -f2)
    log_ok "Сертификат получен, действует до: ${CYAN}$CERT_EXPIRY${NC}"

    systemctl start nginx
}

ensure_ssl_cert() {
    local domain="$1"
    if [[ -s "/etc/letsencrypt/live/$domain/fullchain.pem" \
          && -s "/etc/letsencrypt/live/$domain/privkey.pem" ]]; then
        log_ok "Сертификат для $domain уже существует"
    else
        get_ssl_cert "$domain"
    fi
}

install_certbot_deploy_hook() {
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy
    cat > /etc/letsencrypt/renewal-hooks/deploy/matrix-coturn.sh <<EOF
#!/bin/bash
set -e
if [[ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" && -d "$MATRIX_DIR/data/coturn/tls" ]]; then
    install -m 0644 "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$MATRIX_DIR/data/coturn/tls/turn_server_cert.pem"
    install -m 0600 "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$MATRIX_DIR/data/coturn/tls/turn_server_pkey.pem"
    cd "$MATRIX_DIR"
    docker compose restart coturn >/dev/null 2>&1 || true
fi
systemctl reload nginx >/dev/null 2>&1 || true
EOF
    chmod 700 /etc/letsencrypt/renewal-hooks/deploy/matrix-coturn.sh
}

# ════════════════════════════════════════
#  НАСТРОЙКА WELL-KNOWN (ИСПРАВЛЕНО)
# ════════════════════════════════════════
configure_well_known() {
    local has_livekit="${1:-false}"
    local has_mas="${2:-false}"
    local snippet="/etc/nginx/snippets/matrix-${DOMAIN}-well-known.conf"
    local client_json
    set_nginx_http2_syntax

    # Базовая часть
    client_json="{\"m.homeserver\":{\"base_url\":\"https://$DOMAIN\"}"

    # Добавляем OIDC-данные MAS — без этого QR-код вход не работает
    if [[ "$has_mas" == "true" && -n "${MAS_DOMAIN:-}" ]]; then
        client_json="${client_json},\"org.matrix.msc2965.authentication\":{\"issuer\":\"https://$MAS_DOMAIN/\",\"account\":\"https://$MAS_DOMAIN/account\"}"
    fi

    # LiveKit RTC
    if [[ "$has_livekit" == "true" ]]; then
        client_json="${client_json},\"org.matrix.msc4143.rtc_foci\":[{\"type\":\"livekit\",\"livekit_service_url\":\"https://$DOMAIN/lk-jwt\"}]"
    fi

    client_json="${client_json}}"

    mkdir -p /etc/nginx/snippets
    cat > "$snippet" <<EOF
location = /.well-known/matrix/server {
    default_type application/json;
    add_header Access-Control-Allow-Origin "*" always;
    return 200 '{"m.server":"$DOMAIN:443"}';
}

location = /.well-known/matrix/client {
    default_type application/json;
    add_header Access-Control-Allow-Origin "*" always;
    return 200 '$client_json';
}
EOF

    if [[ "$SERVER_NAME" != "$DOMAIN" ]]; then
        local base_conf="/etc/nginx/sites-available/matrix-base-${SERVER_NAME}.conf"
        cat > "$base_conf" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $SERVER_NAME;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl${NGINX_HTTP2_LISTEN};
    listen [::]:443 ssl${NGINX_HTTP2_LISTEN};
$NGINX_HTTP2_DIRECTIVE
    server_name $SERVER_NAME;
    include $snippet;
    location / {
        default_type text/plain;
        return 200 "Matrix homeserver: $SERVER_NAME\nUse $DOMAIN for the client API.\n";
    }
    ssl_certificate /etc/letsencrypt/live/$SERVER_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$SERVER_NAME/privkey.pem;
}
EOF
        ln -sf "$base_conf" "/etc/nginx/sites-enabled/matrix-base-${SERVER_NAME}.conf"
    fi
}

# ════════════════════════════════════════
#  НАСТРОЙКА UFW
# ════════════════════════════════════════
setup_ufw() {
    log_step "Брандмауэр (UFW)"

    local ssh_port=22 ufw_status
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        ssh_port=$(awk '{print $4}' <<<"$SSH_CONNECTION")
    elif command -v sshd >/dev/null 2>&1; then
        ssh_port=$(sshd -T 2>/dev/null | awk '$1 == "port" {print $2; exit}')
        ssh_port="${ssh_port:-22}"
    fi
    [[ "$ssh_port" =~ ^[0-9]{1,5}$ && "$ssh_port" -ge 1 && "$ssh_port" -le 65535 ]] \
        || log_error "Не удалось безопасно определить SSH-порт: $ssh_port"

    for rule in \
        "$ssh_port/tcp" "80/tcp" "443/tcp" \
        "3478/tcp" "3478/udp" \
        "5349/tcp" "5349/udp" \
        "49152:49252/udp"
    do
        ufw allow "$rule" >/dev/null 2>&1
    done

    ufw_status=$(ufw status 2>/dev/null | head -n1 || true)
    if [[ "$ufw_status" != "Status: active" ]]; then
        log_warn "UFW сейчас выключен. SSH-порт $ssh_port/tcp уже добавлен в правила."
        if confirm_action "Включить UFW"; then
            ufw --force enable >/dev/null 2>&1
        else
            log_warn "UFW оставлен выключенным; правила сохранены"
            return
        fi
    fi

    log_ok "Открыты порты: SSH $ssh_port, 80, 443, 3478, 5349, 49152-49252"
}

# ════════════════════════════════════════
#  ЧТЕНИЕ / ЗАПИСЬ .ENV
# ════════════════════════════════════════
load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        chmod 600 "$ENV_FILE"
        set -a
        # Файл создаётся только этим скриптом, принадлежит root и имеет режим 0600.
        # shellcheck source=/dev/null
        source "$ENV_FILE"
        set +a
        local override_key
        for override_key in "${!USER_OVERRIDES[@]}"; do
            printf -v "$override_key" '%s' "${USER_OVERRIDES[$override_key]}"
        done
        SERVER_NAME="${SERVER_NAME:-${DOMAIN:-}}"
        DOMAIN="${DOMAIN:-$SERVER_NAME}"
        ADMIN_EMAIL="${ADMIN_EMAIL:-admin@$DOMAIN}"
        MAS_DB_PASSWORD="${MAS_DB_PASSWORD:-${DB_PASSWORD:-}}"
        REGISTRATION_MODE="${REGISTRATION_MODE:-closed}"
        FEDERATION_MODE="${FEDERATION_MODE:-public}"
        MAX_UPLOAD_SIZE="${MAX_UPLOAD_SIZE:-2048M}"
        REMOTE_MEDIA_LIFETIME="${REMOTE_MEDIA_LIFETIME:-14d}"
        PRESENCE_ENABLED="${PRESENCE_ENABLED:-false}"
        PROXY_ENABLED="${PROXY_ENABLED:-false}"
        CONTAINER_PROXY_URL="${CONTAINER_PROXY_URL:-}"
        RETENTION_ENABLED="${RETENTION_ENABLED:-true}"
        RETENTION_DEFAULT_MIN_LIFETIME="${RETENTION_DEFAULT_MIN_LIFETIME:-1d}"
        RETENTION_DEFAULT_MAX_LIFETIME="${RETENTION_DEFAULT_MAX_LIFETIME:-365d}"
        LOCAL_MEDIA_LIFETIME="${LOCAL_MEDIA_LIFETIME:-30d}"
        IMAGE_POLICY="${IMAGE_POLICY:-managed}"
        set_image_defaults
    else
        log_error "Файл .env не найден. Сначала установите Matrix (пункт 1)."
    fi
}

save_env() {
    mkdir -p "$MATRIX_DIR"
    local env_tmp
    env_tmp=$(mktemp "$MATRIX_DIR/.env.tmp.XXXXXX")
    {
        echo "# MATRIX SERVER ENVIRONMENT — generated by Install-Matrix v$INSTALLER_VERSION"
        printf 'SERVER_NAME=%q\n' "$SERVER_NAME"
        printf 'DOMAIN=%q\n' "$DOMAIN"
        printf 'ADMIN_EMAIL=%q\n' "$ADMIN_EMAIL"
        printf 'EXTERNAL_IP=%q\n' "$EXTERNAL_IP"
        printf 'DB_PASSWORD=%q\n' "$DB_PASSWORD"
        printf 'REG_SHARED_SECRET=%q\n' "$REG_SHARED_SECRET"
        printf 'MACAROON_SECRET=%q\n' "$MACAROON_SECRET"
        printf 'FORM_SECRET=%q\n' "$FORM_SECRET"
        printf 'TURN_SECRET=%q\n' "$TURN_SECRET"
        printf 'MAS_DOMAIN=%q\n' "${MAS_DOMAIN:-}"
        printf 'MAS_SECRET=%q\n' "${MAS_SECRET:-}"
        printf 'MAS_DB_PASSWORD=%q\n' "${MAS_DB_PASSWORD:-${DB_PASSWORD:-}}"
        printf 'LIVEKIT_DOMAIN=%q\n' "${LIVEKIT_DOMAIN:-}"
        printf 'LIVEKIT_KEY=%q\n' "${LIVEKIT_KEY:-}"
        printf 'LIVEKIT_SECRET=%q\n' "${LIVEKIT_SECRET:-}"
        printf 'KETESA_DOMAIN=%q\n' "${KETESA_DOMAIN:-}"
        printf 'ELEMENT_ADMIN_DOMAIN=%q\n' "${ELEMENT_ADMIN_DOMAIN:-}"
        printf 'NTFY_DOMAIN=%q\n' "${NTFY_DOMAIN:-}"
        printf 'NTFY_ADMIN_USER=%q\n' "${NTFY_ADMIN_USER:-}"
        printf 'PROXY_ENABLED=%q\n' "${PROXY_ENABLED:-false}"
        printf 'CONTAINER_PROXY_URL=%q\n' "${CONTAINER_PROXY_URL:-}"
        printf 'REGISTRATION_MODE=%q\n' "${REGISTRATION_MODE:-closed}"
        printf 'FEDERATION_MODE=%q\n' "${FEDERATION_MODE:-public}"
        printf 'MAX_UPLOAD_SIZE=%q\n' "${MAX_UPLOAD_SIZE:-2048M}"
        printf 'REMOTE_MEDIA_LIFETIME=%q\n' "${REMOTE_MEDIA_LIFETIME:-14d}"
        printf 'PRESENCE_ENABLED=%q\n' "${PRESENCE_ENABLED:-false}"
        printf 'POSTGRES_IMAGE=%q\n' "$POSTGRES_IMAGE"
        printf 'SYNAPSE_IMAGE=%q\n' "$SYNAPSE_IMAGE"
        printf 'COTURN_IMAGE=%q\n' "$COTURN_IMAGE"
        printf 'MAS_IMAGE=%q\n' "$MAS_IMAGE"
        printf 'LIVEKIT_IMAGE=%q\n' "$LIVEKIT_IMAGE"
        printf 'LK_JWT_IMAGE=%q\n' "$LK_JWT_IMAGE"
        printf 'KETESA_IMAGE=%q\n' "$KETESA_IMAGE"
        printf 'ELEMENT_ADMIN_IMAGE=%q\n' "$ELEMENT_ADMIN_IMAGE"
        printf 'NTFY_IMAGE=%q\n' "$NTFY_IMAGE"
        printf 'XRAY_VERSION=%q\n' "$XRAY_VERSION"
        printf 'IMAGE_POLICY=%q\n' "${IMAGE_POLICY:-managed}"
        printf 'RETENTION_ENABLED=%q\n' "${RETENTION_ENABLED:-true}"
        printf 'RETENTION_DEFAULT_MIN_LIFETIME=%q\n' "${RETENTION_DEFAULT_MIN_LIFETIME:-1d}"
        printf 'RETENTION_DEFAULT_MAX_LIFETIME=%q\n' "${RETENTION_DEFAULT_MAX_LIFETIME:-365d}"
        printf 'LOCAL_MEDIA_LIFETIME=%q\n' "${LOCAL_MEDIA_LIFETIME:-30d}"
    } > "$env_tmp"
    chmod 600 "$env_tmp"
    mv -f "$env_tmp" "$ENV_FILE"
}

# ════════════════════════════════════════
#  ГЕНЕРАЦИЯ DOCKER-COMPOSE.YML
# ════════════════════════════════════════
generate_compose() {
    local has_mas="${1:-false}"
    local has_livekit="${2:-false}"
    local has_ketesa="${3:-false}"
    local has_element_admin="${4:-false}"
    local has_ntfy="${5:-false}"

    cat > "$COMPOSE_FILE" <<EOF
services:
  postgres:
    image: $POSTGRES_IMAGE
    container_name: matrix-postgres
    restart: unless-stopped
    volumes:
      - ./data/postgres:/var/lib/postgresql/data
    environment:
      POSTGRES_USER: synapse
      POSTGRES_PASSWORD: $DB_PASSWORD
      POSTGRES_DB: synapse
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U synapse -d synapse"]
      interval: 10s
      timeout: 5s
      retries: 10
    networks:
      - matrix

  synapse:
    image: $SYNAPSE_IMAGE
    container_name: matrix-synapse
    restart: unless-stopped
    depends_on:
      - postgres
EOF

    if [[ "$has_mas" == "true" ]]; then
        cat >> "$COMPOSE_FILE" <<EOF
      - mas
EOF
    fi

    cat >> "$COMPOSE_FILE" <<EOF
    ports:
      - "127.0.0.1:8008:8008"
    volumes:
      - ./data/synapse:/data
    environment:
      SYNAPSE_SERVER_NAME: $SERVER_NAME
      SYNAPSE_REPORT_STATS: "no"
      HTTP_PROXY: "${CONTAINER_PROXY_URL:-}"
      HTTPS_PROXY: "${CONTAINER_PROXY_URL:-}"
      NO_PROXY: "localhost,127.0.0.1,postgres,mas,mas-db,ntfy,$DOMAIN,$SERVER_NAME,172.16.0.0/12"
      http_proxy: "${CONTAINER_PROXY_URL:-}"
      https_proxy: "${CONTAINER_PROXY_URL:-}"
      no_proxy: "localhost,127.0.0.1,postgres,mas,mas-db,ntfy,$DOMAIN,$SERVER_NAME,172.16.0.0/12"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    healthcheck:
      test: ["CMD", "curl", "-fSs", "http://localhost:8008/health"]
      interval: 15s
      timeout: 5s
      retries: 10
      start_period: 20s
    networks:
      - matrix

  coturn:
    image: $COTURN_IMAGE
    container_name: matrix-coturn
    restart: unless-stopped
    network_mode: host
    command: ["-c", "/etc/coturn/turnserver.conf", "--log-file=stdout"]
    volumes:
      - ./data/coturn/turnserver.conf:/etc/coturn/turnserver.conf:ro
      - ./data/coturn/tls:/etc/coturn/tls:ro
EOF

    if [[ "$has_mas" == "true" ]]; then
        cat >> "$COMPOSE_FILE" <<EOF

  mas-db:
    image: $POSTGRES_IMAGE
    container_name: mas-db
    restart: unless-stopped
    volumes:
      - ./data/mas-db:/var/lib/postgresql/data
    environment:
      POSTGRES_USER: mas_user
      POSTGRES_PASSWORD: ${MAS_DB_PASSWORD:-$DB_PASSWORD}
      POSTGRES_DB: mas
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U mas_user -d mas"]
      interval: 10s
      timeout: 5s
      retries: 10
    networks:
      - matrix

  mas:
    image: $MAS_IMAGE
    container_name: matrix-mas
    restart: unless-stopped
    depends_on:
      - mas-db
    ports:
      - "127.0.0.1:8080:8080"
    volumes:
      - ./data/mas/config.yaml:/app/config/config.yaml:ro
      - ./data/synapse/homeserver.yaml:/data/synapse/homeserver.yaml:ro
    environment:
      - MAS_CONFIG=/app/config/config.yaml
      - HTTP_PROXY=${CONTAINER_PROXY_URL:-}
      - HTTPS_PROXY=${CONTAINER_PROXY_URL:-}
      - NO_PROXY=localhost,127.0.0.1,synapse,postgres,mas-db,$DOMAIN,$SERVER_NAME,172.16.0.0/12
      - http_proxy=${CONTAINER_PROXY_URL:-}
      - https_proxy=${CONTAINER_PROXY_URL:-}
      - no_proxy=localhost,127.0.0.1,synapse,postgres,mas-db,$DOMAIN,$SERVER_NAME,172.16.0.0/12
    networks:
      - matrix
EOF
    fi

    if [[ "$has_livekit" == "true" ]]; then
        cat >> "$COMPOSE_FILE" <<EOF

  livekit:
    image: $LIVEKIT_IMAGE
    container_name: matrix-livekit
    restart: unless-stopped
    network_mode: host
    command: --config /etc/livekit.yaml
    volumes:
      - ./data/livekit/livekit.yaml:/etc/livekit.yaml:ro

  lk-jwt-service:
    image: $LK_JWT_IMAGE
    container_name: matrix-lk-jwt
    restart: unless-stopped
    depends_on:
      - mas
    ports:
      - "127.0.0.1:8082:8080"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      - LIVEKIT_URL=wss://$LIVEKIT_DOMAIN
      - LIVEKIT_KEY=$LIVEKIT_KEY
      - LIVEKIT_SECRET=$LIVEKIT_SECRET
      - LIVEKIT_FULL_ACCESS_HOMESERVERS=$SERVER_NAME
    networks:
      - matrix
EOF
    fi

    if [[ "$has_ketesa" == "true" ]]; then
        cat >> "$COMPOSE_FILE" <<EOF

  ketesa:
    image: $KETESA_IMAGE
    container_name: matrix-ketesa
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:8080/"]
      interval: 30s
      timeout: 5s
      retries: 5
    ports:
      - "127.0.0.1:8083:8080"
    volumes:
      - ./data/ketesa/config.json:/var/public/config.json:ro
    environment:
      - SERVER_HOST=0.0.0.0
    networks:
      - matrix
EOF
    fi

    if [[ "$has_element_admin" == "true" ]]; then
        cat >> "$COMPOSE_FILE" <<EOF

  element-admin:
    image: $ELEMENT_ADMIN_IMAGE
    container_name: matrix-element-admin
    restart: unless-stopped
    ports:
      - "127.0.0.1:8084:8080"
    environment:
      - SERVER_NAME=$SERVER_NAME
    networks:
      - matrix
EOF
    fi

    if [[ "$has_ntfy" == "true" ]]; then
        cat >> "$COMPOSE_FILE" <<EOF

  ntfy:
    image: $NTFY_IMAGE
    container_name: matrix-ntfy
    restart: unless-stopped
    init: true
    command: serve
    ports:
      - "127.0.0.1:8090:80"
    volumes:
      - ./data/ntfy/server.yml:/etc/ntfy/server.yml:ro
      - ./data/ntfy/cache:/var/cache/ntfy
      - ./data/ntfy/data:/var/lib/ntfy
    environment:
      - TZ=UTC
      - HTTP_PROXY=${CONTAINER_PROXY_URL:-}
      - HTTPS_PROXY=${CONTAINER_PROXY_URL:-}
      - NO_PROXY=localhost,127.0.0.1,$DOMAIN,$SERVER_NAME,172.16.0.0/12
      - http_proxy=${CONTAINER_PROXY_URL:-}
      - https_proxy=${CONTAINER_PROXY_URL:-}
      - no_proxy=localhost,127.0.0.1,$DOMAIN,$SERVER_NAME,172.16.0.0/12
    extra_hosts:
      - "host.docker.internal:host-gateway"
    healthcheck:
      test: ["CMD-SHELL", "unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy; wget -q --tries=1 http://127.0.0.1:80/v1/health -O - | grep -q true"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 20s
    networks:
      - matrix
EOF
    fi

    cat >> "$COMPOSE_FILE" <<EOF

networks:
  matrix:
    driver: bridge
EOF

    log_ok "docker-compose.yml сгенерирован"
}

# ════════════════════════════════════════
#  ГЕНЕРАЦИЯ HOMESERVER.YAML
# ════════════════════════════════════════
generate_homeserver() {
    local has_mas="${1:-false}"
    local has_livekit="${2:-false}"

    mkdir -p "$(dirname "$HOMESERVER_FILE")"

    cat > "$HOMESERVER_FILE" <<EOF
# Configuration file for Synapse.
server_name: "$SERVER_NAME"
pid_file: /data/homeserver.pid

listeners:
  - port: 8008
    bind_addresses: ['0.0.0.0']
    resources:
      - compress: false
        names: [client, federation]
    tls: false
    type: http
    x_forwarded: true

database:
  name: psycopg2
  allow_unsafe_locale: true
  args:
    user: synapse
    password: $DB_PASSWORD
    host: postgres
    port: 5432
    database: synapse

media_store_path: /data/media_store
max_upload_size: $MAX_UPLOAD_SIZE
EOF

    # Synapse has a dedicated federation HTTP agent.  Writing the proxy into
    # homeserver.yaml makes its CONNECT path deterministic instead of relying
    # only on inherited container environment variables.
    if [[ "${PROXY_ENABLED:-false}" == "true" && -n "${CONTAINER_PROXY_URL:-}" ]]; then
        cat >> "$HOMESERVER_FILE" <<EOF

http_proxy: "$CONTAINER_PROXY_URL"
https_proxy: "$CONTAINER_PROXY_URL"
no_proxy_hosts:
  - "localhost"
  - "127.0.0.1"
  - "postgres"
  - "mas"
  - "mas-db"
  - "ntfy"
  - "$DOMAIN"
  - "$SERVER_NAME"
  - "172.16.0.0/12"
EOF
    fi

cat >> "$HOMESERVER_FILE" <<EOF
media_retention:
  local_media_lifetime: $LOCAL_MEDIA_LIFETIME
  remote_media_lifetime: $REMOTE_MEDIA_LIFETIME
EOF

# Секция retention (если включена)
if [[ "$RETENTION_ENABLED" == "true" ]]; then
    cat >> "$HOMESERVER_FILE" <<EOF

retention:
  enabled: true
  default_policy:
    min_lifetime: $RETENTION_DEFAULT_MIN_LIFETIME
    max_lifetime: $RETENTION_DEFAULT_MAX_LIFETIME
  allowed_lifetime_min: $RETENTION_DEFAULT_MIN_LIFETIME
  allowed_lifetime_max: $RETENTION_DEFAULT_MAX_LIFETIME
  purge_jobs:
    - longest_max_lifetime: 3d
      interval: 12h
    - shortest_min_lifetime: 3d
      interval: 24h
EOF
fi
cat >> "$HOMESERVER_FILE" <<EOF

user_directory:
  enabled: true
  search_all_users: true
  prefer_local_users: true
  exclude_remote_users: false

presence:
  enabled: $PRESENCE_ENABLED

limit_remote_rooms:
  enabled: false
  complexity: 15.0
  complexity_error: "Этот сервер не может подключаться к настолько большой или сложной комнате."
  admins_can_join: true

registration_shared_secret: "$REG_SHARED_SECRET"
report_stats: false
EOF

    # Три режима регистрации; open включается только после явного подтверждения риска.
    if [[ "$has_mas" == "true" ]]; then
        echo "enable_registration: false" >> "$HOMESERVER_FILE"
        echo "enable_registration_without_verification: false" >> "$HOMESERVER_FILE"
    elif [[ "$REGISTRATION_MODE" == "token" ]]; then
        echo "enable_registration: true" >> "$HOMESERVER_FILE"
        echo "registration_requires_token: true" >> "$HOMESERVER_FILE"
    elif [[ "$REGISTRATION_MODE" == "open" ]]; then
        echo "enable_registration: true" >> "$HOMESERVER_FILE"
        echo "registration_requires_token: false" >> "$HOMESERVER_FILE"
        echo "enable_registration_without_verification: true" >> "$HOMESERVER_FILE"
    else
        echo "enable_registration: false" >> "$HOMESERVER_FILE"
        echo "enable_registration_without_verification: false" >> "$HOMESERVER_FILE"
    fi

    cat >> "$HOMESERVER_FILE" <<EOF
suppress_key_server_warning: true
macaroon_secret_key: "$MACAROON_SECRET"
form_secret: "$FORM_SECRET"
signing_key_path: "/data/${SERVER_NAME}.signing.key"

trusted_key_servers:
  - server_name: "matrix.org"

public_baseurl: https://$DOMAIN/
serve_server_wellknown: false

turn_uris:
  - "turn:$DOMAIN?transport=udp"
  - "turn:$DOMAIN?transport=tcp"
  - "turns:$DOMAIN?transport=tcp"

turn_shared_secret: "$TURN_SECRET"
turn_allow_guests: false
turn_user_lifetime: 86400000
EOF

    if [[ "$has_mas" == "true" ]]; then
        cat >> "$HOMESERVER_FILE" <<EOF

matrix_authentication_service:
    enabled: true
    endpoint: "http://mas:8080/"
    secret: "$MAS_SECRET"
    rendezvous_enabled: true
EOF
    fi

    if [[ "$has_livekit" == "true" ]]; then
        cat >> "$HOMESERVER_FILE" <<EOF

experimental_features:
  msc3266_enabled: true
  msc4143_enabled: true
  msc4222_enabled: true
  msc4108_enabled: true

matrix_rtc:
  transports:
    - type: livekit
      livekit_service_url: "https://$DOMAIN/lk-jwt"

extra_well_known_client_content:
  org.matrix.msc4143.rtc_foci:
    - type: livekit
      livekit_service_url: "https://$DOMAIN/lk-jwt"
EOF
    fi

    if [[ "$FEDERATION_MODE" == "restricted" ]]; then
        echo "" >> "$HOMESERVER_FILE"
        echo "federation_domain_whitelist:" >> "$HOMESERVER_FILE"
        if [[ -s "$FEDERATION_FILE" ]]; then
            while IFS= read -r federation_domain; do
                [[ -z "$federation_domain" ]] && continue
                printf '  - "%s"\n' "$federation_domain" >> "$HOMESERVER_FILE"
            done < "$FEDERATION_FILE"
        else
            log_warn "Включён закрытый режим федерации, но allowlist пуст: исходящая федерация будет запрещена"
        fi
    fi

    if [[ "${SKIP_OWNERSHIP:-false}" != "true" ]]; then
        chown 991:991 "$(dirname "$HOMESERVER_FILE")" "$HOMESERVER_FILE"
    fi
    chmod 750 "$(dirname "$HOMESERVER_FILE")"
    chmod 640 "$HOMESERVER_FILE"
    log_ok "homeserver.yaml сгенерирован"
}

# ════════════════════════════════════════
#  УСТАНОВКА MATRIX (пункт 1)
# ════════════════════════════════════════
ensure_initial_admin() {
    log_step "Создание администратора"
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        if [[ -z "${ADMIN_USER:-}" || -z "${ADMIN_PASSWORD_FILE:-}" ]]; then
            log_warn "Администратор не создан: задайте ADMIN_USER и ADMIN_PASSWORD_FILE"
            return
        fi
        [[ "$ADMIN_USER" =~ ^[A-Za-z0-9._=-]{1,255}$ ]] \
            || log_error "Некорректный ADMIN_USER"
        [[ -f "$ADMIN_PASSWORD_FILE" ]] \
            || log_error "ADMIN_PASSWORD_FILE не найден: $ADMIN_PASSWORD_FILE"

        local matrix_user existing_user
        matrix_user="@${ADMIN_USER}:${SERVER_NAME}"
        existing_user=$(docker compose exec -T postgres psql -U synapse -d synapse \
            -tAc "SELECT 1 FROM users WHERE name = '$matrix_user' LIMIT 1" 2>/dev/null \
            | tr -d '[:space:]')
        if [[ "$existing_user" == "1" ]]; then
            log_ok "Администратор $matrix_user уже существует"
            return
        fi

        local admin_password
        admin_password=$(<"$ADMIN_PASSWORD_FILE")
        [[ ${#admin_password} -ge 12 ]] \
            || log_error "Пароль администратора должен содержать минимум 12 символов"
        docker compose exec -T synapse register_new_matrix_user \
            http://localhost:8008 -c /data/homeserver.yaml --admin \
            --user "$ADMIN_USER" --password "$admin_password"
        unset admin_password
        log_ok "Администратор $matrix_user создан"
    else
        echo ""
        echo -e "  ${DIM}Введите данные для первого аккаунта:${NC}"
        echo ""
        docker compose exec synapse register_new_matrix_user \
            http://localhost:8008 -c /data/homeserver.yaml --admin
    fi
}

ensure_coturn_permissions() {
    local coturn_dir="$MATRIX_DIR/data/coturn"
    local tls_dir="$coturn_dir/tls"

    [[ -d "$coturn_dir" ]] || return 0
    # The pinned Coturn image drops privileges to nobody:nogroup (65534).
    # Grant that group read-only access without making the TURN secret or TLS
    # private key world-readable.
    chown root:65534 "$coturn_dir"
    chmod 0750 "$coturn_dir"
    if [[ -f "$coturn_dir/turnserver.conf" ]]; then
        chown root:65534 "$coturn_dir/turnserver.conf"
        chmod 0640 "$coturn_dir/turnserver.conf"
    fi
    if [[ -d "$tls_dir" ]]; then
        chown root:65534 "$tls_dir"
        chmod 0750 "$tls_dir"
    fi
    if [[ -f "$tls_dir/turn_server_cert.pem" ]]; then
        chown root:65534 "$tls_dir/turn_server_cert.pem"
        chmod 0640 "$tls_dir/turn_server_cert.pem"
    fi
    if [[ -f "$tls_dir/turn_server_pkey.pem" ]]; then
        chown root:65534 "$tls_dir/turn_server_pkey.pem"
        chmod 0640 "$tls_dir/turn_server_pkey.pem"
    fi
}

install_matrix() {
    log_step "Установка Matrix (базовая)"

    # Повторный запуск не должен менять секреты уже созданной базы данных.
    if [[ -f "$ENV_FILE" && -f "$MATRIX_DIR/data/postgres/PG_VERSION" ]]; then
        load_env
        detect_components

        cd "$MATRIX_DIR"
        generate_compose "$HAS_MAS" "$HAS_LIVEKIT" "$HAS_KETESA" "$HAS_ELEMENT_ADMIN" "$HAS_NTFY"
        generate_homeserver "$HAS_MAS" "$HAS_LIVEKIT"
        configure_well_known "$HAS_LIVEKIT" "$HAS_MAS"   # исправлено
        ensure_coturn_permissions
        update_nginx_http2_config "/etc/nginx/sites-available/matrix-${DOMAIN}.conf"
        ensure_nginx_upload_limit "/etc/nginx/sites-available/matrix-${DOMAIN}.conf"
        if [[ "$HAS_MAS" == "true" ]]; then
            update_nginx_http2_config "/etc/nginx/sites-available/mas-${MAS_DOMAIN}.conf"
        fi
        if [[ "$HAS_LIVEKIT" == "true" ]]; then
            update_nginx_http2_config "/etc/nginx/sites-available/livekit-${LIVEKIT_DOMAIN}.conf"
        fi
        nginx -t >/dev/null 2>&1 || log_error "Ошибка конфигурации Nginx"
        systemctl reload nginx
        run_spinner "Проверка существующего стека Matrix" \
            docker compose up -d
        run_spinner "Перезапуск Synapse с актуальной конфигурацией" \
            docker compose restart synapse
        wait_for_url "https://$DOMAIN/_matrix/client/versions" "Публичный Matrix API"
        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            ensure_initial_admin
        fi
        log_ok "Matrix уже установлен; конфигурация проверена без смены секретов"
        return
    fi

    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        validate_non_interactive_config
    else
        echo ""
        echo -e "  ${DIM}Основной домен определяет Matrix ID: @user:example.com.${NC}"
        SERVER_NAME=$(read_domain "Основной домен" "example.com")
        DOMAIN=$(read_domain "Домен Matrix API" "matrix.$SERVER_NAME")

        echo ""
        echo -ne "  ${CYAN}▶${NC}  Email для Let's Encrypt: "
        read -r ADMIN_EMAIL
        [[ "$ADMIN_EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] \
            || log_error "Некорректный email для Let's Encrypt"

        echo ""
        echo "  Регистрация: 1 — закрытая, 2 — по токену, 3 — открытая без проверки"
        echo -ne "  ${CYAN}▶${NC}  Режим [1]: "
        read -r REG_CHOICE
        case "${REG_CHOICE:-1}" in
            1) REGISTRATION_MODE="closed" ;;
            2) REGISTRATION_MODE="token" ;;
            3)
                log_warn "Открытая регистрация без проверки допускает массовое создание аккаунтов и abuse"
                confirm_action "Я понимаю риск и хочу включить открытую регистрацию" \
                    || log_error "Открытая регистрация отменена"
                ALLOW_OPEN_REGISTRATION=true
                REGISTRATION_MODE="open"
                ;;
            *) log_error "Неверный режим регистрации" ;;
        esac
    fi

    # Безопасные defaults можно переопределить config-файлом.
    FEDERATION_MODE="${FEDERATION_MODE:-public}"
    MAX_UPLOAD_SIZE="${MAX_UPLOAD_SIZE:-2048M}"
    REMOTE_MEDIA_LIFETIME="${REMOTE_MEDIA_LIFETIME:-14d}"
    PRESENCE_ENABLED="${PRESENCE_ENABLED:-false}"
    PROXY_ENABLED="${PROXY_ENABLED:-false}"
    CONTAINER_PROXY_URL="${CONTAINER_PROXY_URL:-}"
    RETENTION_ENABLED="${RETENTION_ENABLED:-true}"
    RETENTION_DEFAULT_MIN_LIFETIME="${RETENTION_DEFAULT_MIN_LIFETIME:-1d}"
    RETENTION_DEFAULT_MAX_LIFETIME="${RETENTION_DEFAULT_MAX_LIFETIME:-365d}"
    LOCAL_MEDIA_LIFETIME="${LOCAL_MEDIA_LIFETIME:-30d}"
    IMAGE_POLICY="${IMAGE_POLICY:-managed}"
    set_image_defaults

    if [[ "$NON_INTERACTIVE" == "false" ]]; then
        echo ""
        echo -e "  ${DIM}Пароль PostgreSQL (Enter = автогенерация):${NC}"
        echo -ne "  ${CYAN}▶${NC}  "
        read -rs DB_PASSWORD
        echo ""
    fi

    if [[ -z "$DB_PASSWORD" ]]; then
        DB_PASSWORD=$(generate_secret 24)
        log_ok "Пароль БД сгенерирован: ${CYAN}$DB_PASSWORD${NC}"
    else
        [[ "$DB_PASSWORD" =~ ^[A-Za-z0-9._~-]{12,128}$ ]] \
            || log_error "Ручной пароль БД: 12–128 символов A-Z, a-z, 0-9, точка, _, ~ или -"
        log_ok "Пароль БД задан вручную"
    fi

    # Внешний IP
    EXTERNAL_IP="${EXTERNAL_IP:-$(curl -4 -s --max-time 5 https://ifconfig.me 2>/dev/null \
               || curl -4 -s --max-time 5 https://api.ipify.org 2>/dev/null)}"
    [[ -z "$EXTERNAL_IP" ]] && log_error "Не удалось определить внешний IP."
    log_ok "Внешний IP: ${CYAN}$EXTERNAL_IP${NC}"

    # Проверка DNS выполняется всегда через getent, который входит в базовую систему.
    for required_domain in "$DOMAIN" "$SERVER_NAME"; do
        RESOLVED_IP=$(getent ahostsv4 "$required_domain" 2>/dev/null | awk 'NR==1 {print $1}')
        if [[ "$RESOLVED_IP" != "$EXTERNAL_IP" ]]; then
            log_error "DNS $required_domain указывает на '${RESOLVED_IP:-ничего}', ожидался $EXTERNAL_IP"
        fi
        log_ok "DNS: ${CYAN}$required_domain${NC} → ${CYAN}$EXTERNAL_IP${NC}"
    done

    # Генерация секретов
    REG_SHARED_SECRET=$(generate_secret 32)
    MACAROON_SECRET=$(generate_secret 32)
    FORM_SECRET=$(generate_secret 32)
    TURN_SECRET=$(openssl rand -hex 32)

    log_ok "Секреты сгенерированы"

    # Установка пакетов
    install_base_packages
    offer_swap_for_small_server

    # Создание структуры
    mkdir -p "$MATRIX_DIR"/data/{postgres,synapse,coturn/tls}
    touch "$FEDERATION_FILE"
    chmod 600 "$FEDERATION_FILE"
    cd "$MATRIX_DIR"

    # Сохраняем переменные
    save_env

    # Генерация compose и homeserver (без MAS и LiveKit)
    generate_compose false false false false false
    generate_homeserver false false

    # Конфиг Coturn
    cat > data/coturn/turnserver.conf <<EOF
listening-port=3478
tls-listening-port=5349
listening-ip=0.0.0.0
relay-ip=$EXTERNAL_IP

cert=/etc/coturn/tls/turn_server_cert.pem
pkey=/etc/coturn/tls/turn_server_pkey.pem

use-auth-secret
static-auth-secret=$TURN_SECRET
realm=$DOMAIN

min-port=49152
max-port=49252
total-quota=100

log-file=/var/tmp/turnserver.log
EOF

    # SSL для основного домена
    get_ssl_cert "$DOMAIN"
    if [[ "$SERVER_NAME" != "$DOMAIN" ]]; then
        get_ssl_cert "$SERVER_NAME"
    fi

    # Копирование сертификатов для Coturn
    cp /etc/letsencrypt/live/"$DOMAIN"/fullchain.pem data/coturn/tls/turn_server_cert.pem
    cp /etc/letsencrypt/live/"$DOMAIN"/privkey.pem   data/coturn/tls/turn_server_pkey.pem
    ensure_coturn_permissions
    install_certbot_deploy_hook
    log_ok "Сертификаты скопированы для Coturn"

    # Nginx для основного домена
    set_nginx_http2_syntax
    NGINX_CONF="/etc/nginx/sites-available/matrix-${DOMAIN}.conf"
    configure_well_known false false   # исправлено
    cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    client_max_body_size $MAX_UPLOAD_SIZE;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl${NGINX_HTTP2_LISTEN};
    listen [::]:443 ssl${NGINX_HTTP2_LISTEN};
$NGINX_HTTP2_DIRECTIVE
    server_name $DOMAIN;

    client_max_body_size $MAX_UPLOAD_SIZE;

    include /etc/nginx/snippets/matrix-${DOMAIN}-*.conf;

    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    location / {
        proxy_pass http://127.0.0.1:8008;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
        proxy_read_timeout 86400s;
    }

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
}
EOF

    rm -f /etc/nginx/sites-enabled/default
    ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
    nginx -t >/dev/null 2>&1 || log_error "Ошибка конфигурации Nginx"
    systemctl reload-or-restart nginx
    log_ok "Nginx запущен"

    # UFW
    setup_ufw

    # Запуск сервисов
    log_step "Запуск сервисов"
    run_spinner "Запуск PostgreSQL, Synapse, Coturn" \
        docker compose up -d

    # Ожидание Synapse
    echo -ne "  ${CYAN}⠋${NC}  ${DIM}Synapse запускается...${NC}"
    TIMEOUT=120
    ELAPSED=0
    while ! curl -s http://localhost:8008/_matrix/client/versions >/dev/null 2>&1; do
        sleep 2
        ELAPSED=$((ELAPSED + 2))
        printf "\r  ${CYAN}⠙${NC}  ${DIM}Synapse запускается... %ds${NC}     " "$ELAPSED"
        if [[ $ELAPSED -ge $TIMEOUT ]]; then
            echo ""
            log_error "Synapse не ответил за ${TIMEOUT}с. Проверьте: docker compose logs synapse"
        fi
    done
    printf "\r  ${BGREEN}✓${NC}  ${WHITE}Synapse готов!${NC}                        \n"
    wait_for_url "https://$DOMAIN/_matrix/client/versions" "Публичный Matrix API"

    # Создание администратора
    ensure_initial_admin

    # Сохранение учётных данных
    CREDS_FILE="$MATRIX_DIR/credentials.txt"
    cat > "$CREDS_FILE" <<CREDS
Matrix Server — Credentials
============================
Date:        $(date)
Server name: $SERVER_NAME
Matrix API:  https://$DOMAIN

DB User:     synapse
DB Password: $DB_PASSWORD
DB Name:     synapse

TURN Secret: $TURN_SECRET

Working dir: $MATRIX_DIR
CREDS
    chmod 600 "$CREDS_FILE"

    run_diagnostics || log_warn "Установка завершена, но часть health checks не пройдена"

    # Финальный вывод
    echo ""
    echo ""
    echo -e "${BGREEN}  ╔══════════════════════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BGREEN}  ║                                                                                                  ║${NC}"
    echo -e "${BGREEN}  ║                                 УСТАНОВКА MATRIX ЗАВЕРШЕНА!                                      ║${NC}"
    echo -e "${BGREEN}  ║                                                                                                  ║${NC}"
    echo -e "${BGREEN}  ╠══════════════════════════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BGREEN}  ║                                                                                                  ║${NC}"
    echo -e "${BGREEN}  ║${NC}  ${WHITE}Matrix ID:${NC}    ${CYAN}@user:$SERVER_NAME${NC}                                  ║${NC}"
    echo -e "${BGREEN}  ║${NC}  ${WHITE}Matrix API:${NC}   ${CYAN}https://$DOMAIN${NC}                                     ║${NC}"
    echo -e "${BGREEN}  ║                                                                                                  ║${NC}"
    echo -e "${BGREEN}  ║${NC}  ${YELLOW}Секреты не выводятся в терминал; см. защищённый credentials.txt.${NC}                 ║${NC}"
    echo -e "${BGREEN}  ║                                                                                                  ║${NC}"
    echo -e "${BGREEN}  ╠══════════════════════════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BGREEN}  ║                                                                                                  ║${NC}"
    echo -e "${BGREEN}  ║${NC}  ${DIM}Логи:${NC}     ${CYAN}docker compose logs -f                                         ║${NC}"
    echo -e "${BGREEN}  ║${NC}  ${DIM}Рестарт:${NC}  ${CYAN}docker compose restart                                         ║${NC}"
    echo -e "${BGREEN}  ║${NC}  ${DIM}Статус:${NC}   ${CYAN}docker compose ps                                              ║${NC}"
    echo -e "${BGREEN}  ║${NC}                                                                                             ║${NC}"
    echo -e "${BGREEN}  ║${NC}  ${DIM}Учётные данные сохранены в:                                                          ║${NC}"
    echo -e "${BGREEN}  ║${NC}  ${CYAN}$CREDS_FILE                                                                         ║${NC}"
    echo -e "${BGREEN}  ║                                                                                                  ║${NC}"
    echo -e "${BGREEN}  ╚══════════════════════════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "               ${PURPLE}◆${NC}  ${DIM}made by${NC}  ${BPURPLE}zxchubbabubba${NC}  ${PURPLE}◆${NC}"
    echo ""
}

# ════════════════════════════════════════
#  УСТАНОВКА MAS (пункт 2)
# ════════════════════════════════════════
install_mas() {
    log_step "Установка Matrix Authentication Service (MAS)"

    # Проверяем, что Matrix уже установлен
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error "Файл .env не найден. Сначала установите Matrix (пункт 1)."
    fi

    load_env
    validate_registration_mode
    set_mas_registration_flags

    MIGRATION_MARKER="$MATRIX_DIR/data/mas/.syn2mas-complete"
    if [[ -n "${MAS_DOMAIN:-}" && -n "${MAS_SECRET:-}" \
          && -f "$MATRIX_DIR/data/mas/config.yaml" \
          && -f "$MIGRATION_MARKER" ]]; then
        detect_components
        cd "$MATRIX_DIR"
        generate_compose true "$HAS_LIVEKIT" "$HAS_KETESA" "$HAS_ELEMENT_ADMIN" "$HAS_NTFY"
        generate_homeserver true "$HAS_LIVEKIT"
        configure_well_known "$HAS_LIVEKIT" true   # исправлено
        update_nginx_http2_config "/etc/nginx/sites-available/matrix-${DOMAIN}.conf"
        update_nginx_http2_config "/etc/nginx/sites-available/mas-${MAS_DOMAIN}.conf"
        if [[ "$HAS_LIVEKIT" == "true" ]]; then
            update_nginx_http2_config "/etc/nginx/sites-available/livekit-${LIVEKIT_DOMAIN}.conf"
        fi
        nginx -t >/dev/null 2>&1 || log_error "Ошибка конфигурации Nginx"
        systemctl reload nginx
        run_spinner "Проверка существующего стека MAS" \
            docker compose up -d
        run_spinner "Перезапуск Synapse с конфигурацией MAS" \
            docker compose restart synapse
        wait_for_url "https://$MAS_DOMAIN/.well-known/openid-configuration" "MAS OIDC discovery"
        wait_for_url "https://$DOMAIN/_matrix/client/versions" "Matrix API после включения MAS"
        if [[ "$HAS_LIVEKIT" == "true" ]]; then
            wait_for_url "https://$DOMAIN/lk-jwt/healthz" "MatrixRTC Authorization Service"
        fi
        log_ok "MAS уже установлен; конфигурация проверена без смены ключей шифрования"
        return
    fi

    if [[ -n "${MAS_DOMAIN:-}" && -n "${MAS_SECRET:-}" \
          && -f "$MATRIX_DIR/data/mas/config.yaml" ]]; then
        log_warn "Найдена незавершённая установка MAS; продолжаю с сохранёнными ключами"
        check_domain_points_here "$MAS_DOMAIN"
    else
        # Запрос домена для MAS
        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            [[ -n "${MAS_DOMAIN:-}" ]] || log_error "Для --install-mas требуется MAS_DOMAIN в config"
            is_valid_domain "$MAS_DOMAIN" || log_error "Некорректный MAS_DOMAIN"
        else
            echo ""
            MAS_DOMAIN=$(read_domain "Домен MAS" "mas.$SERVER_NAME")
        fi
        check_domain_points_here "$MAS_DOMAIN"
        log_ok "Домен MAS: ${CYAN}$MAS_DOMAIN${NC}"

    # Генерация секрета для связи с Synapse
    MAS_SECRET=$(generate_secret 32)
    MAS_DB_PASSWORD=$(generate_secret 32)
    log_ok "Секрет для MAS сгенерирован"

    # Генерация ключей для MAS (encryption и подписи)
    ENCRYPTION_SECRET=$(openssl rand -hex 32)
    RSA_KEY=$(openssl genrsa 2048 2>/dev/null)
    EC_KEY1=$(openssl ecparam -name prime256v1 -genkey -noout 2>/dev/null)
    EC_KEY2=$(openssl ecparam -name prime256v1 -genkey -noout 2>/dev/null)
    EC_KEY3=$(openssl ecparam -name prime256v1 -genkey -noout 2>/dev/null)

    # Сохраняем в .env
    save_env

    # Создаём каталог для конфига MAS
    mkdir -p "$MATRIX_DIR/data/mas"
    cat > "$MATRIX_DIR/data/mas/config.yaml" <<EOF
http:
  listeners:
  - name: web
    resources:
    - name: discovery
    - name: human
    - name: oauth
    - name: compat
    - name: graphql
    - name: assets
    - name: adminapi
    binds:
    - address: '[::]:8080'
    proxy_protocol: false
  - name: internal
    resources:
    - name: health
    binds:
    - host: localhost
      port: 8081
    proxy_protocol: false
  trusted_proxies:
  - 192.168.0.0/16
  - 172.16.0.0/12
  - 10.0.0.0/10
  - 127.0.0.1/8
  - fd00::/8
  - ::1/128
  public_base: https://$MAS_DOMAIN/
  issuer: https://$MAS_DOMAIN/
database:
  uri: postgresql://mas_user:${MAS_DB_PASSWORD:-$DB_PASSWORD}@mas-db:5432/mas
  max_connections: 10
  min_connections: 0
  connect_timeout: 30
  idle_timeout: 600
  max_lifetime: 1800
email:
  from: '"Authentication Service" <root@localhost>'
  reply_to: '"Authentication Service" <root@localhost>'
  transport: blackhole
secrets:
  encryption: $ENCRYPTION_SECRET
  keys:
  - key: |
$(echo "$RSA_KEY" | sed 's/^/      /')
  - key: |
$(echo "$EC_KEY1" | sed 's/^/      /')
  - key: |
$(echo "$EC_KEY2" | sed 's/^/      /')
  - key: |
$(echo "$EC_KEY3" | sed 's/^/      /')
passwords:
  enabled: true
  schemes:
  - version: 1
    algorithm: bcrypt
    unicode_normalization: true
  - version: 2
    algorithm: argon2id
  minimum_complexity: 3
matrix:
  kind: synapse
  homeserver: $SERVER_NAME
  secret: $MAS_SECRET
  endpoint: http://synapse:8008/
account:
  password_registration_enabled: $MAS_REGISTRATION_ENABLED
  password_registration_email_required: false
  password_registration_token_required: $MAS_REGISTRATION_TOKEN_REQUIRED
  password_change_allowed: true
  password_recovery_enabled: false
EOF
        log_ok "Конфиг MAS создан"
        # MAS runs as an unprivileged container user and reads this bind mount.
        chmod 0644 "$MATRIX_DIR/data/mas/config.yaml"
        chmod 0755 "$MATRIX_DIR/data/mas"
        # The bind-mounted file must be traversable by the container runtime.
        chmod 0755 "$MATRIX_DIR" "$MATRIX_DIR/data"
    fi

    # Получение SSL для MAS
    ensure_ssl_cert "$MAS_DOMAIN"

    # Настройка Nginx для MAS
    set_nginx_http2_syntax
    NGINX_MAS_CONF="/etc/nginx/sites-available/mas-${MAS_DOMAIN}.conf"
    cat > "$NGINX_MAS_CONF" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $MAS_DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl${NGINX_HTTP2_LISTEN};
    listen [::]:443 ssl${NGINX_HTTP2_LISTEN};
$NGINX_HTTP2_DIRECTIVE
    server_name $MAS_DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
    }

    ssl_certificate /etc/letsencrypt/live/$MAS_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$MAS_DOMAIN/privkey.pem;
}
EOF

    ln -sf "$NGINX_MAS_CONF" /etc/nginx/sites-enabled/

    # Legacy Matrix clients send login/logout/refresh to the homeserver domain.
    # With delegated authentication these compatibility endpoints belong to MAS.
    MAS_COMPAT_SNIPPET="/etc/nginx/snippets/matrix-${DOMAIN}-mas.conf"
    cat > "$MAS_COMPAT_SNIPPET" <<EOF
location ~ ^/_matrix/client/(?:r0|v1|v3|unstable)/(?:login|logout(?:/all)?|refresh)$ {
    proxy_pass http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_buffering off;
}
EOF

    nginx -t >/dev/null 2>&1 || log_error "Ошибка конфигурации Nginx для MAS"
    systemctl reload nginx
    log_ok "Nginx для MAS настроен"

    # Подготавливаем контейнеры и переносим существующие аккаунты/сессии в MAS.
    # Запускать пустой MAS рядом с уже работающим Synapse без syn2mas нельзя:
    # после включения делегированной авторизации старые пользователи потеряют вход.
    cd "$MATRIX_DIR"
    detect_components
    generate_compose true false "$HAS_KETESA" "$HAS_ELEMENT_ADMIN" "$HAS_NTFY"

    # syn2mas runs in a separate container user and must be able to read the
    # Synapse configuration mounted read-only from the host.  Synapse itself
    # does not require the file to be private (the database credentials are
    # kept in .env), so make the mounted copy world-readable for the migration
    # and MAS container while retaining the private directory permissions.
    chmod 0644 "$HOMESERVER_FILE"

    run_spinner "Запуск баз данных Synapse и MAS" \
        docker compose up -d postgres mas-db
    run_spinner "Загрузка образа MAS" \
        docker compose pull mas

    for _ in {1..60}; do
        if docker compose exec -T mas-db pg_isready -U mas_user -d mas >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done
    docker compose exec -T mas-db pg_isready -U mas_user -d mas >/dev/null 2>&1 \
        || log_error "База данных MAS не готова"

    if [[ ! -f "$MIGRATION_MARKER" ]]; then
        BACKUP_DIR="$MATRIX_DIR/data/backups/mas-migration-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        cp "$HOMESERVER_FILE" "$BACKUP_DIR/homeserver.yaml"
        docker compose exec -T postgres pg_dump -U synapse synapse \
            > "$BACKUP_DIR/synapse.sql" \
            || log_error "Не удалось создать резервную копию Synapse"
        chmod -R 700 "$BACKUP_DIR"
        log_ok "Резервная копия Synapse создана"

        set +e
        docker compose run --rm --no-deps mas \
            --config /app/config/config.yaml syn2mas check \
            --synapse-config /data/synapse/homeserver.yaml \
            --synapse-database-uri "postgresql://synapse:${DB_PASSWORD:-}@postgres:5432/synapse" \
            >"$RUNTIME_DIR/syn2mas-check.log" 2>&1
        SYN2MAS_CHECK_STATUS=$?
        set -e
        if [[ $SYN2MAS_CHECK_STATUS -ne 0 && $SYN2MAS_CHECK_STATUS -ne 11 ]]; then
            tail -50 "$RUNTIME_DIR/syn2mas-check.log"
            log_error "Проверка syn2mas завершилась ошибкой"
        fi
        if [[ $SYN2MAS_CHECK_STATUS -eq 11 ]]; then
            log_warn "syn2mas сообщил предупреждения; регистрация Synapse будет отключена перед миграцией"
        else
            log_ok "Проверка syn2mas пройдена"
        fi

        docker compose stop synapse >/dev/null 2>&1 || true
        generate_homeserver true false
        # generate_homeserver restores the Synapse-only 0640 mode.  syn2mas
        # uses a different unprivileged UID, so make the bind-mounted file
        # readable again immediately before the migration container starts.
        chmod 0644 "$HOMESERVER_FILE"

        set +e
        docker compose run --rm --no-deps mas \
            --config /app/config/config.yaml syn2mas migrate \
            --synapse-config /data/synapse/homeserver.yaml \
            --synapse-database-uri "postgresql://synapse:${DB_PASSWORD:-}@postgres:5432/synapse" \
            >"$RUNTIME_DIR/syn2mas-migrate.log" 2>&1
        SYN2MAS_MIGRATE_STATUS=$?
        set -e
        if [[ $SYN2MAS_MIGRATE_STATUS -ne 0 && $SYN2MAS_MIGRATE_STATUS -ne 11 ]]; then
            tail -50 "$RUNTIME_DIR/syn2mas-migrate.log"
            cp "$BACKUP_DIR/homeserver.yaml" "$HOMESERVER_FILE"
            chown 991:991 "$HOMESERVER_FILE"
            chmod 0640 "$HOMESERVER_FILE"
            docker compose up -d postgres synapse coturn >/dev/null 2>&1 || true
            log_error "Миграция syn2mas завершилась ошибкой; конфигурация Synapse восстановлена"
        fi
        touch "$MIGRATION_MARKER"
        chmod 600 "$MIGRATION_MARKER"
        log_ok "Аккаунты и сессии перенесены в MAS"
    else
        generate_homeserver true false
        log_ok "Миграция syn2mas уже была выполнена"
    fi

    # Перезапуск сервисов
    log_step "Перезапуск сервисов с MAS"
    run_spinner "Запуск обновлённого стека" \
        docker compose up -d
    run_spinner "Перезапуск Synapse с конфигурацией MAS" \
        docker compose restart synapse
    wait_for_url "https://$MAS_DOMAIN/.well-known/openid-configuration" "MAS OIDC discovery"
    wait_for_url "https://$DOMAIN/_matrix/client/versions" "Matrix API после включения MAS"

    # Дописываем данные в credentials.txt
    CREDS_FILE="$MATRIX_DIR/credentials.txt"
    if [[ -f "$CREDS_FILE" ]]; then
        cat >> "$CREDS_FILE" <<CREDS

MAS (Matrix Authentication Service)
====================================
MAS Domain:  https://$MAS_DOMAIN
MAS Secret:  $MAS_SECRET
CREDS
    else
        cat > "$CREDS_FILE" <<CREDS
Matrix Server — Credentials (дополнено MAS)
===========================================
Date:        $(date)
MAS Domain:  https://$MAS_DOMAIN
MAS Secret:  $MAS_SECRET
CREDS
    fi
    chmod 600 "$CREDS_FILE"

    # Финальный вывод
    echo ""
    echo ""
    echo -e "${BGREEN}  ╔══════════════════════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BGREEN}  ║                                                                                                  ║${NC}"
    echo -e "${BGREEN}  ║                              УСТАНОВКА MAS ЗАВЕРШЕНА!                                           ║${NC}"
    echo -e "${BGREEN}  ║                                                                                                  ║${NC}"
    echo -e "${BGREEN}  ╠══════════════════════════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BGREEN}  ║                                                                                                  ║${NC}"
    echo -e "${BGREEN}  ║${NC}  ${WHITE}MAS URL:${NC}       ${CYAN}https://$MAS_DOMAIN${NC}                                ║${NC}"
    echo -e "${BGREEN}  ║${NC}  ${WHITE}Интеграция:${NC}    ${GREEN}активна (с Synapse)${NC}                              ║${NC}"
    echo -e "${BGREEN}  ║                                                                                                  ║${NC}"
    echo -e "${BGREEN}  ║${NC}  ${YELLOW}Секрет MAS:${NC}   ${WHITE}$MAS_SECRET                                           ║${NC}"
    echo -e "${BGREEN}  ║                                                                                                  ║${NC}"
    echo -e "${BGREEN}  ╠══════════════════════════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BGREEN}  ║                                                                                                  ║${NC}"
    echo -e "${BGREEN}  ║${NC}  ${DIM}Логи:${NC}     ${CYAN}docker compose logs -f mas                                     ║${NC}"
    echo -e "${BGREEN}  ║${NC}  ${DIM}Статус:${NC}   ${CYAN}docker compose ps                                             ║${NC}"
    echo -e "${BGREEN}  ║${NC}                                                                                             ║${NC}"
    echo -e "${BGREEN}  ║${NC}  ${DIM}Учётные данные дополнены в:                                                          ║${NC}"
    echo -e "${BGREEN}  ║${NC}  ${CYAN}$CREDS_FILE                                                                         ║${NC}"
    echo -e "${BGREEN}  ║                                                                                                  ║${NC}"
    echo -e "${BGREEN}  ╚══════════════════════════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "               ${PURPLE}◆${NC}  ${DIM}made by${NC}  ${BPURPLE}zxchubbabubba${NC}  ${PURPLE}◆${NC}"
    echo ""
}

# ════════════════════════════════════════
#  УСТАНОВКА LIVEKIT (пункт 3)
# ════════════════════════════════════════
install_livekit() {
    log_step "Установка LiveKit (звонки)"

    # Проверяем наличие Matrix и MAS
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error "Файл .env не найден. Сначала установите Matrix (пункт 1)."
    fi

    load_env

    # Проверяем, что MAS установлен (по наличию переменной MAS_DOMAIN)
    if [[ -z "$MAS_DOMAIN" ]]; then
        log_error "MAS не установлен. Сначала установите MAS (пункт 2)."
    fi

    if [[ -n "${LIVEKIT_DOMAIN:-}" && -n "${LIVEKIT_KEY:-}" \
          && -n "${LIVEKIT_SECRET:-}" \
          && -f "$MATRIX_DIR/data/livekit/livekit.yaml" ]]; then
        log_ok "LiveKit уже установлен; существующие API-ключи будут сохранены"
    else
        # Запрос домена для LiveKit
        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            [[ -n "${LIVEKIT_DOMAIN:-}" ]] || log_error "Для --install-livekit требуется LIVEKIT_DOMAIN в config"
            is_valid_domain "$LIVEKIT_DOMAIN" || log_error "Некорректный LIVEKIT_DOMAIN"
        else
            echo ""
            LIVEKIT_DOMAIN=$(read_domain "Домен LiveKit" "livekit.$SERVER_NAME")
        fi
        RESOLVED_IP=$(getent ahostsv4 "$LIVEKIT_DOMAIN" 2>/dev/null | awk 'NR==1 {print $1}')
        [[ "$RESOLVED_IP" == "$EXTERNAL_IP" ]] \
            || log_error "DNS $LIVEKIT_DOMAIN указывает на '${RESOLVED_IP:-ничего}', ожидался $EXTERNAL_IP"
        log_ok "Домен LiveKit: ${CYAN}$LIVEKIT_DOMAIN${NC}"

        # Генерация ключей LiveKit
        LIVEKIT_KEY=$(generate_secret 64)
        LIVEKIT_SECRET=$(generate_secret 64)
        log_ok "Ключи LiveKit сгенерированы"

        # Сохраняем в .env
        save_env
    fi

    # Создаём каталог для конфига LiveKit
    mkdir -p "$MATRIX_DIR/data/livekit"
    cat > "$MATRIX_DIR/data/livekit/livekit.yaml" <<EOF
port: 7880
rtc:
  tcp_port: 7881
  # Single-port UDP mux avoids lossy random high-port routing and simplifies ICE.
  # 7882 is LiveKit's standard UDP mux port and works better than UDP/443 on some carriers.
  udp_port: 7882
  use_external_ip: false
  node_ip: $EXTERNAL_IP
keys:
  $LIVEKIT_KEY: $LIVEKIT_SECRET
room:
  auto_create: false
logging:
  level: info
EOF
    log_ok "Конфиг LiveKit создан"

    # Получение SSL для LiveKit
    ensure_ssl_cert "$LIVEKIT_DOMAIN"

    # Настройка Nginx для LiveKit
    set_nginx_http2_syntax
    NGINX_LIVEKIT_CONF="/etc/nginx/sites-available/livekit-${LIVEKIT_DOMAIN}.conf"
    cat > "$NGINX_LIVEKIT_CONF" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $LIVEKIT_DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl${NGINX_HTTP2_LISTEN};
    listen [::]:443 ssl${NGINX_HTTP2_LISTEN};
$NGINX_HTTP2_DIRECTIVE
    server_name $LIVEKIT_DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:7880;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
        proxy_read_timeout 86400s;
    }

    ssl_certificate /etc/letsencrypt/live/$LIVEKIT_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$LIVEKIT_DOMAIN/privkey.pem;
}
EOF

    ln -sf "$NGINX_LIVEKIT_CONF" /etc/nginx/sites-enabled/
    nginx -t >/dev/null 2>&1 || log_error "Ошибка конфигурации Nginx для LiveKit"
    systemctl reload nginx
    log_ok "Nginx для LiveKit настроен"

    # Открываем порты для LiveKit
    log_step "Открытие портов для LiveKit"
    cat > /etc/sysctl.d/99-matrix-livekit.conf <<'EOF'
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.netdev_max_backlog=5000
EOF
    sysctl --system >/dev/null
    for old_rule in "8008/tcp" "8448/tcp" "7880/tcp"; do
        ufw --force delete allow "$old_rule" >/dev/null 2>&1 || true
    done
    for old_rule in "443/udp" "50000:50100/udp"; do
        ufw --force delete allow "$old_rule" >/dev/null 2>&1 || true
    done
    for rule in "7881/tcp" "7882/udp"; do
        ufw allow "$rule" >/dev/null 2>&1
    done
    log_ok "Открыты медиапорты 7881/tcp и 7882/udp; UDP-буферы увеличены"

    # Перегенерируем compose и homeserver с включенным LiveKit
    cd "$MATRIX_DIR"
    detect_components
    generate_compose true true "$HAS_KETESA" "$HAS_ELEMENT_ADMIN" "$HAS_NTFY"
    generate_homeserver true true
    configure_well_known true true   # исправлено

    # Добавляем /lk-jwt через отдельный файл-включение
    SNIPPET_FILE="/etc/nginx/snippets/matrix-${DOMAIN}-livekit.conf"
    cat > "$SNIPPET_FILE" <<EOF
location = /lk-jwt {
    return 308 /lk-jwt/;
}

location ^~ /lk-jwt/ {
    # Завершающий / снимает публичный префикс /lk-jwt. JWT-сервис
    # принимает /sfu/get, /get_token, /sfu_webhook и /healthz.
    proxy_pass http://127.0.0.1:8082/;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_buffering off;
}
EOF

    MAIN_NGINX="/etc/nginx/sites-available/matrix-${DOMAIN}.conf"
    INCLUDE_GLOB="/etc/nginx/snippets/matrix-${DOMAIN}-*.conf"
    if ! grep -Fq "include $INCLUDE_GLOB;" "$MAIN_NGINX"; then
        sed -i "/add_header X-Frame-Options/i\    include $INCLUDE_GLOB;\n" "$MAIN_NGINX"
    fi
    rm -f "/etc/nginx/snippets/lk-jwt-${DOMAIN}.conf"
    nginx -t >/dev/null 2>&1 || log_error "Ошибка добавления /lk-jwt в Nginx"
    systemctl reload nginx
    log_ok "Добавлен прокси /lk-jwt с корректным снятием префикса"

    # Перезапуск сервисов
    log_step "Перезапуск сервисов с LiveKit"
    run_spinner "Запуск обновлённого стека" \
        docker compose up -d
    run_spinner "Применение конфигурации LiveKit" \
        docker compose restart livekit lk-jwt-service
    run_spinner "Перезапуск Synapse с конфигурацией MatrixRTC" \
        docker compose restart synapse
    wait_for_url "https://$DOMAIN/lk-jwt/healthz" "MatrixRTC Authorization Service"
    wait_for_url "https://$DOMAIN/.well-known/matrix/server" "Matrix federation discovery"
    wait_for_http_status \
        "https://$DOMAIN/_matrix/client/unstable/org.matrix.msc4143/rtc/transports" \
        "401" "MatrixRTC transport discovery"

    # Обновляем секцию LiveKit в credentials.txt, не оставляя устаревшие ключи
    CREDS_FILE="$MATRIX_DIR/credentials.txt"
    if [[ -f "$CREDS_FILE" ]]; then
        sed -i \
            -e '/^LiveKit (звонки)$/,/^API Secret:/d' \
            -e '/^Matrix Server — Credentials (дополнено LiveKit)$/,/^API Secret:/d' \
            "$CREDS_FILE"
        cat >> "$CREDS_FILE" <<CREDS

LiveKit (звонки)
=================
LiveKit Domain:  wss://$LIVEKIT_DOMAIN
API Key:         $LIVEKIT_KEY
API Secret:      $LIVEKIT_SECRET
CREDS
    else
        cat > "$CREDS_FILE" <<CREDS
Matrix Server — Credentials (дополнено LiveKit)
===============================================
Date:           $(date)
LiveKit Domain: wss://$LIVEKIT_DOMAIN
API Key:        $LIVEKIT_KEY
API Secret:     $LIVEKIT_SECRET
CREDS
    fi
    chmod 600 "$CREDS_FILE"

    # Финальный вывод
    echo ""
    echo ""
    echo -e "${BGREEN}  ╔══════════════════════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BGREEN}  ║                                                                                                  ║${NC}"
    echo -e "${BGREEN}  ║                             УСТАНОВКА LIVEKIT ЗАВЕРШЕНА!                                        ║${NC}"
    echo -e "${BGREEN}  ║                                                                                                  ║${NC}"
    echo -e "${BGREEN}  ╠══════════════════════════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BGREEN}  ║                                                                                                  ║${NC}"
    echo -e "${BGREEN}  ║${NC}  ${WHITE}LiveKit URL:${NC}   ${CYAN}wss://$LIVEKIT_DOMAIN${NC}                             ║${NC}"
    echo -e "${BGREEN}  ║${NC}  ${WHITE}Интеграция:${NC}    ${GREEN}активна (через /lk-jwt)${NC}                         ║${NC}"
    echo -e "${BGREEN}  ║                                                                                                  ║${NC}"
    echo -e "${BGREEN}  ║${NC}  ${YELLOW}API Key:${NC}      ${WHITE}$LIVEKIT_KEY                                           ║${NC}"
    echo -e "${BGREEN}  ║${NC}  ${YELLOW}API Secret:${NC}   ${WHITE}$LIVEKIT_SECRET                                        ║${NC}"
    echo -e "${BGREEN}  ║                                                                                                  ║${NC}"
    echo -e "${BGREEN}  ╠══════════════════════════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BGREEN}  ║                                                                                                  ║${NC}"
    echo -e "${BGREEN}  ║${NC}  ${DIM}Логи:${NC}     ${CYAN}docker compose logs -f livekit lk-jwt-service                  ║${NC}"
    echo -e "${BGREEN}  ║${NC}  ${DIM}Статус:${NC}   ${CYAN}docker compose ps                                             ║${NC}"
    echo -e "${BGREEN}  ║${NC}                                                                                             ║${NC}"
    echo -e "${BGREEN}  ║${NC}  ${DIM}Учётные данные дополнены в:                                                          ║${NC}"
    echo -e "${BGREEN}  ║${NC}  ${CYAN}$CREDS_FILE                                                                         ║${NC}"
    echo -e "${BGREEN}  ║                                                                                                  ║${NC}"
    echo -e "${BGREEN}  ╚══════════════════════════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "               ${PURPLE}◆${NC}  ${DIM}made by${NC}  ${BPURPLE}zxchubbabubba${NC}  ${PURPLE}◆${NC}"
    echo ""
}

# ════════════════════════════════════════
#  УПРАВЛЕНИЕ И ДОПОЛНИТЕЛЬНЫЕ КОМПОНЕНТЫ
# ════════════════════════════════════════
require_matrix() {
    [[ -f "$ENV_FILE" && -f "$HOMESERVER_FILE" ]] \
        || log_error "Сначала установите Matrix (пункт 1)."
    load_env
    detect_components
}

check_domain_points_here() {
    local domain="$1"
    local resolved
    resolved=$(getent ahostsv4 "$domain" 2>/dev/null | awk 'NR==1 {print $1}')
    [[ "$resolved" == "$EXTERNAL_IP" ]] \
        || log_error "DNS $domain указывает на '${resolved:-ничего}', ожидался $EXTERNAL_IP"
    log_ok "DNS $domain указывает на $EXTERNAL_IP"
}

regenerate_stack() {
    detect_components
    generate_compose "$HAS_MAS" "$HAS_LIVEKIT" "$HAS_KETESA" "$HAS_ELEMENT_ADMIN" "$HAS_NTFY"
    generate_homeserver "$HAS_MAS" "$HAS_LIVEKIT"
    configure_well_known "$HAS_LIVEKIT" "$HAS_MAS"   # исправлено
}

apply_synapse_config() {
    local backup_file
    backup_file=$(mktemp "$MATRIX_DIR/data/synapse/homeserver.yaml.rollback.XXXXXX")
    cp "$HOMESERVER_FILE" "$backup_file"
    regenerate_stack

    if ! docker compose -f "$COMPOSE_FILE" config --quiet >"$RUNTIME_DIR/matrix-compose-check.log" 2>&1; then
        cp "$backup_file" "$HOMESERVER_FILE"
        rm -f "$backup_file"
        tail -30 "$RUNTIME_DIR/matrix-compose-check.log"
        log_error "Новый docker-compose.yml некорректен; homeserver.yaml восстановлен"
    fi

    if ! docker compose -f "$COMPOSE_FILE" up -d synapse >"$RUNTIME_DIR/matrix-synapse-apply.log" 2>&1; then
        cp "$backup_file" "$HOMESERVER_FILE"
        docker compose -f "$COMPOSE_FILE" restart synapse >/dev/null 2>&1 || true
        rm -f "$backup_file"
        tail -30 "$RUNTIME_DIR/matrix-synapse-apply.log"
        log_error "Synapse не принял конфигурацию; выполнен откат"
    fi

    local elapsed=0
    until curl --fail --silent --max-time 5 \
        http://127.0.0.1:8008/_matrix/client/versions >/dev/null 2>&1; do
        sleep 2
        elapsed=$((elapsed + 2))
        if [[ $elapsed -ge 90 ]]; then
            cp "$backup_file" "$HOMESERVER_FILE"
            docker compose -f "$COMPOSE_FILE" restart synapse >/dev/null 2>&1 || true
            rm -f "$backup_file"
            log_error "Synapse не запустился за 90 секунд; выполнен откат"
        fi
    done
    rm -f "$backup_file"
    log_ok "Конфигурация Synapse применена"
}

show_federation_status() {
    require_matrix
    echo ""
    echo -e "  Режим исходящей федерации: ${CYAN}$FEDERATION_MODE${NC}"
    if [[ "$FEDERATION_MODE" == "public" ]]; then
        echo "  Разрешены все федеративные серверы."
    elif [[ -s "$FEDERATION_FILE" ]]; then
        echo "  Разрешённые серверы:"
        sed 's/^/    - /' "$FEDERATION_FILE"
    else
        echo "  Allowlist пуст: исходящая федерация полностью заблокирована."
    fi
}

add_federation_domain() {
    require_matrix
    local input federation_domain
    echo ""
    echo "  Можно ввести домен (matrix.org) или Matrix ID (@user:matrix.org)."
    echo -ne "  ${CYAN}▶${NC}  Федеративный домен: "
    read -r input
    federation_domain=$(normalize_domain "$input")
    is_valid_domain "$federation_domain" \
        || log_error "Некорректный федеративный домен: $federation_domain"
    [[ "$federation_domain" != "$SERVER_NAME" ]] \
        || log_error "Локальный server_name нельзя добавлять в allowlist"

    mkdir -p "$(dirname "$FEDERATION_FILE")"
    touch "$FEDERATION_FILE"
    if grep -Fqx "$federation_domain" "$FEDERATION_FILE"; then
        log_warn "$federation_domain уже есть в allowlist"
        return
    fi
    printf '%s\n' "$federation_domain" >> "$FEDERATION_FILE"
    sort -u -o "$FEDERATION_FILE" "$FEDERATION_FILE"
    chmod 600 "$FEDERATION_FILE"
    FEDERATION_MODE="restricted"
    save_env
    cd "$MATRIX_DIR"
    apply_synapse_config
    log_ok "Добавлена федерация $federation_domain; включён ограниченный allowlist"
}

remove_federation_domain() {
    require_matrix
    [[ -s "$FEDERATION_FILE" ]] || log_error "Список федераций пуст"
    show_federation_status
    local input federation_domain tmp_file
    echo -ne "  ${CYAN}▶${NC}  Домен для удаления: "
    read -r input
    federation_domain=$(normalize_domain "$input")
    grep -Fqx "$federation_domain" "$FEDERATION_FILE" \
        || log_error "$federation_domain отсутствует в allowlist"
    tmp_file=$(mktemp "$MATRIX_DIR/.federation.XXXXXX")
    grep -Fvx "$federation_domain" "$FEDERATION_FILE" > "$tmp_file" || true
    mv -f "$tmp_file" "$FEDERATION_FILE"
    chmod 600 "$FEDERATION_FILE"
    cd "$MATRIX_DIR"
    apply_synapse_config
    log_ok "$federation_domain удалён"
}

set_public_federation() {
    require_matrix
    FEDERATION_MODE="public"
    save_env
    cd "$MATRIX_DIR"
    apply_synapse_config
    log_ok "Публичная федерация включена: разрешены все серверы"
}

manage_federation() {
    require_matrix
    echo ""
    echo "  1) Показать текущий режим и allowlist"
    echo "  2) Добавить домен и включить ограниченный allowlist"
    echo "  3) Удалить домен из allowlist"
    echo "  4) Разрешить публичную федерацию со всеми серверами"
    echo -ne "  ${CYAN}▶${NC}  Выбор: "
    local federation_choice
    read -r federation_choice
    case "$federation_choice" in
        1) show_federation_status ;;
        2) add_federation_domain ;;
        3) remove_federation_domain ;;
        4) set_public_federation ;;
        *) log_error "Неверный выбор" ;;
    esac
}

write_proxy_vhost() {
    local label="$1" domain="$2" port="$3" websocket="${4:-false}"
    local conf="/etc/nginx/sites-available/${label}-${domain}.conf"
    local websocket_headers=""
    set_nginx_http2_syntax
    if [[ "$websocket" == "true" ]]; then
        websocket_headers='        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";'
    fi
    cat > "$conf" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl${NGINX_HTTP2_LISTEN};
    listen [::]:443 ssl${NGINX_HTTP2_LISTEN};
$NGINX_HTTP2_DIRECTIVE
    server_name $domain;
    client_max_body_size $MAX_UPLOAD_SIZE;

    location / {
        proxy_pass http://127.0.0.1:$port;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
$websocket_headers
        proxy_buffering off;
    }

    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
}
EOF
    ln -sf "$conf" "/etc/nginx/sites-enabled/${label}-${domain}.conf"
    nginx -t >/dev/null 2>&1 || log_error "Некорректный Nginx-конфиг для $domain"
    systemctl reload nginx
}

ensure_mas_admin_api() {
    local mas_config="$MATRIX_DIR/data/mas/config.yaml"
    [[ -f "$mas_config" ]] || log_error "Element Admin требует установленный MAS"
    if ! grep -Eq '^[[:space:]]*-[[:space:]]+name:[[:space:]]+adminapi[[:space:]]*$' "$mas_config"; then
        cp "$mas_config" "${mas_config}.before-adminapi.$(date +%Y%m%d-%H%M%S)"
        sed -i '/^[[:space:]]*- name: assets[[:space:]]*$/a\    - name: adminapi' "$mas_config"
        log_ok "В MAS включён adminapi"
    fi
}

install_ketesa() {
    log_step "Установка Ketesa Admin"
    require_matrix
    if [[ -n "${KETESA_DOMAIN:-}" ]]; then
        log_warn "Ketesa уже настроена; проверяю и восстанавливаю сервис"
    else
        KETESA_DOMAIN=$(read_domain "Домен Ketesa Admin" "admin.$SERVER_NAME")
    fi
    check_domain_points_here "$KETESA_DOMAIN"
    ensure_ssl_cert "$KETESA_DOMAIN"
    mkdir -p "$MATRIX_DIR/data/ketesa"
    cat > "$MATRIX_DIR/data/ketesa/config.json" <<EOF
{
  "restrictBaseUrl": "https://$DOMAIN"
}
EOF
    chmod 644 "$MATRIX_DIR/data/ketesa/config.json"
    save_env
    cd "$MATRIX_DIR"
    regenerate_stack
    docker compose config --quiet || log_error "Ошибка docker-compose после добавления Ketesa"
    write_proxy_vhost "ketesa" "$KETESA_DOMAIN" 8083 false
    run_spinner "Запуск Ketesa Admin" docker compose up -d ketesa
    wait_for_url "https://$KETESA_DOMAIN/" "Ketesa Admin"
    log_ok "Ketesa доступна: https://$KETESA_DOMAIN"
}

install_element_admin() {
    log_step "Установка Element Admin"
    require_matrix
    [[ "$HAS_MAS" == "true" ]] \
        || log_error "Element Admin требует установленный MAS (пункт 2)"
    if [[ -n "${ELEMENT_ADMIN_DOMAIN:-}" ]]; then
        log_warn "Element Admin уже настроен; проверяю и восстанавливаю сервис"
    else
        ELEMENT_ADMIN_DOMAIN=$(read_domain "Домен Element Admin" "element-admin.$SERVER_NAME")
    fi
    check_domain_points_here "$ELEMENT_ADMIN_DOMAIN"
    ensure_ssl_cert "$ELEMENT_ADMIN_DOMAIN"
    ensure_mas_admin_api
    save_env
    cd "$MATRIX_DIR"
    # The installation marker is deliberately written only after the service
    # answers.  Therefore component auto-detection cannot see Element Admin on
    # its first run; render this one component explicitly for the initial
    # compose-up while preserving every already installed optional service.
    generate_compose "$HAS_MAS" "$HAS_LIVEKIT" "$HAS_KETESA" true "$HAS_NTFY"
    generate_homeserver "$HAS_MAS" "$HAS_LIVEKIT"
    configure_well_known "$HAS_LIVEKIT" "$HAS_MAS"
    docker compose config --quiet || log_error "Ошибка docker-compose после добавления Element Admin"
    write_proxy_vhost "element-admin" "$ELEMENT_ADMIN_DOMAIN" 8084 false
    run_spinner "Запуск Element Admin и MAS" docker compose up -d mas element-admin
    wait_for_url "https://$ELEMENT_ADMIN_DOMAIN/" "Element Admin"
    mkdir -p "$MATRIX_DIR/data/element-admin"
    touch "$MATRIX_DIR/data/element-admin/.installed"
    chmod 600 "$MATRIX_DIR/data/element-admin/.installed"
    log_ok "Element Admin доступен: https://$ELEMENT_ADMIN_DOMAIN"
}

install_ntfy() {
    log_step "Установка ntfy (UnifiedPush)"
    require_matrix
    local ntfy_new="false"
    local ntfy_password=""
    local ntfy_user_list=""
    if [[ -n "${NTFY_DOMAIN:-}" && -f "$MATRIX_DIR/data/ntfy/server.yml" ]]; then
        log_warn "ntfy уже настроен; проверяю и восстанавливаю сервис"
    else
        ntfy_new="true"
        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            [[ -n "${NTFY_DOMAIN:-}" ]] || log_error "Для ntfy требуется NTFY_DOMAIN в config"
            is_valid_domain "$NTFY_DOMAIN" || log_error "Некорректный NTFY_DOMAIN"
        else
            NTFY_DOMAIN=$(read_domain "Домен ntfy" "ntfy.$SERVER_NAME")
            echo -ne "  ${CYAN}▶${NC}  Имя администратора ntfy [admin]: "
            read -r NTFY_ADMIN_USER
        fi
        NTFY_ADMIN_USER="${NTFY_ADMIN_USER:-admin}"
        [[ "$NTFY_ADMIN_USER" =~ ^[A-Za-z0-9._-]{1,64}$ ]] \
            || log_error "Некорректное имя пользователя ntfy"
        ntfy_password=$(generate_secret 24)
    fi
    check_domain_points_here "$NTFY_DOMAIN"
    ensure_ssl_cert "$NTFY_DOMAIN"
    mkdir -p "$MATRIX_DIR/data/ntfy/cache" "$MATRIX_DIR/data/ntfy/data"
    cat > "$MATRIX_DIR/data/ntfy/server.yml" <<EOF
base-url: "https://$NTFY_DOMAIN"
listen-http: ":80"
behind-proxy: true
cache-file: "/var/cache/ntfy/cache.db"
attachment-cache-dir: "/var/cache/ntfy/attachments"
auth-file: "/var/lib/ntfy/user.db"
auth-default-access: "deny-all"
enable-login: true
EOF
    chmod 600 "$MATRIX_DIR/data/ntfy/server.yml"
    save_env
    cd "$MATRIX_DIR"
    regenerate_stack
    docker compose config --quiet || log_error "Ошибка docker-compose после добавления ntfy"
    write_proxy_vhost "ntfy" "$NTFY_DOMAIN" 8090 true
    run_spinner "Запуск ntfy" docker compose up -d ntfy
    if [[ "$ntfy_new" == "false" ]]; then
        ntfy_user_list=$(docker compose exec -T ntfy ntfy user list 2>/dev/null || true)
        if ! grep -Fq "$NTFY_ADMIN_USER" <<< "$ntfy_user_list"; then
            log_warn "Сохранённый пользователь ntfy не найден; будет создан новый пароль"
            ntfy_password=$(generate_secret 24)
            ntfy_new="true"
        fi
    fi
    if [[ "$ntfy_new" == "true" ]]; then
        if ! docker compose exec -T -e "NTFY_PASSWORD=$ntfy_password" ntfy \
            ntfy user add --role=admin "$NTFY_ADMIN_USER" >"$RUNTIME_DIR/ntfy-user.log" 2>&1; then
            tail -20 "$RUNTIME_DIR/ntfy-user.log"
            log_error "Не удалось создать администратора ntfy"
        fi
    fi
    wait_for_url "https://$NTFY_DOMAIN/v1/health" "ntfy"
    if [[ "$ntfy_new" == "true" ]]; then
        {
            echo ""
            echo "ntfy (UnifiedPush)"
            echo "=================="
            echo "URL:      https://$NTFY_DOMAIN"
            echo "User:     $NTFY_ADMIN_USER"
            echo "Password: $ntfy_password"
        } >> "$MATRIX_DIR/credentials.txt"
        chmod 600 "$MATRIX_DIR/credentials.txt"
    fi
    log_ok "ntfy доступен: https://$NTFY_DOMAIN"
}

dump_postgres_database() {
    local service="$1" user="$2" database="$3" output="$4"
    docker compose exec -T "$service" pg_dump -U "$user" -d "$database" -Fc > "$output"
}

restore_postgres_database() {
    local service="$1" user="$2" database="$3" input="$4"
    docker compose exec -T "$service" pg_restore -U "$user" -d "$database" \
        --clean --if-exists --no-owner < "$input"
}

create_backup() {
    log_step "Резервное копирование"
    require_matrix
    local stamp backup_dir
    stamp=$(date +%Y%m%d-%H%M%S)
    backup_dir="$BACKUP_ROOT/$stamp"
    mkdir -p "$backup_dir"
    chmod 700 "$BACKUP_ROOT" "$backup_dir"
    cd "$MATRIX_DIR"

    run_spinner "Дамп базы Synapse" \
        dump_postgres_database postgres synapse synapse "$backup_dir/synapse.dump"
    if [[ "$HAS_MAS" == "true" ]]; then
        run_spinner "Дамп базы MAS" \
            dump_postgres_database mas-db mas_user mas "$backup_dir/mas.dump"
    fi
    local backup_items=(.env docker-compose.yml)
    local backup_item
    for backup_item in credentials.txt federation-domains.txt data/synapse data/mas \
        data/coturn data/livekit data/ketesa data/ntfy; do
        [[ -e "$backup_item" ]] && backup_items+=("$backup_item")
    done
    tar --exclude='./data/postgres' --exclude='./data/mas-db' \
        --exclude='./data/backups' --exclude='./data/synapse/media_store' \
        -czf "$backup_dir/configuration.tar.gz" "${backup_items[@]}" \
        || log_error "Не удалось архивировать конфигурацию"
    (
        cd "$backup_dir"
        local checksum_items=(synapse.dump configuration.tar.gz)
        [[ -f mas.dump ]] && checksum_items+=(mas.dump)
        sha256sum "${checksum_items[@]}" > SHA256SUMS
    )
    {
        echo "installer_version=$INSTALLER_VERSION"
        echo "created_at=$(date --iso-8601=seconds)"
        echo "server_name=$SERVER_NAME"
        echo "matrix_domain=$DOMAIN"
        echo "reason=${BACKUP_REASON:-manual}"
        echo "images:"
        docker compose config --images 2>/dev/null | sort -u | sed 's/^/  - /'
    } > "$backup_dir/MANIFEST.txt"
    (cd "$backup_dir" && sha256sum MANIFEST.txt >> SHA256SUMS)
    chmod -R go-rwx "$backup_dir"
    LAST_BACKUP_DIR="$backup_dir"
    log_ok "Резервная копия создана: $backup_dir"
    log_warn "Медиа-файлы не включены; каталог media_store следует копировать отдельно"
}

resolve_backup_dir() {
    local requested="${1:-}" resolved
    if [[ -z "$requested" || "$requested" == "latest" ]]; then
        requested=$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null \
            | sort -nr | awk 'NR == 1 {$1=""; sub(/^ /, ""); print}')
    fi
    [[ -n "$requested" && -d "$requested" ]] || log_error "Резервная копия не найдена: ${requested:-latest}"
    resolved=$(realpath -e "$requested")
    [[ -f "$resolved/SHA256SUMS" && -f "$resolved/configuration.tar.gz" && -f "$resolved/synapse.dump" ]] \
        || log_error "Неполная резервная копия: $resolved"
    printf '%s' "$resolved"
}

verify_backup() {
    local backup_dir="$1"
    (cd "$backup_dir" && sha256sum --check --status SHA256SUMS) \
        || log_error "Проверка SHA256 резервной копии не пройдена"
    tar -tzf "$backup_dir/configuration.tar.gz" >/dev/null \
        || log_error "Архив configuration.tar.gz повреждён"
    validate_backup_archive "$backup_dir/configuration.tar.gz"
    log_ok "Контрольные суммы резервной копии корректны"
}

validate_backup_archive() {
    local archive="$1"
    if ! python3 - "$archive" <<'PY'
import pathlib
import sys
import tarfile

archive = sys.argv[1]
allowed_files = {
    ".env",
    "docker-compose.yml",
    "credentials.txt",
    "federation-domains.txt",
}
allowed_prefixes = (
    "data/synapse",
    "data/mas",
    "data/coturn",
    "data/livekit",
    "data/ketesa",
    "data/ntfy",
)

def allowed(name: str) -> bool:
    normalized = name.rstrip("/")
    path = pathlib.PurePosixPath(normalized)
    if not normalized or path.is_absolute() or ".." in path.parts:
        return False
    return normalized in allowed_files or any(
        normalized == prefix or normalized.startswith(prefix + "/")
        for prefix in allowed_prefixes
    )

with tarfile.open(archive, "r:gz") as bundle:
    for member in bundle.getmembers():
        if not allowed(member.name):
            raise SystemExit(f"Недопустимый путь в backup: {member.name}")
        if not (member.isfile() or member.isdir()):
            raise SystemExit(f"Недопустимый тип объекта в backup: {member.name}")
PY
    then
        log_error "Архив содержит небезопасные или неожиданные объекты"
    fi
}

verify_backup_command() {
    local backup_dir
    backup_dir=$(resolve_backup_dir "${RESTORE_SOURCE:-latest}")
    verify_backup "$backup_dir"
    log_ok "Резервная копия готова к восстановлению: $backup_dir"
}

restore_backup() {
    log_step "Восстановление Matrix"
    local backup_dir
    backup_dir=$(resolve_backup_dir "${RESTORE_SOURCE:-latest}")
    verify_backup "$backup_dir"
    log_warn "Будут заменены текущие конфигурация и базы данных из $backup_dir"
    confirm_action "Продолжить восстановление" || { log_warn "Восстановление отменено"; return; }

    if [[ -f "$COMPOSE_FILE" ]]; then
        cd "$MATRIX_DIR"
        BACKUP_REASON="pre-restore" create_backup
        docker compose stop synapse mas lk-jwt-service ketesa element-admin ntfy livekit coturn \
            >/dev/null 2>&1 || true
    fi

    mkdir -p "$MATRIX_DIR"
    tar -xzf "$backup_dir/configuration.tar.gz" -C "$MATRIX_DIR"
    chmod 600 "$ENV_FILE"
    load_env
    detect_components
    cd "$MATRIX_DIR"
    regenerate_stack
    docker compose config --quiet || log_error "Восстановленный Compose некорректен"
    run_spinner "Запуск PostgreSQL для восстановления" docker compose up -d postgres
    for _ in {1..60}; do
        docker compose exec -T postgres pg_isready -U synapse -d synapse >/dev/null 2>&1 && break
        sleep 1
    done
    docker compose exec -T postgres pg_isready -U synapse -d synapse >/dev/null 2>&1 \
        || log_error "PostgreSQL не готов к восстановлению"
    run_spinner "Восстановление базы Synapse" \
        restore_postgres_database postgres synapse synapse "$backup_dir/synapse.dump"

    if [[ "$HAS_MAS" == "true" && -f "$backup_dir/mas.dump" ]]; then
        run_spinner "Запуск PostgreSQL MAS" docker compose up -d mas-db
        for _ in {1..60}; do
            docker compose exec -T mas-db pg_isready -U mas_user -d mas >/dev/null 2>&1 && break
            sleep 1
        done
        run_spinner "Восстановление базы MAS" \
            restore_postgres_database mas-db mas_user mas "$backup_dir/mas.dump"
    fi

    run_spinner "Запуск восстановленного стека" docker compose up -d --remove-orphans
    run_diagnostics
    log_ok "Восстановление завершено из $backup_dir"
}

save_update_state() {
    local state_file="$MATRIX_DIR/.last-update.env"
    {
        echo "# Previous image set saved by Install-Matrix v$INSTALLER_VERSION"
        printf 'POSTGRES_IMAGE=%q\n' "$POSTGRES_IMAGE"
        printf 'SYNAPSE_IMAGE=%q\n' "$SYNAPSE_IMAGE"
        printf 'COTURN_IMAGE=%q\n' "$COTURN_IMAGE"
        printf 'MAS_IMAGE=%q\n' "$MAS_IMAGE"
        printf 'LIVEKIT_IMAGE=%q\n' "$LIVEKIT_IMAGE"
        printf 'LK_JWT_IMAGE=%q\n' "$LK_JWT_IMAGE"
        printf 'KETESA_IMAGE=%q\n' "$KETESA_IMAGE"
        printf 'ELEMENT_ADMIN_IMAGE=%q\n' "$ELEMENT_ADMIN_IMAGE"
        printf 'NTFY_IMAGE=%q\n' "$NTFY_IMAGE"
        printf 'BACKUP_DIR=%q\n' "${LAST_BACKUP_DIR:-}"
    } > "$state_file"
    chmod 600 "$state_file"
}

apply_managed_image_defaults() {
    [[ "${IMAGE_POLICY:-managed}" == "managed" ]] || return 0
    POSTGRES_IMAGE="$POSTGRES_IMAGE_DEFAULT"
    SYNAPSE_IMAGE="$SYNAPSE_IMAGE_DEFAULT"
    COTURN_IMAGE="$COTURN_IMAGE_DEFAULT"
    MAS_IMAGE="$MAS_IMAGE_DEFAULT"
    LIVEKIT_IMAGE="$LIVEKIT_IMAGE_DEFAULT"
    LK_JWT_IMAGE="$LK_JWT_IMAGE_DEFAULT"
    KETESA_IMAGE="$KETESA_IMAGE_DEFAULT"
    ELEMENT_ADMIN_IMAGE="$ELEMENT_ADMIN_IMAGE_DEFAULT"
    NTFY_IMAGE="$NTFY_IMAGE_DEFAULT"
}

rollback_services() {
    log_step "Откат набора контейнеров"
    require_matrix
    local state_file="$MATRIX_DIR/.last-update.env"
    [[ -f "$state_file" ]] || log_error "Состояние предыдущего обновления не найдено"
    # Этот файл создаётся только установщиком, принадлежит root и имеет mode 0600.
    # shellcheck source=/dev/null
    source "$state_file"
    save_env
    cd "$MATRIX_DIR"
    regenerate_stack
    run_spinner "Загрузка предыдущих образов" docker compose pull
    run_spinner "Запуск предыдущего набора" docker compose up -d --remove-orphans
    run_diagnostics
    log_warn "Откатил образы. Для отката миграций БД используйте restore из BACKUP_DIR=${BACKUP_DIR:-не указан}"
}

uninstall_matrix() {
    log_step "Удаление Matrix"
    [[ -f "$ENV_FILE" ]] || log_error "Установка Matrix не найдена"
    load_env
    detect_components
    local mode="${UNINSTALL_MODE:-}"
    if [[ -z "$mode" ]]; then
        echo "  1) Удалить сервисы, сохранить данные"
        echo "  2) REMOVE EVERYTHING — удалить сервисы и /root/matrix-server"
        echo -ne "  ${CYAN}▶${NC}  Выбор: "
        read -r mode
        [[ "$mode" == "1" ]] && mode="keep-data"
        [[ "$mode" == "2" ]] && mode="purge"
    fi
    [[ "$mode" == "keep-data" || "$mode" == "purge" ]] \
        || log_error "Режим удаления: keep-data или purge"
    log_warn "Режим удаления: $mode"
    confirm_action "Остановить и удалить Matrix-сервисы" || { log_warn "Удаление отменено"; return; }

    local final_backup=""
    if [[ "$mode" == "purge" ]]; then
        BACKUP_REASON="pre-uninstall" create_backup
        final_backup="/root/install-matrix-final-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
        tar -C "$(dirname "$LAST_BACKUP_DIR")" -czf "$final_backup" "$(basename "$LAST_BACKUP_DIR")"
        chmod 600 "$final_backup"
    fi

    cd "$MATRIX_DIR"
    docker compose down --remove-orphans >/dev/null 2>&1 || true
    local pattern file
    for pattern in \
        "/etc/nginx/sites-available/matrix-${DOMAIN}.conf" \
        "/etc/nginx/sites-available/mas-${MAS_DOMAIN:-}.conf" \
        "/etc/nginx/sites-available/livekit-${LIVEKIT_DOMAIN:-}.conf" \
        "/etc/nginx/sites-available/ketesa-${KETESA_DOMAIN:-}.conf" \
        "/etc/nginx/sites-available/element-admin-${ELEMENT_ADMIN_DOMAIN:-}.conf" \
        "/etc/nginx/sites-available/ntfy-${NTFY_DOMAIN:-}.conf"; do
        [[ "$pattern" == *"-.conf" ]] && continue
        for file in "$pattern" "${pattern/sites-available/sites-enabled}"; do
            [[ -e "$file" || -L "$file" ]] && rm -f -- "$file"
        done
    done
    find /etc/nginx/snippets -maxdepth 1 -type f -name "matrix-${DOMAIN}-*.conf" -delete 2>/dev/null || true
    nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
    for pattern in "3478/tcp" "3478/udp" "5349/tcp" "5349/udp" \
        "49152:49252/udp" "7881/tcp" "7882/udp" "443/udp" "50000:50100/udp"; do
        ufw --force delete allow "$pattern" >/dev/null 2>&1 || true
    done
    rm -f /etc/sysctl.d/99-matrix-livekit.conf
    sysctl --system >/dev/null 2>&1 || true

    if [[ "$mode" == "purge" ]]; then
        [[ "$MATRIX_DIR" == "/root/matrix-server" ]] \
            || log_error "Защитная проверка отказалась удалить неожиданный путь: $MATRIX_DIR"
        rm -rf --one-file-system -- "$MATRIX_DIR"
        log_ok "Сервисы и данные Matrix удалены. Финальная backup-копия: $final_backup"
    else
        log_ok "Сервисы удалены, данные сохранены в $MATRIX_DIR"
    fi
}

diagnostic_check() {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        log_ok "$description"
        return 0
    fi
    log_warn "$description — ошибка"
    return 1
}

compose_service_running() {
    local service="$1"
    docker compose ps --status running --services 2>/dev/null | grep -Fqx "$service"
}

tls_certificate_valid() {
    local domain="$1"
    openssl s_client -connect "$domain:443" -servername "$domain" </dev/null 2>/dev/null \
        | openssl x509 -checkend 86400 -noout >/dev/null 2>&1
}

run_diagnostics() {
    log_step "Диагностика Matrix-стека"
    require_matrix
    cd "$MATRIX_DIR"
    local failures=0
    diagnostic_check "Docker Compose config корректен" docker compose config --quiet \
        || failures=$((failures + 1))
    diagnostic_check "PostgreSQL запущен" compose_service_running postgres \
        || failures=$((failures + 1))
    diagnostic_check "PostgreSQL принимает соединения" \
        docker compose exec -T postgres pg_isready -U synapse -d synapse \
        || failures=$((failures + 1))
    diagnostic_check "Synapse запущен" compose_service_running synapse \
        || failures=$((failures + 1))
    diagnostic_check "Coturn запущен" compose_service_running coturn \
        || failures=$((failures + 1))
    diagnostic_check "Nginx-конфигурация корректна" nginx -t \
        || failures=$((failures + 1))
    diagnostic_check "HTTPS-сертификат Matrix действителен" \
        tls_certificate_valid "$DOMAIN" \
        || failures=$((failures + 1))
    diagnostic_check "Matrix Client API отвечает" \
        curl -fsS --max-time 15 "https://$DOMAIN/_matrix/client/versions" \
        || failures=$((failures + 1))
    diagnostic_check "Matrix Federation API отвечает" \
        curl -fsS --max-time 15 "https://$DOMAIN/_matrix/federation/v1/version" \
        || failures=$((failures + 1))
    curl -fsS --max-time 15 "https://$SERVER_NAME/.well-known/matrix/server" \
        | jq -e '."m.server"' >/dev/null \
        && log_ok "server delegation работает" \
        || { log_warn "server delegation не работает"; failures=$((failures + 1)); }
    curl -fsS --max-time 15 "https://$SERVER_NAME/.well-known/matrix/client" \
        | jq -e '."m.homeserver".base_url' >/dev/null \
        && log_ok "client discovery работает" \
        || { log_warn "client discovery не работает"; failures=$((failures + 1)); }
    if [[ "$HAS_MAS" == "true" ]]; then
        diagnostic_check "MAS запущен" compose_service_running mas \
            || failures=$((failures + 1))
        docker compose exec -T mas mas-cli --config /app/config/config.yaml doctor >"$RUNTIME_DIR/mas-doctor.log" 2>&1 \
            && log_ok "MAS doctor не нашёл критических ошибок" \
            || { log_warn "MAS doctor сообщил об ошибке (диагностический лог: $RUNTIME_DIR/mas-doctor.log)"; failures=$((failures + 1)); }
    fi
    if [[ "$HAS_LIVEKIT" == "true" ]]; then
        diagnostic_check "LiveKit запущен" compose_service_running livekit \
            || failures=$((failures + 1))
        diagnostic_check "MatrixRTC JWT service запущен" compose_service_running lk-jwt-service \
            || failures=$((failures + 1))
        diagnostic_check "MatrixRTC health endpoint отвечает" \
            curl -fsS --max-time 15 "https://$DOMAIN/lk-jwt/healthz" \
            || failures=$((failures + 1))
    fi
    if [[ "$HAS_NTFY" == "true" ]]; then
        diagnostic_check "ntfy health endpoint отвечает" \
            curl -fsS --max-time 15 "https://$NTFY_DOMAIN/v1/health" \
            || failures=$((failures + 1))
    fi
    docker compose ps
    [[ $failures -eq 0 ]] && log_ok "Все проверки пройдены" \
        || log_warn "Не пройдено проверок: $failures"
    return "$failures"
}

update_services() {
    log_step "Обновление контейнеров"
    require_matrix
    BACKUP_REASON="pre-update" create_backup
    save_update_state
    apply_managed_image_defaults
    save_env
    cd "$MATRIX_DIR"
    regenerate_stack
    if ! run_spinner "Загрузка закреплённых образов" docker compose pull; then
        log_warn "Загрузка образов не удалась; возвращаю предыдущий набор"
        rollback_services
        return 1
    fi
    if ! run_spinner "Пересоздание контейнеров" docker compose up -d --remove-orphans; then
        log_warn "Запуск обновлённого стека не удался; выполняю rollback"
        rollback_services
        return 1
    fi
    if ! run_diagnostics; then
        log_warn "Post-update диагностика не пройдена; выполняю rollback образов"
        rollback_services
        return 1
    fi
    log_ok "Обновление завершено; backup: $LAST_BACKUP_DIR"
}

configure_registration() {
    log_step "Режим регистрации"
    require_matrix
    if [[ "$HAS_MAS" == "true" ]]; then
        log_warn "Регистрацией управляет MAS; выбранный режим будет применён и к MAS, и к Synapse"
        echo "  Для режима token токены создаются средствами MAS."
    fi
    echo "  1) Закрытая регистрация (рекомендуется)"
    echo "  2) Регистрация только по токену Synapse"
    echo "  3) Открытая регистрация без токена (обычный мессенджер)"
    echo -ne "  ${CYAN}▶${NC}  Выбор: "
    local registration_choice
    read -r registration_choice
    case "$registration_choice" in
        1) REGISTRATION_MODE="closed" ;;
        2) REGISTRATION_MODE="token" ;;
        3)
            log_warn "Открытая регистрация без проверки допускает массовое создание аккаунтов и abuse"
            confirm_action "Я понимаю риск и хочу включить открытую регистрацию" \
                || { log_warn "Изменение отменено"; return; }
            ALLOW_OPEN_REGISTRATION=true
            REGISTRATION_MODE="open"
            ;;
        *) log_error "Неверный выбор" ;;
    esac
    save_env
    cd "$MATRIX_DIR"
    apply_synapse_config
    if [[ "$HAS_MAS" == "true" && -f "$MATRIX_DIR/data/mas/config.yaml" ]]; then
        if [[ "$REGISTRATION_MODE" == "open" ]]; then
            sed -i 's/password_registration_enabled: false/password_registration_enabled: true/; s/password_registration_token_required: true/password_registration_token_required: false/' \
                "$MATRIX_DIR/data/mas/config.yaml"
        elif [[ "$REGISTRATION_MODE" == "token" ]]; then
            sed -i 's/password_registration_enabled: false/password_registration_enabled: true/; s/password_registration_token_required: false/password_registration_token_required: true/' \
                "$MATRIX_DIR/data/mas/config.yaml"
        else
            sed -i 's/password_registration_enabled: true/password_registration_enabled: false/' \
                "$MATRIX_DIR/data/mas/config.yaml"
        fi
        chmod 0644 "$MATRIX_DIR/data/mas/config.yaml"
        docker compose restart mas >/dev/null 2>&1 || true
    fi
    log_ok "Режим регистрации: $REGISTRATION_MODE"
}

# ════════════════════════════════════════
#  УСТАНОВКА XRAY (С ДОБАВЛЕНИЕМ GEO-БАЗ)
# ════════════════════════════════════════
install_xray_proxy() {
    log_step "Установка Xray-клиента и маршрутизация контейнеров"
    require_matrix
    echo "  Эта функция направляет внешний HTTP(S)-трафик Docker-контейнеров через VLESS."
    echo "  Локальные, частные и российские назначения остаются DIRECT."
    if [[ -f /usr/local/etc/xray/config.json ]]; then
        log_warn "Найден существующий /usr/local/etc/xray/config.json"
        echo -ne "  Перезаписать его после создания резервной копии? [y/N]: "
        local overwrite_xray
        read -r overwrite_xray
        [[ "$overwrite_xray" =~ ^[YyДд]$ ]] || { log_warn "Установка Xray отменена"; return; }
        cp /usr/local/etc/xray/config.json \
            "/usr/local/etc/xray/config.json.backup.$(date +%Y%m%d-%H%M%S)"
    fi

    local vless_uri xray_tmp install_script
    echo -ne "  ${CYAN}▶${NC}  VLESS URI: "
    read -rs vless_uri
    echo ""
    [[ "$vless_uri" == vless://* ]] || log_error "Ожидалась ссылка vless://"
    xray_tmp=$(mktemp /tmp/matrix-xray-config.XXXXXX)

    python3 - "$vless_uri" "$xray_tmp" <<'PY'
import json
import sys
from urllib.parse import parse_qs, unquote, urlparse

uri, output = sys.argv[1], sys.argv[2]
parsed = urlparse(uri)
query = {key: values[-1] for key, values in parse_qs(parsed.query).items()}
if parsed.scheme != "vless" or not parsed.username or not parsed.hostname or not parsed.port:
    raise SystemExit("Некорректный VLESS URI: нужны UUID, host и port")

network = query.get("type", "tcp")
security = query.get("security", "none")
stream = {"network": network, "security": security}
if security == "reality":
    stream["realitySettings"] = {
        "serverName": query.get("sni", parsed.hostname),
        "fingerprint": query.get("fp", "chrome"),
        "publicKey": query.get("pbk", ""),
        "shortId": query.get("sid", ""),
        "spiderX": unquote(query.get("spx", "/")),
    }
elif security == "tls":
    stream["tlsSettings"] = {
        "serverName": query.get("sni", parsed.hostname),
        "fingerprint": query.get("fp", "chrome"),
        "allowInsecure": query.get("allowInsecure", "0") in ("1", "true"),
    }

host = query.get("host", parsed.hostname)
path = unquote(query.get("path", "/"))
if network == "ws":
    stream["wsSettings"] = {"path": path, "headers": {"Host": host}}
elif network == "grpc":
    stream["grpcSettings"] = {"serviceName": query.get("serviceName", path.lstrip("/"))}
elif network in ("xhttp", "splithttp"):
    stream["xhttpSettings"] = {
        "path": path,
        "host": host,
        "mode": query.get("mode", "auto"),
    }
elif network == "tcp" and query.get("headerType") == "http":
    stream["tcpSettings"] = {
        "header": {"type": "http", "request": {"path": [path], "headers": {"Host": [host]}}}
    }

user = {"id": parsed.username, "encryption": query.get("encryption", "none")}
if query.get("flow"):
    user["flow"] = query["flow"]

config = {
    "log": {"loglevel": "warning"},
    "inbounds": [
        {"tag": "socks-in", "listen": "0.0.0.0", "port": 10808,
         "protocol": "socks", "settings": {"auth": "noauth", "udp": True}},
        {"tag": "http-in", "listen": "0.0.0.0", "port": 10809,
         "protocol": "http", "settings": {}},
    ],
    "outbounds": [
        {"tag": "vless-proxy", "protocol": "vless", "settings": {"vnext": [{
            "address": parsed.hostname, "port": parsed.port, "users": [user]
        }]}, "streamSettings": stream},
        {"tag": "direct", "protocol": "freedom"},
        {"tag": "block", "protocol": "blackhole"},
    ],
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {"type": "field", "protocol": ["bittorrent"], "outboundTag": "block"},
            {"type": "field", "ip": ["geoip:private", "geoip:ru"], "outboundTag": "direct"},
            {"type": "field", "domain": ["geosite:private", "geosite:category-ru"], "outboundTag": "direct"},
        ],
    },
}
with open(output, "w", encoding="utf-8") as handle:
    json.dump(config, handle, ensure_ascii=False, indent=2)
PY
    unset vless_uri

    install_script=$(mktemp /tmp/xray-install.XXXXXX)
    run_with_retry "Загрузка официального установщика Xray" \
        curl -fsSL --retry 3 \
        "$XRAY_INSTALL_URL" \
        -o "$install_script"
    echo "$XRAY_INSTALL_SHA256  $install_script" | sha256sum --check --status \
        || log_error "Checksum установщика Xray не совпал"
    chmod 700 "$install_script"
    run_spinner "Установка Xray $XRAY_VERSION" \
        bash "$install_script" install --version "$XRAY_VERSION"
    rm -f "$install_script"
    install -d -m 700 /usr/local/etc/xray
    install -m 600 "$xray_tmp" /usr/local/etc/xray/config.json
    rm -f "$xray_tmp"
    local xray_service_user
    xray_service_user=$(systemctl show -p User --value xray 2>/dev/null || true)
    xray_service_user="${xray_service_user:-root}"
    chown "$xray_service_user" /usr/local/etc/xray /usr/local/etc/xray/config.json
    /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json \
        || log_error "Xray отклонил сгенерированную конфигурацию"
    systemctl enable --now xray

    # === ДОБАВЛЯЕМ СВЕЖИЕ GEO-БАЗЫ ОТ runetfreedom ===
    log_step "Загрузка актуальных geo-баз для Xray"
    mkdir -p /usr/local/share/xray
    local geosite_tmp="$RUNTIME_DIR/geosite.dat"
    local geoip_tmp="$RUNTIME_DIR/geoip.dat"
    run_with_retry "Загрузка geosite.dat (RU)" \
        curl -fsSL "https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/download/$XRAY_GEO_RELEASE/geosite.dat" \
        -o "$geosite_tmp"
    run_with_retry "Загрузка geoip.dat (RU)" \
        curl -fsSL "https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/download/$XRAY_GEO_RELEASE/geoip.dat" \
        -o "$geoip_tmp"
    echo "$XRAY_GEOSITE_SHA256  $geosite_tmp" | sha256sum --check --status \
        || log_error "SHA256 geosite.dat не совпадает"
    echo "$XRAY_GEOIP_SHA256  $geoip_tmp" | sha256sum --check --status \
        || log_error "SHA256 geoip.dat не совпадает"
    install -m 0644 "$geosite_tmp" /usr/local/share/xray/geosite.dat
    install -m 0644 "$geoip_tmp" /usr/local/share/xray/geoip.dat
    chown "$xray_service_user" /usr/local/share/xray/geosite.dat /usr/local/share/xray/geoip.dat
    log_ok "Geo-базы обновлены"

    mkdir -p /etc/systemd/system/docker.service.d
    cat > /etc/systemd/system/docker.service.d/http-proxy.conf <<'EOF'
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:10809"
Environment="HTTPS_PROXY=http://127.0.0.1:10809"
Environment="NO_PROXY=localhost,127.0.0.1,::1,172.16.0.0/12,10.0.0.0/8,192.168.0.0/16"
EOF
    systemctl daemon-reload
    systemctl restart docker

    ufw insert 1 allow from 172.16.0.0/12 to any port 10808 proto tcp >/dev/null 2>&1 || true
    ufw insert 1 allow from 172.16.0.0/12 to any port 10809 proto tcp >/dev/null 2>&1 || true
    ufw deny 10808/tcp >/dev/null 2>&1 || true
    ufw deny 10809/tcp >/dev/null 2>&1 || true

    PROXY_ENABLED="true"
    CONTAINER_PROXY_URL="http://host.docker.internal:10809"
    save_env
    cd "$MATRIX_DIR"
    regenerate_stack
    run_spinner "Перезапуск Matrix-стека с прокси" docker compose up -d
    curl --fail --silent --show-error --max-time 20 \
        --proxy http://127.0.0.1:10809 https://api.ipify.org >/dev/null \
        || log_error "Xray запущен, но тестовый HTTP-запрос через него не прошёл"
    local matrix_org_federation_status
    matrix_org_federation_status=$(curl --silent --show-error --max-time 25 \
        --proxy http://127.0.0.1:10809 \
        --output /dev/null --write-out '%{http_code}' \
        'https://matrix-federation.matrix.org/_matrix/federation/v1/query/directory?room_alias=%23matrix%3Amatrix.org' \
        || true)
    case "$matrix_org_federation_status" in
        401)
            log_ok "Выходной IP прокси принимается федерацией matrix.org"
            ;;
        429)
            log_warn "matrix.org отклоняет выходной IP прокси (HTTP 429); поиск, профили и комнаты matrix.org не заработают, пока не будет заменён VLESS-выход"
            ;;
        *)
            log_warn "Не удалось подтвердить доступ к федерации matrix.org через прокси (HTTP ${matrix_org_federation_status:-000})"
            ;;
    esac
    log_ok "Xray настроен; Docker и контейнеры используют HTTP-прокси 10809"
}

# ════════════════════════════════════════
#  CLI И МЕНЮ
# ════════════════════════════════════════
show_help() {
    cat <<EOF
Install-Matrix v$INSTALLER_VERSION

Использование:
  sudo ./install-matrix.sh [command] [options]

Команды:
  menu                    Интерактивное меню (по умолчанию)
  install                 Установить или восстановить базовый Matrix
  install-mas             Установить MAS
  install-livekit         Установить LiveKit/MatrixRTC
  backup                  Создать проверяемую резервную копию
  verify-backup [DIR|latest]
                          Проверить SHA256 и безопасность архива без restore
  restore [DIR|latest]    Восстановить конфигурацию и базы
  diagnose                Выполнить post-install health checks
  update                  Обновить managed-образы с backup и rollback
  rollback                Вернуть набор образов до последнего update
  uninstall               Удалить сервисы; данные сохраняются по умолчанию
  version                 Показать версию

Опции автоматизации:
  --config FILE                 Прочитать разрешённые KEY=VALUE из файла
  --non-interactive             Не задавать интерактивных вопросов
  --yes                         Подтвердить безопасные автоматические действия
  --dry-run                     Проверить config и отрендерить YAML без изменений ОС
  --server-name DOMAIN          Домен Matrix ID, например example.com
  --domain DOMAIN               Публичный Matrix API, например matrix.example.com
  --admin-email EMAIL           Email Let's Encrypt
  --admin-user USER             Создать первого администратора
  --admin-password-file FILE    Прочитать пароль администратора из файла
  --registration MODE           closed, token или open
  --allow-open-registration     Явно подтвердить риск режима open
  --external-ip IPv4            Не определять публичный IPv4 автоматически
  --keep-data                   Для uninstall: сохранить /root/matrix-server
  --purge                       Для uninstall: удалить данные после внешнего backup
  -h, --help                    Показать справку
  -V, --version                 Показать версию

Примеры:
  sudo ./install-matrix.sh install --non-interactive --config config.env --yes
  sudo ./install-matrix.sh backup
  sudo ./install-matrix.sh verify-backup latest
  sudo ./install-matrix.sh restore latest
  sudo ./install-matrix.sh uninstall --keep-data

Документация: $INSTALLER_REPOSITORY
EOF
}

require_option_value() {
    local option="$1" value="${2:-}"
    [[ -n "$value" && "$value" != --* ]] || log_error "$option требует значение"
}

parse_cli() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            menu|install|install-mas|install-livekit|backup|diagnose|update|rollback|uninstall|version)
                CLI_COMMAND="$1"; shift ;;
            restore|verify-backup)
                CLI_COMMAND="$1"
                if [[ -n "${2:-}" && "$2" != --* ]]; then RESTORE_SOURCE="$2"; shift; fi
                shift
                ;;
            --install) CLI_COMMAND="install"; shift ;;
            --install-mas) CLI_COMMAND="install-mas"; shift ;;
            --install-livekit) CLI_COMMAND="install-livekit"; shift ;;
            --backup) CLI_COMMAND="backup"; shift ;;
            --verify-backup)
                CLI_COMMAND="verify-backup"
                if [[ -n "${2:-}" && "$2" != --* ]]; then RESTORE_SOURCE="$2"; shift; fi
                shift
                ;;
            --restore)
                CLI_COMMAND="restore"
                if [[ -n "${2:-}" && "$2" != --* ]]; then RESTORE_SOURCE="$2"; shift; fi
                shift
                ;;
            --uninstall) CLI_COMMAND="uninstall"; shift ;;
            --config)
                require_option_value "$1" "${2:-}"; load_config_file "$2"; shift 2 ;;
            --non-interactive) NON_INTERACTIVE=true; shift ;;
            --yes) ASSUME_YES=true; shift ;;
            --dry-run) DRY_RUN=true; NON_INTERACTIVE=true; shift ;;
            --allow-open-registration) ALLOW_OPEN_REGISTRATION=true; shift ;;
            --server-name) require_option_value "$1" "${2:-}"; SERVER_NAME="$2"; USER_OVERRIDES[SERVER_NAME]="$2"; shift 2 ;;
            --domain) require_option_value "$1" "${2:-}"; DOMAIN="$2"; USER_OVERRIDES[DOMAIN]="$2"; shift 2 ;;
            --admin-email) require_option_value "$1" "${2:-}"; ADMIN_EMAIL="$2"; USER_OVERRIDES[ADMIN_EMAIL]="$2"; shift 2 ;;
            --admin-user) require_option_value "$1" "${2:-}"; ADMIN_USER="$2"; USER_OVERRIDES[ADMIN_USER]="$2"; shift 2 ;;
            --admin-password-file) require_option_value "$1" "${2:-}"; ADMIN_PASSWORD_FILE="$2"; USER_OVERRIDES[ADMIN_PASSWORD_FILE]="$2"; shift 2 ;;
            --registration) require_option_value "$1" "${2:-}"; REGISTRATION_MODE="$2"; USER_OVERRIDES[REGISTRATION_MODE]="$2"; shift 2 ;;
            --external-ip) require_option_value "$1" "${2:-}"; EXTERNAL_IP="$2"; USER_OVERRIDES[EXTERNAL_IP]="$2"; shift 2 ;;
            --keep-data) UNINSTALL_MODE="keep-data"; shift ;;
            --purge) UNINSTALL_MODE="purge"; shift ;;
            -h|--help) CLI_COMMAND="help"; shift ;;
            -V|--version) CLI_COMMAND="version"; shift ;;
            *) log_error "Неизвестный аргумент: $1. Используйте --help" ;;
        esac
    done
}

dry_run_install() {
    log_step "Dry run"
    validate_non_interactive_config
    local dry_dir has_mas has_livekit has_ketesa has_element_admin has_ntfy
    dry_dir=$(mktemp -d /tmp/install-matrix-dry-run.XXXXXX)
    has_mas="${ENABLE_MAS:-false}"
    has_livekit="${ENABLE_LIVEKIT:-false}"
    has_ketesa="${ENABLE_KETESA:-false}"
    has_element_admin="${ENABLE_ELEMENT_ADMIN:-false}"
    has_ntfy="${ENABLE_NTFY:-false}"
    [[ "$has_livekit" != "true" || "$has_mas" == "true" ]] \
        || log_error "ENABLE_LIVEKIT=true требует ENABLE_MAS=true"
    [[ "$has_element_admin" != "true" || "$has_mas" == "true" ]] \
        || log_error "ENABLE_ELEMENT_ADMIN=true требует ENABLE_MAS=true"

    MATRIX_DIR="$dry_dir"
    ENV_FILE="$MATRIX_DIR/.env"
    COMPOSE_FILE="$MATRIX_DIR/docker-compose.yml"
    HOMESERVER_FILE="$MATRIX_DIR/data/synapse/homeserver.yaml"
    FEDERATION_FILE="$MATRIX_DIR/federation-domains.txt"
    BACKUP_ROOT="$MATRIX_DIR/data/backups"
    SKIP_OWNERSHIP=true
    DB_PASSWORD="${DB_PASSWORD:-dry-run-db-password}"
    REG_SHARED_SECRET="${REG_SHARED_SECRET:-dry-run-registration-secret}"
    MACAROON_SECRET="${MACAROON_SECRET:-dry-run-macaroon-secret}"
    FORM_SECRET="${FORM_SECRET:-dry-run-form-secret}"
    TURN_SECRET="${TURN_SECRET:-dry-run-turn-secret}"
    MAS_SECRET="${MAS_SECRET:-dry-run-mas-secret}"
    MAS_DB_PASSWORD="${MAS_DB_PASSWORD:-dry-run-mas-db-password}"
    LIVEKIT_KEY="${LIVEKIT_KEY:-dry-run-livekit-key}"
    LIVEKIT_SECRET="${LIVEKIT_SECRET:-dry-run-livekit-secret}"
    MAX_UPLOAD_SIZE="${MAX_UPLOAD_SIZE:-2048M}"
    REMOTE_MEDIA_LIFETIME="${REMOTE_MEDIA_LIFETIME:-14d}"
    LOCAL_MEDIA_LIFETIME="${LOCAL_MEDIA_LIFETIME:-30d}"
    PRESENCE_ENABLED="${PRESENCE_ENABLED:-false}"
    RETENTION_ENABLED="${RETENTION_ENABLED:-true}"
    RETENTION_DEFAULT_MIN_LIFETIME="${RETENTION_DEFAULT_MIN_LIFETIME:-1d}"
    RETENTION_DEFAULT_MAX_LIFETIME="${RETENTION_DEFAULT_MAX_LIFETIME:-365d}"
    FEDERATION_MODE="${FEDERATION_MODE:-public}"
    CONTAINER_PROXY_URL="${CONTAINER_PROXY_URL:-}"
    mkdir -p "$MATRIX_DIR/data/synapse"
    : > "$FEDERATION_FILE"
    set_image_defaults
    generate_compose "$has_mas" "$has_livekit" "$has_ketesa" "$has_element_admin" "$has_ntfy"
    generate_homeserver "$has_mas" "$has_livekit"
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        docker compose -f "$COMPOSE_FILE" config --quiet
    fi
    python3 - "$COMPOSE_FILE" "$HOMESERVER_FILE" <<'PY'
import sys
import yaml
for filename in sys.argv[1:]:
    with open(filename, encoding="utf-8") as handle:
        yaml.safe_load(handle)
PY
    log_ok "Dry run пройден: Compose и Synapse YAML корректны"
    rm -rf -- "$dry_dir"
}

dispatch_cli() {
    case "$CLI_COMMAND" in
        help) show_help; return ;;
        version) echo "Install-Matrix v$INSTALLER_VERSION"; return ;;
    esac
    if [[ "$DRY_RUN" == "true" ]]; then
        dry_run_install
        return
    fi
    check_system
    case "$CLI_COMMAND" in
        menu)
            while true; do
                show_menu
                echo ""
                echo -ne "  ${DIM}Нажмите Enter для возврата в меню...${NC}"
                read -r
            done
            ;;
        install)
            install_matrix
            if [[ "${ENABLE_MAS:-false}" == "true" ]]; then install_mas; fi
            if [[ "${ENABLE_LIVEKIT:-false}" == "true" ]]; then install_livekit; fi
            if [[ "${ENABLE_KETESA:-false}" == "true" ]]; then install_ketesa; fi
            if [[ "${ENABLE_ELEMENT_ADMIN:-false}" == "true" ]]; then install_element_admin; fi
            if [[ "${ENABLE_NTFY:-false}" == "true" ]]; then install_ntfy; fi
            ;;
        install-mas) install_mas ;;
        install-livekit) install_livekit ;;
        backup) create_backup ;;
        verify-backup) verify_backup_command ;;
        restore) restore_backup ;;
        diagnose) run_diagnostics ;;
        update) update_services ;;
        rollback) rollback_services ;;
        uninstall) uninstall_matrix ;;
        *) log_error "Неизвестная команда: $CLI_COMMAND" ;;
    esac
}

show_menu() {
    clear 2>/dev/null || true
    echo ""
    echo -e "${BRED}          ▄█████████████████████████████████████▄${NC}"
    echo -e "${BRED}        ████                                   ████${NC}"
    echo -e "${BRED}       ████   ${RED}▓▓▓▓▓▓▓▓▓▓${BRED}         ${RED}▓▓▓▓▓▓▓▓▓▓${BRED}   ████${NC}"
    echo -e "${BRED}       ████   ${RED}▓▓        ▓▓${BRED}       ${RED}▓▓        ▓▓${BRED}   ████${NC}"
    echo -e "${BRED}       ████   ${RED}▓▓  ${YELLOW}██████${RED}  ▓▓     ▓▓  ${YELLOW}██████${RED}  ▓▓${BRED}   ████${NC}"
    echo -e "${BRED}       ████   ${RED}▓▓  ${YELLOW}██████${RED}  ▓▓     ▓▓  ${YELLOW}██████${RED}  ▓▓${BRED}   ████${NC}"
    echo -e "${BRED}       ████   ${RED}▓▓        ▓▓${BRED}       ${RED}▓▓        ▓▓${BRED}   ████${NC}"
    echo -e "${BRED}       ████   ${RED}▓▓▓▓▓▓▓▓▓▓${BRED}         ${RED}▓▓▓▓▓▓▓▓▓▓${BRED}   ████${NC}"
    echo -e "${BRED}        ████                                   ████${NC}"
    echo -e "${BRED}          ▀█████████████████████████████████████▀${NC}"
    echo ""
    echo -e "${BRED}  ███╗   ███╗ █████╗ ████████╗██████╗ ██╗██╗  ██╗${NC}"
    echo -e "${BRED}  ████╗ ████║██╔══██╗╚══██╔══╝██╔══██╗██║╚██╗██╔╝${NC}"
    echo -e "${BRED}  ██╔████╔██║███████║   ██║   ██████╔╝██║ ╚███╔╝ ${NC}"
    echo -e "${BRED}  ██║╚██╔╝██║██╔══██║   ██║   ██╔══██╗██║ ██╔██╗ ${NC}"
    echo -e "${BRED}  ██║ ╚═╝ ██║██║  ██║   ██║   ██║  ██║██║██╔╝ ██╗${NC}"
    echo -e "${BRED}  ╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝${NC}"
    echo ""
    echo -e "${YELLOW}       ███████╗███████╗██████╗ ██╗   ██╗███████╗██████╗ ${NC}"
    echo -e "${YELLOW}       ██╔════╝██╔════╝██╔══██╗██║   ██║██╔════╝██╔══██╗${NC}"
    echo -e "${YELLOW}       ███████╗█████╗  ██████╔╝██║   ██║█████╗  ██████╔╝${NC}"
    echo -e "${YELLOW}       ╚════██║██╔══╝  ██╔══██╗╚██╗ ██╔╝██╔══╝  ██╔══██╗${NC}"
    echo -e "${YELLOW}       ███████║███████╗██║  ██║ ╚████╔╝ ███████╗██║  ██║ ${NC}"
    echo -e "${YELLOW}       ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝${NC}"
    echo ""
    echo -e "${BRED}  ════════════════════════════════════════════════════════${NC}"
    echo -e "     ${DIM}Ubuntu/Debian  ·  version $INSTALLER_VERSION${NC}"
    echo -e "${BRED}  ════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${WHITE}Выберите действие:${NC}"
    echo ""
    echo -e "    ${CYAN}1)${NC}  Установить/восстановить ${WHITE}Matrix${NC} (Synapse + PostgreSQL + Coturn)"
    echo -e "    ${CYAN}2)${NC}  Установить ${WHITE}MAS${NC} (Matrix Authentication Service)"
    echo -e "    ${CYAN}3)${NC}  Установить ${WHITE}LiveKit${NC} (сервер MatrixRTC; без Element Call)"
    echo -e "    ${CYAN}4)${NC}  ${WHITE}Добавить федерацию${NC} в ограниченный allowlist"
    echo -e "    ${CYAN}5)${NC}  Управление федерацией (просмотр/удаление/публичный режим)"
    echo -e "    ${CYAN}6)${NC}  Установить ${WHITE}Ketesa Admin${NC} (рекомендуемая лёгкая админка)"
    echo -e "    ${CYAN}7)${NC}  Установить ${WHITE}Element Admin${NC} (требует MAS)"
    echo -e "    ${CYAN}8)${NC}  Установить ${WHITE}ntfy${NC} (сервер UnifiedPush)"
    echo -e "    ${CYAN}9)${NC}  Настроить ${WHITE}Xray/VLESS${NC} для исходящего трафика"
    echo -e "   ${CYAN}10)${NC}  Настроить регистрацию"
    echo -e "   ${CYAN}11)${NC}  Создать резервную копию"
    echo -e "   ${CYAN}12)${NC}  Диагностика стека"
    echo -e "   ${CYAN}13)${NC}  Обновить закреплённые контейнеры (с backup)"
    echo -e "   ${CYAN}14)${NC}  Восстановить из резервной копии"
    echo -e "   ${CYAN}15)${NC}  Откатить контейнеры после обновления"
    echo -e "   ${CYAN}16)${NC}  Удалить Matrix (сохранить данные или удалить всё)"
    echo -e "    ${CYAN}0)${NC}  Выход"
    echo ""
    echo -ne "  ${CYAN}▶${NC}  "
    read -r choice
    case "$choice" in
        1) install_matrix ;;
        2) install_mas ;;
        3) install_livekit ;;
        4) add_federation_domain ;;
        5) manage_federation ;;
        6) install_ketesa ;;
        7) install_element_admin ;;
        8) install_ntfy ;;
        9) install_xray_proxy ;;
        10) configure_registration ;;
        11) create_backup ;;
        12) run_diagnostics ;;
        13) update_services ;;
        14) RESTORE_SOURCE="latest"; restore_backup ;;
        15) rollback_services ;;
        16) uninstall_matrix ;;
        0) echo -e "  ${GREEN}Выход.${NC}"; exit 0 ;;
        *) echo -e "  ${RED}Неверный выбор.${NC}"; sleep 1 ;;
    esac
}

# ════════════════════════════════════════
#  ЗАПУСК
# ════════════════════════════════════════
if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" \
      || "${BASH_SOURCE[0]}" == "/dev/stdin" ]]; then
    initialize_runtime_dir
    parse_cli "$@"
    dispatch_cli
fi
