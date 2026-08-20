# Однократная настройка репозитория GitHub

> [English version](REPOSITORY_SETTINGS.md)

Эти настройки доступны только владельцу и не могут полностью храниться в Git. Примените их после публикации ветки с релизом.

## Основные настройки

- Описание: `Production-ready Matrix Synapse deployment for Ubuntu and Debian`.
- Website: ссылка на документацию или будущий сайт проекта.
- Включите **Issues** и **Discussions**.
- Загрузите `docs/assets/social-preview.png` как social preview.
- Добавьте topics из [COMMUNITY.ru.md](COMMUNITY.ru.md).

## Безопасность

- Включите private vulnerability reporting и Dependabot security updates.
- Защитите `main`: обязательные pull requests, проверки CI/Security, разрешённые обсуждения и запрет force push.
- Оставьте workflow token с read-only правами по умолчанию.
- Подключайте self-hosted runner `install-matrix-e2e` только к одноразовому VPS, но не к production homeserver.

## Первый релиз

Следуйте [RELEASING.ru.md](RELEASING.ru.md) для создания подписанного тега `v4.1.0`. Release workflow публикует standalone-установщик и `SHA256SUMS`. До рекламы versioned quick-start убедитесь, что релиз действительно существует.

## Сервисы сообщества

Для demo VPS и Matrix Space нужны домен, секреты, модерация и операционный бюджет. Соблюдайте меры из [COMMUNITY.ru.md](COMMUNITY.ru.md), не используйте production-инфраструктуру и не публикуйте немодерируемую комнату.
