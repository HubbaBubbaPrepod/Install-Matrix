# Чек-лист публикации в экосистеме Matrix

> [English version](ECOSYSTEM.md)

Долгосрочная цель — включение Install-Matrix в официальный каталог экосистемы Matrix.

- [x] лицензия, совместимая с OSI;
- [x] workflow семантических релизов;
- [x] установщик с проверяемой checksum;
- [x] архитектура и политика безопасности;
- [x] backup, restore, update, rollback и uninstall;
- [x] CI для заявленных Ubuntu/Debian окружений;
- [x] E2E workflow на одноразовой VM;
- [x] публичные шаблоны issues и contribution;
- [ ] опубликовать v4.1.0 и задокументировать production E2E;
- [ ] создать публичный Matrix Space или комнату поддержки;
- [ ] получить отчёты от двух независимых production-пользователей;
- [ ] отправить краткое описание distribution в репозиторий сайта Matrix.

Предлагаемое описание:

> Install-Matrix — интерактивный и неинтерактивный установщик Synapse, PostgreSQL, Nginx, Let's Encrypt и Coturn на одном VPS с опциональными MAS и MatrixRTC. Его цель — быстрое и понятное развёртывание на Ubuntu/Debian со встроенными backup, restore и rollback.
