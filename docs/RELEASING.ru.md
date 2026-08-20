# Выпуск релиза

> [English version](RELEASING.md)

Релизы являются неизменяемыми входными данными развёртывания, а не снимками `main`.

## Чек-лист

1. Обновите `INSTALLER_VERSION`, примеры README и `CHANGELOG.ru.md`/`CHANGELOG.md`.
2. Осознанно обновите закреплённые образы и загрузки, затем локально запустите еженедельную проверку.
3. Выполните все проверки из [CONTRIBUTING.ru.md](../CONTRIBUTING.ru.md).
4. Завершите E2E workflow на одноразовой VM, включая restore.
5. Создайте commit и подписанный аннотированный тег:

```bash
git tag -s v4.1.0 -m "Install-Matrix v4.1.0"
git push origin v4.1.0
```

Release workflow проверяет соответствие тега `--version`, повторяет тесты, публикует `install-matrix.sh`, документацию и `SHA256SUMS`, затем создаёт release notes.

Никогда не перемещайте существующий тег. Вместо этого выпускайте patch-релиз.
