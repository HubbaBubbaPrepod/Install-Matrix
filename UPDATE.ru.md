# Обновление и откат

> [English version](UPDATE.md)

Install-Matrix разделяет версию установщика и версии развёрнутых компонентов. Активные версии находятся в `/root/matrix-server/.env`.

## Политики образов

- `IMAGE_POLICY=managed` при `update` применяет версии образов из текущего установщика.
- `IMAGE_POLICY=custom` сохраняет все ссылки на образы из `.env`.

## Рекомендуемое обновление

1. Прочитайте [CHANGELOG.ru.md](CHANGELOG.ru.md) и upstream-инструкции по миграции.
2. Скачайте установщик из релиза и проверьте `SHA256SUMS`.
3. Выполните:

```bash
sudo ./install-matrix.sh update
```

Команда создаёт backup БД и конфигурации, сохраняет старый набор образов в `.last-update.env`, генерирует новый стек, загружает образы и запускает диагностику. При ошибке загрузки, запуска или health checks предыдущие образы возвращаются автоматически.

## Явный откат

```bash
sudo ./install-matrix.sh rollback
```

Команда возвращает предыдущие ссылки на образы, но не отменяет необратимые миграции БД. Для отката базы восстановите показанный командой `pre-update` backup:

```bash
sudo ./install-matrix.sh restore /root/matrix-server/data/backups/<timestamp>
```

## Собственные версии компонентов

Установите `IMAGE_POLICY=custom`, измените защищённый `.env` и запустите `update`. Для production используйте неизменяемые digest:

```env
SYNAPSE_IMAGE=ghcr.io/element-hq/synapse@sha256:...
```

Крупные обновления Synapse, PostgreSQL и MAS сначала проверяйте на staging. Для major-обновления PostgreSQL требуется явный dump/restore или `pg_upgrade`; одной смены тега контейнера недостаточно.

## Обновление установщика

Версия из `./install-matrix.sh --version` должна совпадать с тегом GitHub-релиза. Не обновляйте production-сервер из изменяемой ветки.
