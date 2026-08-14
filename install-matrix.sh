#!/bin/bash

# ============================================================
#  MATRIX SERVER INSTALLER v4.0
#  by zxchubbabubba
#  Поддерживает: Ubuntu 20.04+ / Debian 11+
#  Меню: Matrix, MAS, LiveKit, federation, admin UIs, ntfy, Xray, backup
# ============================================================

set -Ee -o pipefail
umask 077

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
POSTGRES_IMAGE_DEFAULT="postgres:16.15-alpine"
SYNAPSE_IMAGE_DEFAULT="ghcr.io/element-hq/synapse:v1.158.0"
COTURN_IMAGE_DEFAULT="coturn/coturn:4.17.2-r0"
MAS_IMAGE_DEFAULT="ghcr.io/element-hq/matrix-authentication-service:1.22.0"
LIVEKIT_IMAGE_DEFAULT="livekit/livekit-server:v1.13.5"
LK_JWT_IMAGE_DEFAULT="ghcr.io/element-hq/lk-jwt-service:0.5.0"
KETESA_IMAGE_DEFAULT="ghcr.io/etkecc/ketesa:v1.4.0"
ELEMENT_ADMIN_IMAGE_DEFAULT="oci.element.io/element-admin:0.1.12"
NTFY_IMAGE_DEFAULT="binwiederhier/ntfy:v2.27.0"
XRAY_VERSION_DEFAULT="v26.3.27"

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

    "$@" >/tmp/matrix_cmd.log 2>&1 &
    local pid=$!

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}${frames[$i]}${NC}  ${DIM}%s...${NC}          " "$msg"
        i=$(( (i+1) % ${#frames[@]} ))
        sleep 0.08
    done

    if ! wait "$pid"; then
        printf "\r  ${BRED}✗${NC}  ${RED}%s — ошибка!${NC}\n\n" "$msg"
        echo -e "${DIM}"
        tail -25 /tmp/matrix_cmd.log
        echo -e "${NC}"
        return 1
    fi

    printf "\r  ${BGREEN}✓${NC}  ${WHITE}%s${NC}                    \n" "$msg"
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

detect_components() {
    HAS_MAS=false
    HAS_LIVEKIT=false
    HAS_KETESA=false
    HAS_ELEMENT_ADMIN=false
    HAS_NTFY=false
    [[ -n "${MAS_DOMAIN:-}" && -f "$MATRIX_DIR/data/mas/config.yaml" ]] && HAS_MAS=true
    [[ -n "${LIVEKIT_DOMAIN:-}" && -f "$MATRIX_DIR/data/livekit/livekit.yaml" ]] && HAS_LIVEKIT=true
    [[ -n "${KETESA_DOMAIN:-}" ]] && HAS_KETESA=true
    [[ -n "${ELEMENT_ADMIN_DOMAIN:-}" ]] && HAS_ELEMENT_ADMIN=true
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

    case "$DISTRO" in
        ubuntu)
            if [[ "$VERSION" -lt 20 ]]; then
                log_error "Требуется Ubuntu 20.04 или новее."
            fi
            log_ok "ОС: Ubuntu $VERSION"
            ;;
        debian)
            if [[ "$VERSION" -lt 11 ]]; then
                log_error "Требуется Debian 11 (bullseye) или новее."
            fi
            log_ok "ОС: Debian $VERSION"
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
        return
    fi
    log_warn "На сервере меньше 4 ГБ RAM и нет swap"
    echo -ne "  Создать swap-файл 2 ГБ? [Y/n]: "
    local swap_choice
    read -r swap_choice
    if [[ -n "$swap_choice" && ! "$swap_choice" =~ ^[YyДд]$ ]]; then
        log_warn "Swap не создан"
        return
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
    run_with_retry "Загрузка ключа Docker" \
        curl -fsSL "https://download.docker.com/linux/$DISTRO/gpg" \
        -o /tmp/docker-repository.gpg
    gpg --batch --yes --dearmor \
        -o /usr/share/keyrings/docker-archive-keyring.gpg /tmp/docker-repository.gpg
    chmod 0644 /usr/share/keyrings/docker-archive-keyring.gpg
    rm -f /tmp/docker-repository.gpg

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

configure_well_known() {
    local has_livekit="${1:-false}"
    local snippet="/etc/nginx/snippets/matrix-${DOMAIN}-well-known.conf"
    local client_json
    set_nginx_http2_syntax

    client_json="{\"m.homeserver\":{\"base_url\":\"https://$DOMAIN\"}}"
    if [[ "$has_livekit" == "true" ]]; then
        client_json="{\"m.homeserver\":{\"base_url\":\"https://$DOMAIN\"},\"org.matrix.msc4143.rtc_foci\":[{\"type\":\"livekit\",\"livekit_service_url\":\"https://$DOMAIN/lk-jwt\"}]}"
    fi

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

    for rule in \
        "22/tcp" "80/tcp" "443/tcp" \
        "3478/tcp" "3478/udp" \
        "5349/tcp" "5349/udp" \
        "49152:49252/udp"
    do
        ufw allow "$rule" >/dev/null 2>&1
    done
    ufw --force enable >/dev/null 2>&1

    log_ok "Открыты порты: 22, 80, 443, 3478, 5349, 49152-49252"
}

# ════════════════════════════════════════
#  ЧТЕНИЕ / ЗАПИСЬ .ENV
# ════════════════════════════════════════
load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        chmod 600 "$ENV_FILE"
        set -a
        # Файл создаётся только этим скриптом, принадлежит root и имеет режим 0600.
        source "$ENV_FILE"
        set +a
        SERVER_NAME="${SERVER_NAME:-${DOMAIN:-}}"
        DOMAIN="${DOMAIN:-$SERVER_NAME}"
        ADMIN_EMAIL="${ADMIN_EMAIL:-admin@$DOMAIN}"
        MAS_DB_PASSWORD="${MAS_DB_PASSWORD:-${DB_PASSWORD:-}}"
        REGISTRATION_MODE="${REGISTRATION_MODE:-closed}"
        FEDERATION_MODE="${FEDERATION_MODE:-restricted}"
        MAX_UPLOAD_SIZE="${MAX_UPLOAD_SIZE:-2048M}"
        REMOTE_MEDIA_LIFETIME="${REMOTE_MEDIA_LIFETIME:-14d}"
        PRESENCE_ENABLED="${PRESENCE_ENABLED:-false}"
        PROXY_ENABLED="${PROXY_ENABLED:-false}"
        CONTAINER_PROXY_URL="${CONTAINER_PROXY_URL:-}"
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
        echo "# MATRIX SERVER ENVIRONMENT — generated by Install-Matrix v4.0"
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
        printf 'FEDERATION_MODE=%q\n' "${FEDERATION_MODE:-restricted}"
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
      test: ["CMD-SHELL", "wget -q --tries=1 http://localhost:80/v1/health -O - | grep -q true"]
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

media_retention:
  remote_media_lifetime: $REMOTE_MEDIA_LIFETIME

user_directory:
  enabled: true
  search_all_users: true
  prefer_local_users: true
  exclude_remote_users: false

presence:
  enabled: $PRESENCE_ENABLED

limit_remote_rooms:
  enabled: true
  complexity: 15.0
  complexity_error: "Этот сервер не может подключаться к настолько большой или сложной комнате."
  admins_can_join: false

registration_shared_secret: "$REG_SHARED_SECRET"
report_stats: false
EOF

    # Безопасная регистрация. Открытая регистрация без проверки намеренно не поддерживается.
    if [[ "$has_mas" == "true" ]]; then
        echo "enable_registration: false" >> "$HOMESERVER_FILE"
        echo "enable_registration_without_verification: false" >> "$HOMESERVER_FILE"
    elif [[ "$REGISTRATION_MODE" == "token" ]]; then
        echo "enable_registration: true" >> "$HOMESERVER_FILE"
        echo "registration_requires_token: true" >> "$HOMESERVER_FILE"
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
EOF
    fi

    if [[ "$has_livekit" == "true" ]]; then
        cat >> "$HOMESERVER_FILE" <<EOF

experimental_features:
  msc3266_enabled: true
  msc4143_enabled: true
  msc4222_enabled: true

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

    chown 991:991 "$(dirname "$HOMESERVER_FILE")" "$HOMESERVER_FILE"
    chmod 750 "$(dirname "$HOMESERVER_FILE")"
    chmod 640 "$HOMESERVER_FILE"
    log_ok "homeserver.yaml сгенерирован"
}

# ════════════════════════════════════════
#  УСТАНОВКА MATRIX (пункт 1)
# ════════════════════════════════════════
install_matrix() {
    log_step "Установка Matrix (базовая)"

    # Повторный запуск не должен менять секреты уже созданной базы данных.
    if [[ -f "$ENV_FILE" && -f "$MATRIX_DIR/data/postgres/PG_VERSION" ]]; then
        load_env
        detect_components

        cd "$MATRIX_DIR"
        generate_compose "$HAS_MAS" "$HAS_LIVEKIT" "$HAS_KETESA" "$HAS_ELEMENT_ADMIN" "$HAS_NTFY"
        generate_homeserver "$HAS_MAS" "$HAS_LIVEKIT"
        configure_well_known "$HAS_LIVEKIT"
        update_nginx_http2_config "/etc/nginx/sites-available/matrix-${DOMAIN}.conf"
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
        log_ok "Matrix уже установлен; конфигурация проверена без смены секретов"
        return
    fi

    # Запрос данных
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
    echo -e "  ${DIM}Регистрация: 1 — закрытая (рекомендуется), 2 — только по токену${NC}"
    echo -ne "  ${CYAN}▶${NC}  Режим [1]: "
    read -r REG_CHOICE
    [[ "$REG_CHOICE" == "2" ]] && REGISTRATION_MODE="token" || REGISTRATION_MODE="closed"
    # Безопасный режим по умолчанию: исходящая федерация закрыта до явного
    # добавления доменов через меню или включения публичного режима.
    FEDERATION_MODE="restricted"
    MAX_UPLOAD_SIZE="2048M"
    REMOTE_MEDIA_LIFETIME="14d"
    PRESENCE_ENABLED="false"
    PROXY_ENABLED="false"
    CONTAINER_PROXY_URL=""
    set_image_defaults

    echo ""
    echo -e "  ${DIM}Пароль PostgreSQL (Enter = автогенерация):${NC}"
    echo -ne "  ${CYAN}▶${NC}  "
    read -rs DB_PASSWORD
    echo ""

    if [[ -z "$DB_PASSWORD" ]]; then
        DB_PASSWORD=$(generate_secret 24)
        log_ok "Пароль БД сгенерирован: ${CYAN}$DB_PASSWORD${NC}"
    else
        [[ "$DB_PASSWORD" =~ ^[A-Za-z0-9._~-]{12,128}$ ]] \
            || log_error "Ручной пароль БД: 12–128 символов A-Z, a-z, 0-9, точка, _, ~ или -"
        log_ok "Пароль БД задан вручную"
    fi

    # Внешний IP
    EXTERNAL_IP=$(curl -4 -s --max-time 5 https://ifconfig.me 2>/dev/null \
               || curl -4 -s --max-time 5 https://api.ipify.org 2>/dev/null)
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
    chmod 644 data/coturn/tls/turn_server_cert.pem
    chmod 600 data/coturn/tls/turn_server_pkey.pem
    install_certbot_deploy_hook
    log_ok "Сертификаты скопированы для Coturn"

    # Nginx для основного домена
    set_nginx_http2_syntax
    NGINX_CONF="/etc/nginx/sites-available/matrix-${DOMAIN}.conf"
    configure_well_known false
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
    systemctl start nginx
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
    log_step "Создание администратора"
    echo ""
    echo -e "  ${DIM}Введите данные для первого аккаунта:${NC}"
    echo ""
    docker compose exec synapse register_new_matrix_user \
        http://localhost:8008 -c /data/homeserver.yaml --admin

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
    echo -e "${BGREEN}  ║${NC}  ${YELLOW}Пароль БД:${NC}    ${WHITE}$DB_PASSWORD                                           ║${NC}"
    echo -e "${BGREEN}  ║${NC}  ${YELLOW}Секрет TURN:${NC}  ${WHITE}$TURN_SECRET                                           ║${NC}"
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

    MIGRATION_MARKER="$MATRIX_DIR/data/mas/.syn2mas-complete"
    if [[ -n "${MAS_DOMAIN:-}" && -n "${MAS_SECRET:-}" \
          && -f "$MATRIX_DIR/data/mas/config.yaml" \
          && -f "$MIGRATION_MARKER" ]]; then
        detect_components
        cd "$MATRIX_DIR"
        generate_compose true "$HAS_LIVEKIT" "$HAS_KETESA" "$HAS_ELEMENT_ADMIN" "$HAS_NTFY"
        generate_homeserver true "$HAS_LIVEKIT"
        configure_well_known "$HAS_LIVEKIT"
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
        echo ""
        MAS_DOMAIN=$(read_domain "Домен MAS" "mas.$SERVER_NAME")
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
  password_registration_enabled: true
  password_registration_email_required: false
  password_registration_token_required: true
  password_change_allowed: true
  password_recovery_enabled: false
EOF
        log_ok "Конфиг MAS создан"
        # MAS runs as an unprivileged container user and reads this bind mount.
        chmod 0644 "$MATRIX_DIR/data/mas/config.yaml"
        chmod 0755 "$MATRIX_DIR/data/mas"
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
            >/tmp/syn2mas-check.log 2>&1
        SYN2MAS_CHECK_STATUS=$?
        set -e
        if [[ $SYN2MAS_CHECK_STATUS -ne 0 && $SYN2MAS_CHECK_STATUS -ne 11 ]]; then
            tail -50 /tmp/syn2mas-check.log
            log_error "Проверка syn2mas завершилась ошибкой"
        fi
        if [[ $SYN2MAS_CHECK_STATUS -eq 11 ]]; then
            log_warn "syn2mas сообщил предупреждения; регистрация Synapse будет отключена перед миграцией"
        else
            log_ok "Проверка syn2mas пройдена"
        fi

        docker compose stop synapse >/dev/null 2>&1 || true
        generate_homeserver true false

        set +e
        docker compose run --rm --no-deps mas \
            --config /app/config/config.yaml syn2mas migrate \
            --synapse-config /data/synapse/homeserver.yaml \
            --synapse-database-uri "postgresql://synapse:${DB_PASSWORD:-}@postgres:5432/synapse" \
            >/tmp/syn2mas-migrate.log 2>&1
        SYN2MAS_MIGRATE_STATUS=$?
        set -e
        if [[ $SYN2MAS_MIGRATE_STATUS -ne 0 && $SYN2MAS_MIGRATE_STATUS -ne 11 ]]; then
            tail -50 /tmp/syn2mas-migrate.log
            cp "$BACKUP_DIR/homeserver.yaml" "$HOMESERVER_FILE"
            chown 991:991 "$HOMESERVER_FILE"
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

    LIVEKIT_ALREADY_INSTALLED=false
    if [[ -n "${LIVEKIT_DOMAIN:-}" && -n "${LIVEKIT_KEY:-}" \
          && -n "${LIVEKIT_SECRET:-}" \
          && -f "$MATRIX_DIR/data/livekit/livekit.yaml" ]]; then
        LIVEKIT_ALREADY_INSTALLED=true
        log_ok "LiveKit уже установлен; существующие API-ключи будут сохранены"
    else
        # Запрос домена для LiveKit
        echo ""
        LIVEKIT_DOMAIN=$(read_domain "Домен LiveKit" "livekit.$SERVER_NAME")
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
  port_range_start: 50000
  port_range_end: 50100
  use_external_ip: true
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
    for old_rule in "8008/tcp" "8448/tcp" "7880/tcp"; do
        ufw --force delete allow "$old_rule" >/dev/null 2>&1 || true
    done
    for rule in "7881/tcp" "50000:50100/udp"; do
        ufw allow "$rule" >/dev/null 2>&1
    done
    log_ok "Открыты медиапорты 7881/tcp и 50000-50100/udp"

    # Перегенерируем compose и homeserver с включенным LiveKit
    cd "$MATRIX_DIR"
    detect_components
    generate_compose true true "$HAS_KETESA" "$HAS_ELEMENT_ADMIN" "$HAS_NTFY"
    generate_homeserver true true
    configure_well_known true

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
    configure_well_known "$HAS_LIVEKIT"
}

apply_synapse_config() {
    local backup_file
    backup_file=$(mktemp "$MATRIX_DIR/data/synapse/homeserver.yaml.rollback.XXXXXX")
    cp "$HOMESERVER_FILE" "$backup_file"
    regenerate_stack

    if ! docker compose -f "$COMPOSE_FILE" config --quiet >/tmp/matrix-compose-check.log 2>&1; then
        cp "$backup_file" "$HOMESERVER_FILE"
        rm -f "$backup_file"
        tail -30 /tmp/matrix-compose-check.log
        log_error "Новый docker-compose.yml некорректен; homeserver.yaml восстановлен"
    fi

    if ! docker compose -f "$COMPOSE_FILE" up -d synapse >/tmp/matrix-synapse-apply.log 2>&1; then
        cp "$backup_file" "$HOMESERVER_FILE"
        docker compose -f "$COMPOSE_FILE" restart synapse >/dev/null 2>&1 || true
        rm -f "$backup_file"
        tail -30 /tmp/matrix-synapse-apply.log
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
    regenerate_stack
    docker compose config --quiet || log_error "Ошибка docker-compose после добавления Element Admin"
    write_proxy_vhost "element-admin" "$ELEMENT_ADMIN_DOMAIN" 8084 false
    run_spinner "Запуск Element Admin и MAS" docker compose up -d mas element-admin
    wait_for_url "https://$ELEMENT_ADMIN_DOMAIN/" "Element Admin"
    log_ok "Element Admin доступен: https://$ELEMENT_ADMIN_DOMAIN"
}

install_ntfy() {
    log_step "Установка ntfy (UnifiedPush)"
    require_matrix
    local ntfy_new="false"
    local ntfy_password=""
    if [[ -n "${NTFY_DOMAIN:-}" ]]; then
        log_warn "ntfy уже настроен; проверяю и восстанавливаю сервис"
    else
        ntfy_new="true"
        NTFY_DOMAIN=$(read_domain "Домен ntfy" "ntfy.$SERVER_NAME")
        echo -ne "  ${CYAN}▶${NC}  Имя администратора ntfy [admin]: "
        read -r NTFY_ADMIN_USER
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
        if ! docker compose exec -T ntfy ntfy user list 2>/dev/null \
            | grep -Fq "$NTFY_ADMIN_USER"; then
            log_warn "Сохранённый пользователь ntfy не найден; будет создан новый пароль"
            ntfy_password=$(generate_secret 24)
            ntfy_new="true"
        fi
    fi
    if [[ "$ntfy_new" == "true" ]]; then
        if ! docker compose exec -T -e "NTFY_PASSWORD=$ntfy_password" ntfy \
            ntfy user add --role=admin "$NTFY_ADMIN_USER" >/tmp/ntfy-user.log 2>&1; then
            tail -20 /tmp/ntfy-user.log
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
        bash -c "docker compose exec -T postgres pg_dump -U synapse -d synapse -Fc > '$backup_dir/synapse.dump'"
    if [[ "$HAS_MAS" == "true" ]]; then
        run_spinner "Дамп базы MAS" \
            bash -c "docker compose exec -T mas-db pg_dump -U mas_user -d mas -Fc > '$backup_dir/mas.dump'"
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
    sha256sum "$backup_dir"/* > "$backup_dir/SHA256SUMS"
    chmod -R go-rwx "$backup_dir"
    log_ok "Резервная копия создана: $backup_dir"
    log_warn "Медиа-файлы не включены; каталог media_store следует копировать отдельно"
}

run_diagnostics() {
    log_step "Диагностика Matrix-стека"
    require_matrix
    cd "$MATRIX_DIR"
    local failures=0
    docker compose config --quiet && log_ok "docker-compose.yml корректен" \
        || { log_warn "docker-compose.yml содержит ошибку"; failures=$((failures + 1)); }
    nginx -t >/dev/null 2>&1 && log_ok "Nginx-конфигурация корректна" \
        || { log_warn "Nginx-конфигурация содержит ошибку"; failures=$((failures + 1)); }
    curl -fsS --max-time 15 "https://$DOMAIN/_matrix/client/versions" >/dev/null \
        && log_ok "Matrix Client API отвечает" \
        || { log_warn "Matrix Client API не отвечает"; failures=$((failures + 1)); }
    curl -fsS --max-time 15 "https://$SERVER_NAME/.well-known/matrix/server" \
        | jq -e '."m.server"' >/dev/null \
        && log_ok "server delegation работает" \
        || { log_warn "server delegation не работает"; failures=$((failures + 1)); }
    curl -fsS --max-time 15 "https://$SERVER_NAME/.well-known/matrix/client" \
        | jq -e '."m.homeserver".base_url' >/dev/null \
        && log_ok "client discovery работает" \
        || { log_warn "client discovery не работает"; failures=$((failures + 1)); }
    if [[ "$HAS_MAS" == "true" ]]; then
        docker compose exec -T mas mas-cli --config /app/config/config.yaml doctor >/tmp/mas-doctor.log 2>&1 \
            && log_ok "MAS doctor не нашёл критических ошибок" \
            || { log_warn "MAS doctor сообщил об ошибке (см. /tmp/mas-doctor.log)"; failures=$((failures + 1)); }
    fi
    docker compose ps
    [[ $failures -eq 0 ]] && log_ok "Все проверки пройдены" \
        || log_warn "Не пройдено проверок: $failures"
    return "$failures"
}

update_services() {
    log_step "Обновление контейнеров"
    require_matrix
    create_backup
    cd "$MATRIX_DIR"
    regenerate_stack
    run_spinner "Загрузка закреплённых образов" docker compose pull
    run_spinner "Пересоздание контейнеров" docker compose up -d --remove-orphans
    run_diagnostics
}

configure_registration() {
    log_step "Режим регистрации"
    require_matrix
    if [[ "$HAS_MAS" == "true" ]]; then
        log_warn "Регистрацией управляет MAS: регистрация по паролю включена только с токеном"
        echo "  Токены создаются средствами MAS; открытая регистрация без проверки отключена."
        return
    fi
    echo "  1) Закрытая регистрация (рекомендуется)"
    echo "  2) Регистрация только по токену Synapse"
    echo -ne "  ${CYAN}▶${NC}  Выбор: "
    local registration_choice
    read -r registration_choice
    case "$registration_choice" in
        1) REGISTRATION_MODE="closed" ;;
        2) REGISTRATION_MODE="token" ;;
        *) log_error "Неверный выбор" ;;
    esac
    save_env
    cd "$MATRIX_DIR"
    apply_synapse_config
    log_ok "Режим регистрации: $REGISTRATION_MODE"
}

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
        https://github.com/XTLS/Xray-install/raw/main/install-release.sh \
        -o "$install_script"
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
    log_ok "Xray настроен; Docker и контейнеры используют HTTP-прокси 10809"
}

# ════════════════════════════════════════
#  МЕНЮ
# ════════════════════════════════════════
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
    echo -e "     ${DIM}Ubuntu 20.04+ · Debian 11+  ·  version 4.0${NC}"
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
        0) echo -e "  ${GREEN}Выход.${NC}"; exit 0 ;;
        *) echo -e "  ${RED}Неверный выбор.${NC}"; sleep 1 ;;
    esac
}

# ════════════════════════════════════════
#  ЗАПУСК
# ════════════════════════════════════════
if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" \
      || "${BASH_SOURCE[0]}" == "/dev/stdin" ]]; then
    check_system
    while true; do
        show_menu
        echo ""
        echo -ne "  ${DIM}Нажмите Enter для возврата в меню...${NC}"
        read -r
    done
fi
