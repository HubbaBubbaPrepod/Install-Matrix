# Install-Matrix

Интерактивный установщик собственного Matrix-сервера для Ubuntu 20.04+ и Debian 11+. Версия 4.0 разворачивает безопасный базовый стек и позволяет отдельно подключать аутентификацию, MatrixRTC, админ-панели, UnifiedPush и исходящий VLESS-прокси.

Element Web и Element Call намеренно не устанавливаются. LiveKit в этом проекте — серверная часть MatrixRTC для совместимых Matrix-клиентов, а не веб-интерфейс Element Call.

## Состав

Базовая установка:

- Synapse с PostgreSQL;
- Coturn;
- Nginx и сертификаты Let's Encrypt;
- UFW;
- корректное разделение `server_name` и публичного Matrix API через `.well-known` delegation.

Опционально:

- Matrix Authentication Service (MAS), включая `syn2mas` и admin API;
- LiveKit и `lk-jwt-service` для MatrixRTC;
- Ketesa Admin;
- Element Admin;
- ntfy как собственный сервер UnifiedPush;
- Xray/VLESS для исходящего HTTP(S)-трафика Docker-контейнеров.

Используются закреплённые версии образов, а не `latest`. Значения можно переопределить в защищённом файле `/root/matrix-server/.env`.

## DNS до установки

Предположим, основной домен — `example.com`, а IP сервера — `203.0.113.10`.

| Назначение | Имя | Тип | Значение | Обязательность |
|---|---|---|---|---|
| Matrix ID (`@user:example.com`) и delegation | `example.com` | `A` | `203.0.113.10` | обязательно |
| Matrix Client/Federation API | `matrix.example.com` | `A` | `203.0.113.10` | обязательно |
| MAS | `mas.example.com` | `A` | `203.0.113.10` | если ставится MAS |
| MatrixRTC/LiveKit | `livekit.example.com` | `A` | `203.0.113.10` | если ставится LiveKit |
| Ketesa Admin | `admin.example.com` | `A` | `203.0.113.10` | если ставится Ketesa |
| Element Admin | `element-admin.example.com` | `A` | `203.0.113.10` | если ставится Element Admin |
| ntfy | `ntfy.example.com` | `A` | `203.0.113.10` | если ставится ntfy |

Можно использовать wildcard `A` для `*.example.com`, но отдельная запись apex-домена `example.com` всё равно нужна. SRV, MX и TXT-записи установщику не требуются.

Важные условия:

- не создавайте `AAAA`, если IPv6 на сервере и в Nginx не настроен полностью;
- если у домена есть CAA, он должен разрешать `letsencrypt.org`;
- на время выпуска сертификатов порты `80/tcp` и `443/tcp` должны вести прямо на сервер, без закрытого proxy/CDN-режима;
- DNS должен успеть обновиться до запуска соответствующего пункта меню.

## Сетевые порты

Открываются базово:

- `22/tcp` — SSH;
- `80/tcp`, `443/tcp` — HTTP/HTTPS, Client API и федерация;
- `3478/tcp+udp`, `5349/tcp+udp`, `49152-49252/udp` — Coturn.

Для LiveKit дополнительно:

- `7881/tcp`;
- `50000-50100/udp`.

Synapse `8008`, MAS `8080`, lk-jwt `8082`, Ketesa `8083`, Element Admin `8084` и ntfy `8090` слушают только `127.0.0.1`. Порт федерации `8448` не нужен: Nginx обслуживает федерацию на `443`.

## Установка

```bash
curl -fsSL https://raw.githubusercontent.com/HubbaBubbaPrepod/Install-Matrix/refs/heads/main/install-matrix.sh -o install-matrix.sh
chmod +x install-matrix.sh
sudo ./install-matrix.sh
```

Скрипт создаёт установку в `/root/matrix-server`.

## Меню

1. Установить или восстановить Matrix.
2. Установить MAS.
3. Установить LiveKit/MatrixRTC без Element Call.
4. Добавить федеративный домен в ограниченный allowlist.
5. Просмотреть/изменить режим федерации.
6. Установить Ketesa Admin.
7. Установить Element Admin (требует MAS).
8. Установить ntfy.
9. Настроить Xray по VLESS URI.
10. Настроить регистрацию.
11. Создать резервную копию.
12. Запустить диагностику.
13. Обновить контейнеры с предварительным backup.

### Федерация

По умолчанию исходящая федерация закрыта: новый сервер не связывается с внешними Matrix-серверами. Пункт «Добавить федерацию» принимает как домен (`matrix.org`), так и Matrix ID (`@alice:matrix.org`), извлекает домен и безопасно перезапускает Synapse. Отдельный пункт меню позволяет явно включить публичный режим.

В restricted-режиме `federation_domain_whitelist` ограничивает исходящие федеративные соединения. Пустой allowlist блокирует их полностью. В меню можно удалить домен или вернуться в публичный режим; при ошибке запуска `homeserver.yaml` откатывается.

### Регистрация

Открытая регистрация без проверки не поддерживается. Для Synapse доступны закрытый режим и регистрация по токену. После установки MAS регистрацией управляет MAS, а парольная регистрация требует токен.

### Админ-панели

Ketesa — лёгкая панель, ограниченная URL текущего homeserver. Element Admin требует MAS и включённый MAS admin API. Обе панели устанавливаются отдельно и не включают Element Web.

### ntfy

ntfy разворачивается с закрытым доступом и отдельным администратором. Это endpoint для клиентов, поддерживающих UnifiedPush; он не заменяет push gateway автоматически для любого Matrix-клиента.

### Xray

Пункт Xray принимает VLESS URI, строит конфигурацию Xray, проверяет её и настраивает HTTP-прокси для Docker daemon и контейнеров. Частные адреса и российские назначения направляются напрямую, остальные — через VLESS. Сама VLESS-ссылка не сохраняется в `.env` или `credentials.txt`.

Если на сервере уже есть `/usr/local/etc/xray/config.json`, скрипт запросит подтверждение и создаст резервную копию перед заменой.

## Файлы и резервные копии

```text
/root/matrix-server/
├── .env                         # 0600
├── docker-compose.yml
├── credentials.txt              # 0600
├── federation-domains.txt       # 0600
└── data/
    ├── postgres/
    ├── synapse/
    ├── coturn/
    ├── mas/
    ├── mas-db/
    ├── livekit/
    ├── ketesa/
    ├── ntfy/
    └── backups/
```

Backup включает дампы PostgreSQL Synapse/MAS, секреты и конфигурации. `media_store` намеренно исключён из быстрого backup и должен копироваться отдельно на внешнее хранилище. Проверяйте восстановление резервных копий до эксплуатации.

## Диагностика

Пункт диагностики проверяет:

- `docker compose config`;
- синтаксис Nginx;
- Matrix Client API;
- `.well-known/matrix/server` и `.well-known/matrix/client`;
- `mas-cli doctor`, если MAS установлен;
- состояние контейнеров.

Полезные ручные команды:

```bash
cd /root/matrix-server
docker compose ps
docker compose logs -f
curl https://matrix.example.com/_matrix/client/versions
curl https://example.com/.well-known/matrix/server
```

## Безопасность

- `.env`, списки федерации, конфигурации с секретами и `credentials.txt` доступны только root;
- сертификат Coturn обновляется deploy-hook Certbot;
- контейнерные порты приложений не публикуются в Интернет;
- перед обновлением создаётся backup;
- стабильные образы закреплены версиями;
- не публикуйте `/root/matrix-server` и не передавайте `credentials.txt` третьим лицам;
- для production ограничьте SSH по ключам и доверенным IP, настройте внешний backup и мониторинг.

## Разработка и проверки

```bash
bash tests/static-render.sh
```

GitHub Actions запускает Bash syntax check, ShellCheck и рендер всех вариантов Compose/Synapse YAML.

## Отказ от ответственности

Скрипт изменяет Docker, Nginx, Certbot, UFW и systemd на сервере. Перед production-развёртыванием проверьте конфигурацию, резервное копирование и требования вашей организации.
