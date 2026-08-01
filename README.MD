# Matrix Server Installer

This repository contains a Bash installer for setting up a self-hosted Matrix infrastructure on Ubuntu 20.04, 22.04, or 24.04.

The script automates installation of:

- Matrix Synapse
- PostgreSQL
- Coturn for STUN/TURN
- Nginx reverse proxy
- Let's Encrypt SSL certificates
- optional Matrix Authentication Service (MAS)
- optional LiveKit for voice/video calls
- firewall configuration with UFW

## Repository contents

- `install-matrix.sh` — interactive installation script

## What the script does

The installer offers a menu with three installation paths:

1. Install Matrix
   - Synapse homeserver
   - PostgreSQL database
   - Coturn
   - Nginx HTTPS proxy
   - automatic TLS certificate via Certbot
   - generated secrets and config in `/root/matrix-server`

2. Install MAS
   - Matrix Authentication Service for login/auth flows
   - requires an existing Matrix installation
   - configures HTTPS for the MAS hostname
   - integrates with Synapse

3. Install LiveKit
   - WebRTC media service for Matrix voice/video calls
   - requires Matrix and MAS
   - configures reverse proxy and JWT service
   - exposes `/lk-jwt` on the main Matrix domain

## Requirements

Before running the installer, make sure:

- You are running Ubuntu 20.04+ on a fresh or managed server
- You have root access
- Your Matrix domain is configured in DNS and resolves to the server IP
- Ports 80, 443, 8448, 8008, 3478, 5349, and the RTP range are allowed
- A valid domain for the Matrix server is available

Example:

- Matrix: `matrix.example.com`
- MAS: `mas.example.com` (optional)
- LiveKit: `livekit.example.com` (optional)

## Установка

Ссылка на проект: [HubbaBubbaPrepod/Install-Matrix](https://github.com/HubbaBubbaPrepod/Install-Matrix)

Самый быстрый способ установки:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/HubbaBubbaPrepod/Install-Matrix/refs/heads/main/install-matrix.sh)
```

Или скачать и запустить вручную:

```bash
curl -fsSL https://raw.githubusercontent.com/HubbaBubbaPrepod/Install-Matrix/refs/heads/main/install-matrix.sh -o install-matrix.sh && chmod +x install-matrix.sh && sudo bash ./install-matrix.sh
```

Если вы запускаете скрипт локально из этого репозитория, используйте:

```bash
chmod +x install-matrix.sh
sudo ./install-matrix.sh
```

Then choose from the menu:

- `1` — Install Matrix
- `2` — Install MAS
- `3` — Install LiveKit
- `0` — Exit

## Installation flow

### 1) Matrix

The Matrix setup will:

- update OS packages
- install Docker and Compose
- configure Nginx
- request an SSL certificate with Certbot
- create directories under `/root/matrix-server`
- generate `docker-compose.yml` and `homeserver.yaml`
- start Synapse and Coturn containers
- create the first admin user via `register_new_matrix_user`
- save credentials to `/root/matrix-server/credentials.txt`

### 2) MAS

This step adds the Matrix Authentication Service. It creates a MAS config and configures a separate Nginx site for the MAS hostname.

### 3) LiveKit

This step configures the LiveKit signaling/media stack and adds the `/lk-jwt` proxy route to the main Matrix site.

## Generated directories and files

The installer writes the stack to `/root/matrix-server`.

Typical structure:

```text
/root/matrix-server/
├── .env
├── docker-compose.yml
├── credentials.txt
├── data/
│   ├── postgres/
│   ├── synapse/
│   ├── coturn/
│   ├── mas/
│   └── livekit/
```

## Important notes

- The script expects the server to be publicly accessible on the configured domains.
- Certificates are obtained automatically with Let's Encrypt.
- Secrets are generated automatically and stored in `.env` and related config files.
- The script is designed for server-side installation and is not intended for local desktop testing.
- For production, review generated config files and secrets before exposing the service publicly.

## Useful commands

From the Matrix install directory:

```bash
cd /root/matrix-server
sudo docker compose ps
sudo docker compose logs -f
sudo docker compose restart
```

Check Synapse availability:

```bash
curl https://matrix.example.com/_matrix/client/versions
```

## Security recommendations

- Keep your server patched and updated.
- Restrict SSH access with UFW or another firewall rule set.
- Do not expose admin credentials in public repositories.
- Rotate generated secrets if they are ever shared or leaked.
- Review the generated Nginx and Synapse configuration before production deployment.

## Disclaimer

This project is intended for self-hosted infrastructure and automation. Use it responsibly and ensure the server meets your compliance and operational requirements.

## License

This repository does not include an explicit license file. Treat the contents as project-local code for deployment and administration unless otherwise stated by the repository owner.
