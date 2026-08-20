# Uninstall

> [Русская версия](UNINSTALL.ru.md)

Two removal modes are supported.

## Remove services, keep data

```bash
sudo ./install-matrix.sh uninstall --keep-data
```

This stops and removes Compose containers, removes generated Nginx sites and application firewall rules, and preserves `/root/matrix-server` for later recovery.

Reinstall with the same script and select the base install command. Existing database secrets and data are reused.

## Remove everything

```bash
sudo ./install-matrix.sh uninstall --purge
```

The installer:

1. creates a final database/config backup;
2. exports it to `/root/install-matrix-final-backup-<timestamp>.tar.gz`;
3. removes containers, generated Nginx files and application UFW rules;
4. deletes `/root/matrix-server` after validating the exact path.

The final archive does not contain `media_store`. Copy media separately before purge. Let's Encrypt certificates are retained because they may be shared with other services; remove them manually with `certbot delete` only after confirming they are unused.

The installer never removes Docker, Nginx, Certbot or UFW packages because they may be used by unrelated applications.
