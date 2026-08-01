#!/bin/bash

# ============================================================
#  MATRIX SERVER INSTALLER v3.1
#  by zxchubbabubba
#  Ubuntu 20.04 / 22.04 / 24.04
#  Меню: Matrix, MAS, LiveKit (с исправлением Nginx)
# ============================================================

set -e

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
        exit 1
    fi

    printf "\r  ${BGREEN}✓${NC}  ${WHITE}%s${NC}                    \n" "$msg"
}

generate_secret() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-"${1:-32}"
}

# ════════════════════════════════════════
#  ПРОВЕРКА СИСТЕМЫ
# ════════════════════════════════════════
check_system() {
    [[ $EUID -ne 0 ]] && log_error "Запустите от root: sudo ./install-matrix.sh"

    if ! command -v lsb_release &>/dev/null; then
        log_error "lsb_release не найден. Только Ubuntu/Debian."
    fi

    OS_VERSION=$(lsb_release -rs | cut -d. -f1)
    [[ "$OS_VERSION" -lt 20 ]] && log_error "Требуется Ubuntu 20.04 или новее."
    log_ok "ОС: Ubuntu $OS_VERSION"
}

# ════════════════════════════════════════
#  УСТАНОВКА БАЗОВЫХ ПАКЕТОВ
# ════════════════════════════════════════
install_base_packages() {
    log_step "Установка базовых пакетов"

    run_spinner "Обновление списка пакетов" \
        apt-get update -qq

    run_spinner "Установка nginx, certbot, docker, ufw" \
        apt-get install -y -qq \
            apt-transport-https ca-certificates curl software-properties-common \
            nginx certbot python3-certbot-nginx ufw git docker.io docker-compose-v2

    run_spinner "Запуск Docker" \
        bash -c "systemctl enable docker && systemctl start docker"

    if ! docker compose version &>/dev/null; then
        log_error "docker compose v2 не найден"
    fi
    log_ok "Docker Compose готов"
}

# ════════════════════════════════════════
#  ПОЛУЧЕНИЕ SSL СЕРТИФИКАТА (исправлено)
# ════════════════════════════════════════
get_ssl_cert() {
    local domain="$1"
    log_step "SSL сертификат для $domain"

    systemctl stop nginx 2>/dev/null || true
    run_spinner "Получение сертификата для $domain" \
        certbot certonly --standalone -d "$domain" \
            --non-interactive --agree-tos \
            --email "admin@$domain" --no-eff-email

    CERT_EXPIRY=$(openssl x509 -noout -enddate \
        -in "/etc/letsencrypt/live/$domain/fullchain.pem" 2>/dev/null | cut -d= -f2)
    log_ok "Сертификат получен, действует до: ${CYAN}$CERT_EXPIRY${NC}"

    # Запускаем nginx обратно, чтобы он был доступен для дальнейших операций
    systemctl start nginx
}

# ════════════════════════════════════════
#  НАСТРОЙКА UFW
# ════════════════════════════════════════
setup_ufw() {
    log_step "Брандмауэр (UFW)"

    for rule in \
        "22/tcp" "80/tcp" "443/tcp" \
        "8008/tcp" "8448/tcp" \
        "3478/tcp" "3478/udp" \
        "5349/tcp" "5349/udp" \
        "49152:49252/udp"
    do
        ufw allow "$rule" >/dev/null 2>&1
    done
    ufw --force enable >/dev/null 2>&1

    log_ok "Открыты порты: 22, 80, 443, 8008, 8448, 3478, 5349, 49152-49252"
}

# ════════════════════════════════════════
#  ЧТЕНИЕ / ЗАПИСЬ .ENV
# ════════════════════════════════════════
load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        set -a
        source "$ENV_FILE"
        set +a
    else
        log_error "Файл .env не найден. Сначала установите Matrix (пункт 1)."
    fi
}

save_env() {
    mkdir -p "$MATRIX_DIR"
    cat > "$ENV_FILE" <<EOF
# MATRIX SERVER ENVIRONMENT
DOMAIN=$DOMAIN
EXTERNAL_IP=$EXTERNAL_IP
DB_PASSWORD=$DB_PASSWORD
REG_SHARED_SECRET=$REG_SHARED_SECRET
MACAROON_SECRET=$MACAROON_SECRET
FORM_SECRET=$FORM_SECRET
TURN_SECRET=$TURN_SECRET
MAS_DOMAIN=$MAS_DOMAIN
MAS_SECRET=$MAS_SECRET
LIVEKIT_DOMAIN=$LIVEKIT_DOMAIN
LIVEKIT_KEY=$LIVEKIT_KEY
LIVEKIT_SECRET=$LIVEKIT_SECRET
EOF
}

# ════════════════════════════════════════
#  ГЕНЕРАЦИЯ DOCKER-COMPOSE.YML
# ════════════════════════════════════════
generate_compose() {
    local has_mas="${1:-false}"
    local has_livekit="${2:-false}"

    cat > "$COMPOSE_FILE" <<EOF
services:
  postgres:
    image: postgres:16-alpine
    container_name: matrix-postgres
    restart: unless-stopped
    volumes:
      - ./data/postgres:/var/lib/postgresql/data
    environment:
      POSTGRES_USER: synapse
      POSTGRES_PASSWORD: $DB_PASSWORD
      POSTGRES_DB: synapse
    networks:
      - matrix

  synapse:
    image: ghcr.io/element-hq/synapse:latest
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
      - "8008:8008"
      - "8448:8448"
    volumes:
      - ./data/synapse:/data
    environment:
      SYNAPSE_SERVER_NAME: $DOMAIN
      SYNAPSE_REPORT_STATS: "no"
    networks:
      - matrix

  coturn:
    image: coturn/coturn:latest
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
    image: postgres:16-alpine
    container_name: mas-db
    restart: unless-stopped
    volumes:
      - ./data/mas-db:/var/lib/postgresql/data
    environment:
      POSTGRES_USER: mas_user
      POSTGRES_PASSWORD: $DB_PASSWORD
      POSTGRES_DB: mas
    networks:
      - matrix

  mas:
    image: ghcr.io/element-hq/matrix-authentication-service:latest
    container_name: matrix-mas
    restart: unless-stopped
    depends_on:
      - mas-db
    ports:
      - "8080:8080"
    volumes:
      - ./data/mas/config.yaml:/app/config/config.yaml:ro
    environment:
      - MAS_CONFIG=/app/config/config.yaml
    networks:
      - matrix
EOF
    fi

    if [[ "$has_livekit" == "true" ]]; then
        cat >> "$COMPOSE_FILE" <<EOF

  livekit:
    image: livekit/livekit-server:latest
    container_name: matrix-livekit
    restart: unless-stopped
    network_mode: host
    command: --config /etc/livekit.yaml
    volumes:
      - ./data/livekit/livekit.yaml:/etc/livekit.yaml:ro

  lk-jwt-service:
    image: ghcr.io/element-hq/lk-jwt-service:latest
    container_name: matrix-lk-jwt
    restart: unless-stopped
    depends_on:
      - mas
    ports:
      - "8082:8080"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      - LIVEKIT_URL=wss://$LIVEKIT_DOMAIN
      - LIVEKIT_KEY=$LIVEKIT_KEY
      - LIVEKIT_SECRET=$LIVEKIT_SECRET
      - LIVEKIT_FULL_ACCESS_HOMESERVERS=$DOMAIN
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
server_name: "$DOMAIN"
pid_file: /data/homeserver.pid

listeners:
  - port: 8008
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

registration_shared_secret: "$REG_SHARED_SECRET"
report_stats: false
enable_registration: true
enable_registration_without_verification: true
suppress_key_server_warning: true
federation_domain_whitelist: []

macaroon_secret_key: "$MACAROON_SECRET"
form_secret: "$FORM_SECRET"
signing_key_path: "/data/${DOMAIN}.signing.key"

trusted_key_servers:
  - server_name: "matrix.org"

public_baseurl: https://$DOMAIN/

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
  msc4222_enabled: true

extra_well_known_client_content:
  org.matrix.msc4143.rtc_foci:
    - type: livekit
      livekit_service_url: "https://$DOMAIN/lk-jwt"
EOF
    fi

    chown -R 991:991 "$(dirname "$HOMESERVER_FILE")"
    chmod 750 "$(dirname "$HOMESERVER_FILE")"
    log_ok "homeserver.yaml сгенерирован"
}

# ════════════════════════════════════════
#  УСТАНОВКА MATRIX (пункт 1)
# ════════════════════════════════════════
install_matrix() {
    log_step "Установка Matrix (базовая)"

    # Запрос данных
    echo ""
    echo -e "  ${DIM}Домен для Matrix (например: matrix.example.com)${NC}"
    echo -ne "  ${CYAN}▶${NC}  "
    read -r DOMAIN
    DOMAIN=$(echo "$DOMAIN" | xargs)
    [[ -z "$DOMAIN" ]] && log_error "Домен обязателен."

    echo ""
    echo -e "  ${DIM}Пароль PostgreSQL (Enter = автогенерация):${NC}"
    echo -ne "  ${CYAN}▶${NC}  "
    read -rs DB_PASSWORD
    echo ""

    if [[ -z "$DB_PASSWORD" ]]; then
        DB_PASSWORD=$(generate_secret 24)
        log_ok "Пароль БД сгенерирован: ${CYAN}$DB_PASSWORD${NC}"
    else
        log_ok "Пароль БД задан вручную"
    fi

    # Внешний IP
    EXTERNAL_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null \
               || curl -s --max-time 5 api.ipify.org 2>/dev/null)
    [[ -z "$EXTERNAL_IP" ]] && log_error "Не удалось определить внешний IP."
    log_ok "Внешний IP: ${CYAN}$EXTERNAL_IP${NC}"

    # Проверка DNS
    if command -v dig &>/dev/null; then
        RESOLVED_IP=$(dig +short "$DOMAIN" 2>/dev/null | head -1)
        if [[ -n "$RESOLVED_IP" && "$RESOLVED_IP" != "$EXTERNAL_IP" ]]; then
            log_warn "Домен $DOMAIN → $RESOLVED_IP, IP сервера: $EXTERNAL_IP"
            echo -ne "  ${YELLOW}Продолжить? [y/N]:${NC}  "
            read -r CONTINUE
            [[ "$CONTINUE" != "y" && "$CONTINUE" != "Y" ]] && log_error "Установка прервана."
        else
            log_ok "DNS: ${CYAN}$DOMAIN${NC} → ${CYAN}$EXTERNAL_IP${NC}"
        fi
    fi

    # Генерация секретов
    REG_SHARED_SECRET=$(generate_secret 32)
    MACAROON_SECRET=$(generate_secret 32)
    FORM_SECRET=$(generate_secret 32)
    TURN_SECRET=$(openssl rand -hex 32)

    log_ok "Секреты сгенерированы"

    # Установка пакетов
    install_base_packages

    # Создание структуры
    mkdir -p "$MATRIX_DIR"/data/{postgres,synapse,coturn/tls}
    cd "$MATRIX_DIR"

    # Сохраняем переменные
    save_env

    # Генерация compose и homeserver (без MAS и LiveKit)
    generate_compose false false
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

    # Копирование сертификатов для Coturn
    cp /etc/letsencrypt/live/"$DOMAIN"/fullchain.pem data/coturn/tls/turn_server_cert.pem
    cp /etc/letsencrypt/live/"$DOMAIN"/privkey.pem   data/coturn/tls/turn_server_pkey.pem
    chmod 644 data/coturn/tls/*.pem
    log_ok "Сертификаты скопированы для Coturn"

    # Nginx для основного домена
    NGINX_CONF="/etc/nginx/sites-available/matrix-${DOMAIN}.conf"
    cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name $DOMAIN;

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
Domain:      https://$DOMAIN

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
    echo -e "${BGREEN}  ║                                 УСТАНОВКА MATRIX ЗАВЕРШЕНА!                                     ║${NC}"
    echo -e "${BGREEN}  ║                                                                                                  ║${NC}"
    echo -e "${BGREEN}  ╠══════════════════════════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BGREEN}  ║                                                                                                  ║${NC}"
    echo -e "${BGREEN}  ║${NC}  ${WHITE}Сервер:${NC}       ${CYAN}https://$DOMAIN${NC}                                     ║${NC}"
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

    # Запрос домена для MAS
    echo ""
    echo -e "  ${DIM}Домен для MAS (например, mas.$DOMAIN)${NC}"
    echo -ne "  ${CYAN}▶${NC}  "
    read -r MAS_DOMAIN
    MAS_DOMAIN=$(echo "$MAS_DOMAIN" | xargs)
    if [[ -z "$MAS_DOMAIN" ]]; then
        MAS_DOMAIN="mas.$DOMAIN"
        log_ok "Используем поддомен: ${CYAN}$MAS_DOMAIN${NC}"
    else
        log_ok "Домен MAS: ${CYAN}$MAS_DOMAIN${NC}"
    fi

    # Генерация секрета для связи с Synapse
    MAS_SECRET=$(generate_secret 32)
    log_ok "Секрет для MAS сгенерирован"

    # Генерация ключей для MAS (encryption и подписи)
    ENCRYPTION_SECRET=$(openssl rand -hex 32)
    # Генерируем RSA ключ
    RSA_KEY=$(openssl genrsa 2048 2>/dev/null)
    # Генерируем EC ключи
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
  uri: postgresql://mas_user:$DB_PASSWORD@mas-db:5432/mas
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
      $RSA_KEY
  - key: |
      $EC_KEY1
  - key: |
      $EC_KEY2
  - key: |
      $EC_KEY3
passwords:
  enabled: true
  schemes:
  - version: 1
    algorithm: bcrypt
  - version: 2
    algorithm: argon2id
  minimum_complexity: 3
matrix:
  kind: synapse
  homeserver: $DOMAIN
  secret: $MAS_SECRET
  endpoint: http://synapse:8008/
registration:
  enabled: true
  allow_username: true
  allow_email: false
  allow_guest: false
account:
  password_registration_enabled: true
  password_registration_email_required: false
registration:
  enabled: true
  allow_username: true
  allow_email: false
  allow_guest: false
EOF
    log_ok "Конфиг MAS создан"

    # Получение SSL для MAS
    get_ssl_cert "$MAS_DOMAIN"

    # Настройка Nginx для MAS
    NGINX_MAS_CONF="/etc/nginx/sites-available/mas-${MAS_DOMAIN}.conf"
    cat > "$NGINX_MAS_CONF" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $MAS_DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
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
    nginx -t >/dev/null 2>&1 || log_error "Ошибка конфигурации Nginx для MAS"
    systemctl reload nginx
    log_ok "Nginx для MAS настроен"

    # Перегенерируем compose и homeserver с включенным MAS
    cd "$MATRIX_DIR"
    generate_compose true false
    generate_homeserver true false

    # Перезапуск сервисов
    log_step "Перезапуск сервисов с MAS"
    run_spinner "Запуск обновлённого стека" \
        docker compose up -d

    log_ok "MAS установлен и интегрирован"
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

    # Запрос домена для LiveKit
    echo ""
    echo -e "  ${DIM}Домен для LiveKit (например, livekit.$DOMAIN)${NC}"
    echo -ne "  ${CYAN}▶${NC}  "
    read -r LIVEKIT_DOMAIN
    LIVEKIT_DOMAIN=$(echo "$LIVEKIT_DOMAIN" | xargs)
    if [[ -z "$LIVEKIT_DOMAIN" ]]; then
        LIVEKIT_DOMAIN="livekit.$DOMAIN"
        log_ok "Используем поддомен: ${CYAN}$LIVEKIT_DOMAIN${NC}"
    else
        log_ok "Домен LiveKit: ${CYAN}$LIVEKIT_DOMAIN${NC}"
    fi

    # Генерация ключей LiveKit
    LIVEKIT_KEY=$(generate_secret 64)
    LIVEKIT_SECRET=$(generate_secret 64)
    log_ok "Ключи LiveKit сгенерированы"

    # Сохраняем в .env
    save_env

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
logging:
  level: info
EOF
    log_ok "Конфиг LiveKit создан"

    # Получение SSL для LiveKit
    get_ssl_cert "$LIVEKIT_DOMAIN"

    # Настройка Nginx для LiveKit
    NGINX_LIVEKIT_CONF="/etc/nginx/sites-available/livekit-${LIVEKIT_DOMAIN}.conf"
    cat > "$NGINX_LIVEKIT_CONF" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $LIVEKIT_DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
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

    # Открываем порты для LiveKit (UDP для медиа, TCP для WebSocket)
    log_step "Открытие портов для LiveKit"
    for rule in "7880/tcp" "7881/tcp" "50000:50100/udp"; do
        ufw allow "$rule" >/dev/null 2>&1
    done
    log_ok "Открыты порты 7880, 7881, 50000-50100"

    # Перегенерируем compose и homeserver с включенным LiveKit
    cd "$MATRIX_DIR"
    generate_compose true true
    generate_homeserver true true

    # Добавляем location /lk-jwt на основном домене для lk-jwt-service
    # Проверим, не добавлен ли уже
    MAIN_NGINX="/etc/nginx/sites-available/matrix-${DOMAIN}.conf"
    if ! grep -q "location /lk-jwt" "$MAIN_NGINX"; then
        # Вставляем location перед последней строкой ssl_certificate
        sed -i '/ssl_certificate/i \ \n    location /lk-jwt {\n        proxy_pass http://127.0.0.1:8082;\n        proxy_http_version 1.1;\n        proxy_set_header Host \$host;\n        proxy_set_header X-Real-IP \$remote_addr;\n        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\n        proxy_set_header X-Forwarded-Proto \$scheme;\n        proxy_set_header Upgrade \$http_upgrade;\n        proxy_set_header Connection "upgrade";\n        proxy_buffering off;\n    }\n' "$MAIN_NGINX"
        nginx -t >/dev/null 2>&1 || log_error "Ошибка добавления /lk-jwt в Nginx"
        systemctl reload nginx
        log_ok "Добавлен прокси /lk-jwt на основной домен"
    else
        log_ok "/lk-jwt уже существует"
    fi

    # Перезапуск сервисов
    log_step "Перезапуск сервисов с LiveKit"
    run_spinner "Запуск обновлённого стека" \
        docker compose up -d

    log_ok "LiveKit установлен и интегрирован"
}

# ════════════════════════════════════════
#  МЕНЮ
# ════════════════════════════════════════
show_menu() {
    clear
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
    echo -e "     ${DIM}Ubuntu 20.04 · 22.04 · 24.04  ·  version 3.1${NC}"
    echo -e "${BRED}  ════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${WHITE}Выберите действие:${NC}"
    echo ""
    echo -e "    ${CYAN}1)${NC}  Установить ${WHITE}Matrix${NC} (Synapse + PostgreSQL + Coturn + Nginx + SSL)"
    echo -e "    ${CYAN}2)${NC}  Установить ${WHITE}MAS${NC} (Matrix Authentication Service) — требуется Matrix"
    echo -e "    ${CYAN}3)${NC}  Установить ${WHITE}LiveKit${NC} (звонки) — требуется Matrix + MAS"
    echo -e "    ${CYAN}0)${NC}  Выход"
    echo ""
    echo -ne "  ${CYAN}▶${NC}  "
    read -r choice
    case "$choice" in
        1) install_matrix ;;
        2) install_mas ;;
        3) install_livekit ;;
        0) echo -e "  ${GREEN}Выход.${NC}"; exit 0 ;;
        *) echo -e "  ${RED}Неверный выбор.${NC}"; sleep 1; show_menu ;;
    esac
}

# ════════════════════════════════════════
#  ЗАПУСК
# ════════════════════════════════════════
check_system
show_menu
