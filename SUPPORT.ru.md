# Поддержка

> [English version](SUPPORT.md)

Используйте GitHub Issues для воспроизводимых ошибок и предложений. Перед созданием bug report выполните:

```bash
sudo ./install-matrix.sh --version
sudo ./install-matrix.sh diagnose
cd /root/matrix-server && docker compose ps
```

Скройте секреты, access tokens, signing keys, VLESS URI, приватные домены и IP-адреса. Не публикуйте `.env`, `credentials.txt`, конфигурацию MAS или полные журналы.

Об уязвимостях сообщайте по [SECURITY.ru.md](SECURITY.ru.md). Вопросы по Matrix-клиентам задавайте в сообществах соответствующих клиентов.
