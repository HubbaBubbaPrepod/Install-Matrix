# Архитектура

> [English version](ARCHITECTURE.md)

Install-Matrix рассчитан на один выделенный VPS с Ubuntu или Debian. Nginx является единственной публичной точкой входа HTTP; порты приложений привязаны к loopback или изолированной сети Compose.

```text
Клиенты / федерация
         │ HTTPS :443
         ▼
       Nginx ─────────────── .well-known на server_name
         │
         ├── Synapse :8008 ─── PostgreSQL
         ├── MAS :8080 ─────── MAS PostgreSQL
         ├── lk-jwt :8082 ──── LiveKit (host network)
         ├── панели администратора
         └── ntfy :8090

Звонки ── TURN/TLS ── Coturn (host network)
Звонки ── MatrixRTC ─ LiveKit (host network)
```

## Границы доверия

- Интернет → Nginx/Coturn/LiveKit: недоверенный публичный трафик.
- Nginx → сервисы на loopback: граница reverse proxy.
- Сеть Compose `matrix`: трафик приложений и баз данных.
- `/root/matrix-server`: принадлежащие `root` секреты, конфигурация и постоянные данные.
- Внешнее хранилище backup: зашифрованная граница восстановления.

## Создаваемые файлы

```text
/root/matrix-server/
├── .env
├── docker-compose.yml
├── credentials.txt
├── federation-domains.txt
└── data/
    ├── postgres/
    ├── synapse/
    ├── coturn/
    ├── mas/
    ├── mas-db/
    ├── livekit/
    ├── ketesa/
    ├── element-admin/
    ├── ntfy/
    └── backups/
```

Созданный Compose-файл считается результатом генерации. Постоянные настройки находятся в `.env`, после чего установщик генерирует стек заново.

## Структура установщика

`install-matrix.sh` намеренно остаётся самостоятельным релизным файлом: оператор может скачать, прочитать и проверить один файл до запуска. Функции сгруппированы по этапам жизненного цикла — генерация, компоненты, backup/restore, update/rollback, диагностика и CLI. Каталог `tests/` проверяет эти границы отдельно. `scripts/build-release.sh` создаёт неизменяемый дистрибутив и manifest контрольных сумм; второй источник для генерируемых runtime-файлов не поддерживается.
