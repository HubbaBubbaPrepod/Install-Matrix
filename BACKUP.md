# Backup and disaster recovery

> [Русская версия](BACKUP.ru.md)

Matrix state is not limited to `homeserver.yaml`. A usable recovery set must contain the Synapse PostgreSQL database, the signing key, registration/TURN/MAS secrets, optional MAS database, configuration files and the media store.

## Create and verify a backup

```bash
sudo ./install-matrix.sh backup
sudo ./install-matrix.sh verify-backup latest
```

Each backup is stored under `/root/matrix-server/data/backups/<timestamp>/` and contains:

- `synapse.dump` — PostgreSQL custom-format dump;
- `mas.dump` when MAS is installed;
- `configuration.tar.gz` — `.env`, Compose, signing keys and component configuration;
- `MANIFEST.txt` — installer version, domains, reason and image list;
- `SHA256SUMS` — integrity metadata checked before restore.

`media_store` is deliberately excluded because it may be very large. Back it up independently with snapshots, restic, borg or object-storage replication.

## What must never be lost

| Data | Consequence if lost |
|---|---|
| Synapse database | Rooms, accounts, devices and state are lost |
| `*.signing.key` | The homeserver can no longer prove continuity to federation |
| `.env` and MAS config | Database, TURN, OIDC and encryption secrets are lost |
| MAS database and encryption keys | Authentication sessions/accounts may become unusable |
| `media_store` | Uploaded files and thumbnails disappear |

Copy backups off the VPS. A backup stored only beside the production database is not disaster recovery.

## Restore on the existing host

```bash
sudo ./install-matrix.sh restore /secure/offsite/20260820-120000
# or the most recent local backup
sudo ./install-matrix.sh restore latest
```

The command verifies SHA256 and tar integrity, creates a pre-restore backup when the current stack is available, stops application containers, restores PostgreSQL/MAS and runs the complete health check.

## Restore on a replacement host

1. Provision a supported clean VPS and point the existing DNS names to it.
2. Install Docker, Nginx, Certbot and UFW by running the base installer with the same domains.
3. Transfer the backup directory and the separately stored media store over an authenticated channel.
4. Run `restore <directory> --yes`.
5. Restore `data/synapse/media_store` with ownership `991:991`.
6. Reissue or renew TLS certificates and run `diagnose`.
7. Test login, message history, media, federation and calls before changing traffic permanently.

## Restore drill

Perform a restore drill before every major release and at least quarterly. The manual `E2E deployment` workflow includes a backup/restore cycle on a disposable runner.

Backups contain credentials. Keep them encrypted at rest, restrict access to root and define a retention policy.
