# Releasing

> [Русская версия](RELEASING.ru.md)

Releases are immutable deployment inputs, not snapshots of `main`.

## Checklist

1. Update `INSTALLER_VERSION`, README examples and `CHANGELOG.md`.
2. Update pinned images/downloads deliberately and run the weekly verification locally.
3. Run all checks from [CONTRIBUTING.md](../CONTRIBUTING.md).
4. Complete the disposable-VM E2E workflow, including restore.
5. Commit and create a signed annotated tag:

```bash
git tag -s v4.1.0 -m "Install-Matrix v4.1.0"
git push origin v4.1.0
```

The release workflow validates that the tag matches `--version`, reruns tests, publishes `install-matrix.sh`, documentation and `SHA256SUMS`, and creates release notes.

Never retag an existing version. Publish a patch release instead.
