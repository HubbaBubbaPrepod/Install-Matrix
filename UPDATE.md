# Updates, upgrades and rollback

> [Русская версия](UPDATE.ru.md)

Install-Matrix separates installer releases from deployed component versions. The active versions live in `/root/matrix-server/.env`.

## Image policies

- `IMAGE_POLICY=managed` adopts the image versions shipped by the current installer when `update` runs.
- `IMAGE_POLICY=custom` preserves all image references from `.env`.

## Recommended update

1. Read [CHANGELOG.md](CHANGELOG.md) and upstream migration notes.
2. Download a tagged installer and verify `SHA256SUMS`.
3. Run:

```bash
sudo ./install-matrix.sh update
```

The command creates a database/configuration backup, saves the old image set in `.last-update.env`, renders the new stack, pulls images and runs diagnostics. If pull, startup or diagnostics fail, the previous images are restored automatically.

## Explicit rollback

```bash
sudo ./install-matrix.sh rollback
```

This restores the previous image references. It does not reverse irreversible database migrations. For database rollback, restore the `pre-update` backup shown by the command:

```bash
sudo ./install-matrix.sh restore /root/matrix-server/data/backups/<timestamp>
```

## Custom component versions

Set `IMAGE_POLICY=custom`, edit the protected `.env`, then run `update`. Use immutable digests for long-lived production deployments:

```env
SYNAPSE_IMAGE=ghcr.io/element-hq/synapse@sha256:...
```

Test Synapse, PostgreSQL and MAS major upgrades in staging. PostgreSQL major-version upgrades require an explicit dump/restore or `pg_upgrade`; changing only the container tag is not sufficient.

## Installer upgrade

The version printed by `./install-matrix.sh --version` must match the GitHub release tag. Do not update from a mutable branch on a production server.
