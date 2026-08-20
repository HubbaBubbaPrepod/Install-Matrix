# История изменений

> [English version](CHANGELOG.md)

Здесь перечисляются заметные изменения. Проект следует Semantic Versioning.

## [4.1.0] — 2026-08-20

### Добавлено

- CLI, строгий parser конфигурации, non-interactive и dry-run;
- restore с проверкой checksum;
- управляемые обновления образов, автоматический и явный rollback;
- удаление с сохранением данных и полный purge;
- единые health checks PostgreSQL, Synapse, Coturn, TLS, федерации, MAS, MatrixRTC и ntfy;
- документация, community templates, автоматизация релиза и визуальные материалы;
- тесты всех допустимых комбинаций и матрица Ubuntu/Debian;
- Trivy, Gitleaks, zizmor, yamllint, markdownlint и supply-chain проверки.

### Изменено

- открытая регистрация сохранена, но требует явного подтверждения риска;
- UFW определяет и сохраняет текущий SSH-порт;
- секреты больше не выводятся в финальном баннере;
- Xray installer закреплён неизменяемым commit и SHA-256;
- geo-базы закреплены релизом и SHA-256 вместо `latest`.

### Безопасность

- GitHub Actions закреплены полным SHA commit;
- restore отклоняет path traversal, ссылки и неожиданные файлы;
- root-временные файлы размещаются в приватном каталоге;
- релиз содержит SHA-256 checksums;
- автоматизация принимает пароль администратора из файла, а не аргумента CLI.

## [4.0.0] — 2026-08-14

### Добавлено

- базовый стек Synapse/PostgreSQL/Coturn;
- опциональные MAS, LiveKit/MatrixRTC, admin UI, ntfy и Xray;
- static render tests, диагностика и backup БД/конфигурации.

[4.1.0]: https://github.com/HubbaBubbaPrepod/Install-Matrix/compare/v4.0.0...v4.1.0
[4.0.0]: https://github.com/HubbaBubbaPrepod/Install-Matrix/releases/tag/v4.0.0
