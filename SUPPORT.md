# Support

> [Русская версия](SUPPORT.ru.md)

Use GitHub Issues for reproducible bugs and feature requests. Before opening a bug:

```bash
sudo ./install-matrix.sh --version
sudo ./install-matrix.sh diagnose
cd /root/matrix-server && docker compose ps
```

Redact credentials, access tokens, signing keys, VLESS URIs, private domains and IP addresses. Do not paste `.env`, `credentials.txt`, MAS config or complete logs publicly.

Security vulnerabilities follow [SECURITY.md](SECURITY.md). General Matrix client support belongs in the client's own community.
