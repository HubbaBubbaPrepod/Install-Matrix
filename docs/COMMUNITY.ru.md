# Сообщество, demo и запуск проекта

> [English version](COMMUNITY.md)

## Рекомендуемые GitHub topics

`matrix`, `matrix-synapse`, `synapse`, `matrix-server`, `matrix-homeserver`, `self-hosted`, `self-hosting`, `homelab`, `linux`, `ubuntu`, `debian`, `docker`, `postgresql`, `coturn`, `turn-server`, `nginx`, `letsencrypt`, `matrixrtc`, `livekit`, `privacy`.

## Matrix Space

Создавайте публичный Space только после появления сопровождающего, который сможет его модерировать:

```text
Install-Matrix
├── Общее
├── Поддержка
├── Ошибки
├── Предложения
└── Объявления
```

Опубликуйте канонический alias комнаты в README и `SUPPORT.ru.md`. Не рекламируйте немодерируемую комнату.

## Demo-сервер

Используйте отдельные VPS, домен и одноразовые аккаунты. Никогда не применяйте production-секреты. Отключите федерацию или задайте строгий allowlist, уменьшите retention и лимит загрузки, ограничьте скорость регистрации и регулярно пересоздавайте demo. Публичный demo — обслуживаемый внешний сервис, поэтому код репозитория не создаёт его автоматически.

## Порядок запуска

1. Опубликуйте проверенный релиз и checksum.
2. Запишите 60-секундную демонстрацию по [VIDEO_SCRIPT.ru.md](VIDEO_SCRIPT.ru.md).
3. Опубликуйте [TUTORIAL.ru.md](TUTORIAL.ru.md) как техническую статью.
4. Расскажите о решении и опыте сообществам Matrix и self-hosting.
5. Просите отзывы о развёртывании, а не звёзды.

Вариант заголовка:

> Я сделал установщик Matrix Synapse одной командой с backup, restore и rollback — вот что я узнал.
