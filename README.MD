# Install-Matrix

> **Простой способ развернуть готовый к эксплуатации сервер Matrix Synapse на обычном VPS.**

[English version](README.en.md)

Один установщик для Synapse, PostgreSQL, Nginx, Let's Encrypt и Coturn. Дополнительно поддерживаются MAS, MatrixRTC/LiveKit, панели администрирования, ntfy и исходящий прокси Xray.

[![CI](https://github.com/HubbaBubbaPrepod/Install-Matrix/actions/workflows/ci.yml/badge.svg)](https://github.com/HubbaBubbaPrepod/Install-Matrix/actions/workflows/ci.yml)
[![Security](https://github.com/HubbaBubbaPrepod/Install-Matrix/actions/workflows/security.yml/badge.svg)](https://github.com/HubbaBubbaPrepod/Install-Matrix/actions/workflows/security.yml)
[![Release](https://img.shields.io/github/v/release/HubbaBubbaPrepod/Install-Matrix)](https://github.com/HubbaBubbaPrepod/Install-Matrix/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

[Быстрый старт](#быстрый-старт) · [Документация](#документация) · [CLI](#cli-и-автоматизация) · [Issues](https://github.com/HubbaBubbaPrepod/Install-Matrix/issues)

![Архитектура Install-Matrix](docs/assets/architecture.svg)

## Что устанавливается?

| Компонент | Статус | Назначение |
|---|---|---|
| Matrix Synapse | В комплекте | Домашний сервер и федерация |
| PostgreSQL | В комплекте | Рабочая база данных |
| Coturn | В комплекте | TURN/STUN для звонков |
| Nginx | В комплекте | TLS и обратный прокси |
| Let's Encrypt | В комплекте | Автоматические HTTPS-сертификаты |
| UFW | В комплекте | Межсетевой экран с сохранением текущего SSH-порта |
| Matrix Authentication Service | Опционально | Современная аутентификация Matrix |
| LiveKit + lk-jwt-service | Опционально | Медиасервер MatrixRTC |
| Ketesa / Element Admin | Опционально | Панели администрирования |
| ntfy | Опционально | Сервер UnifiedPush |
| Xray/VLESS | Опционально | Исходящий HTTP(S)-прокси контейнеров |

## Зачем Install-Matrix?

Обычное развёртывание Matrix требует вручную связать базу данных, обратный прокси, TLS, TURN, обнаружение федерации и резервное копирование. Install-Matrix сохраняет удобную интерактивную установку и одновременно предоставляет воспроизводимый CLI для cloud-init, Ansible и CI.

- безопасные настройки по умолчанию и явный выбор регистрации: `closed`, `token` или `open`;
- образы закреплены версиями и OCI digest, внешние загрузки — неизменяемыми версиями и SHA-256;
- backup, проверка контрольных сумм, restore, update и rollback образов;
- удаление сервисов с сохранением данных или полная очистка;
- проверки PostgreSQL, Synapse, Coturn, TLS, федерации, MAS, MatrixRTC и ntfy;
- автоматический рендер всех допустимых комбинаций компонентов на Ubuntu и Debian.

Проект рассчитан на понятное развёртывание на одном VPS. Для сильно изменяемой многоузловой установки через Ansible лучше рассмотреть `matrix-docker-ansible-deploy`.

## Быстрый старт

### Рекомендуется: релиз с проверкой контрольной суммы

```bash
VERSION=v4.1.0
curl -fLO "https://github.com/HubbaBubbaPrepod/Install-Matrix/releases/download/${VERSION}/install-matrix.sh"
curl -fLO "https://github.com/HubbaBubbaPrepod/Install-Matrix/releases/download/${VERSION}/SHA256SUMS"
sha256sum --check --ignore-missing SHA256SUMS
less install-matrix.sh
chmod +x install-matrix.sh
sudo ./install-matrix.sh
```

Не запускайте от `root` непроверенный скрипт из изменяемой ветки. Каждый релиз собирается GitHub Actions и содержит `SHA256SUMS`.

### Загрузка и запуск одной командой

```bash
VERSION=v4.1.0; curl -fsSLo install-matrix.sh "https://github.com/HubbaBubbaPrepod/Install-Matrix/releases/download/${VERSION}/install-matrix.sh" && chmod +x install-matrix.sh && sudo ./install-matrix.sh
```

Установка размещается в `/root/matrix-server`.

## DNS до установки

Предположим, домен Matrix ID — `example.com`, а IPv4 сервера — `203.0.113.10`.

| Назначение | DNS-имя | Обязательно |
|---|---|---|
| Matrix ID и делегирование `.well-known` | `example.com` | Да |
| Matrix Client/Federation API | `matrix.example.com` | Да |
| MAS | `mas.example.com` | При включённом MAS |
| MatrixRTC | `livekit.example.com` | При включённом LiveKit |
| Ketesa | `admin.example.com` | При включении |
| Element Admin | `element-admin.example.com` | При включении |
| ntfy | `ntfy.example.com` | При включении |

Во время выпуска сертификатов Let's Encrypt все записи должны напрямую указывать на сервер. Не публикуйте `AAAA`, пока IPv6 не настроен полностью. Существующие CAA-записи должны разрешать `letsencrypt.org`.

## Поддерживаемые системы

CI создаёт и проверяет конфигурации в следующих окружениях. Перед production-релизом настоящая установка проверяется ручным E2E workflow на одноразовой виртуальной машине.

| ОС | Версия | Рендер в CI | Условие production-релиза |
|---|---:|:---:|:---:|
| Ubuntu | 20.04 | ✅ | Ручной E2E |
| Ubuntu | 22.04 | ✅ | Ручной E2E |
| Ubuntu | 24.04 | ✅ | Ручной E2E |
| Ubuntu | 26.04 | ✅ | Ручной E2E |
| Debian | 11 | ✅ | Ручной E2E |
| Debian | 12 | ✅ | Ручной E2E |
| Debian | 13 | ✅ | Ручной E2E |

Официально поддерживается архитектура `amd64`. Другие архитектуры могут работать, если все выбранные образы имеют подходящий manifest, но пока не блокируют выпуск релиза.

## Режимы регистрации

| Режим | Поведение |
|---|---|
| `closed` | Создание новых аккаунтов отключено |
| `token` | Для регистрации требуется токен Synapse/MAS |
| `open` | Регистрация без токена с обязательным подтверждением риска |

Открытая регистрация намеренно доступна, но может привлечь ботов и злоупотребления. В non-interactive режиме одновременно требуются `REGISTRATION_MODE=open` и `--allow-open-registration`.

## CLI и автоматизация

```bash
sudo ./install-matrix.sh --help
sudo ./install-matrix.sh diagnose
sudo ./install-matrix.sh backup
sudo ./install-matrix.sh verify-backup latest
sudo ./install-matrix.sh restore latest
sudo ./install-matrix.sh update
sudo ./install-matrix.sh rollback
sudo ./install-matrix.sh uninstall --keep-data
```

Неинтерактивная установка:

```bash
sudo ./install-matrix.sh install \
  --non-interactive \
  --config config.env \
  --yes
```

Проверка и рендер без изменения операционной системы:

```bash
./install-matrix.sh install --dry-run --config config.env
```

Скопируйте [`config.example`](config.example), а настоящий файл храните вне Git. Пароль администратора читается из `ADMIN_PASSWORD_FILE` и не передаётся аргументом командной строки.

## Сетевые порты

| Порты | Компонент |
|---|---|
| Текущий SSH-порт, `80/tcp`, `443/tcp` | Доступ к серверу и HTTPS |
| `3478/tcp+udp`, `5349/tcp+udp`, `49152-49252/udp` | Coturn |
| `7881/tcp`, `50000-50100/udp` | LiveKit при включении |

HTTP-порты приложений привязаны только к `127.0.0.1`. Федерация обслуживается на `443`; публичный порт `8448` не требуется.

## Результат установки

Установщик завершает работу единым отчётом:

```text
✓ Docker Compose config
✓ PostgreSQL
✓ Synapse
✓ Coturn
✓ Nginx и HTTPS
✓ Matrix Client API
✓ Matrix Federation API
✓ MAS / LiveKit / ntfy — если включены
```

Учётные данные записываются с правами `0600` в `/root/matrix-server/credentials.txt`. Секреты не выводятся в финальном баннере.

## Документация

- [Резервное копирование и восстановление](BACKUP.ru.md)
- [Обновление и откат](UPDATE.ru.md)
- [Удаление](UNINSTALL.ru.md)
- [Политика безопасности](SECURITY.ru.md)
- [FAQ](docs/FAQ.ru.md)
- [Архитектура](docs/ARCHITECTURE.ru.md)
- [Участие в разработке](CONTRIBUTING.ru.md)
- [Поддержка](SUPPORT.ru.md)
- [Кодекс поведения](CODE_OF_CONDUCT.ru.md)
- [История изменений](CHANGELOG.ru.md)

## Скриншоты

| Интерактивное меню | Проверка состояния | Автоматизация |
|---|---|---|
| ![Меню установщика](docs/assets/menu.svg) | ![Проверки состояния](docs/assets/health.svg) | ![Автоматизация CLI](docs/assets/automation.svg) |

## Разработка

```bash
bash -n install-matrix.sh tests/*.sh scripts/*.sh
shellcheck --severity=warning -x -e SC1091 install-matrix.sh tests/*.sh scripts/*.sh
bash tests/static-render.sh
bash tests/cli.sh
bash tests/lifecycle.sh
bash tests/docs.sh
bash tests/supply-chain.sh
```

CI дополнительно запускает yamllint, markdownlint, Trivy, Gitleaks, zizmor и матрицу из шести дистрибутивов. E2E workflow предназначен для отдельной одноразовой VM с настоящими DNS-записями.

## Лицензия

[MIT](LICENSE). Об уязвимостях сообщайте по инструкции из [SECURITY.ru.md](SECURITY.ru.md), а не через публичный issue.
