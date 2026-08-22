# Changelog

> [Русская версия](CHANGELOG.ru.md)

All notable changes are documented here. The project follows Semantic Versioning.

## [4.1.0] - 2026-08-22

### Added

- command-line interface, strict config-file parser, non-interactive mode and dry-run;
- checksum-verified backup restore;
- managed image updates, automatic image rollback and explicit rollback command;
- keep-data and purge uninstall modes;
- unified PostgreSQL, Synapse, Coturn, TLS, federation, MAS, MatrixRTC and ntfy health checks;
- complete documentation, community templates, release automation and visual assets;
- all-valid-combination render tests and Ubuntu/Debian CI matrix;
- Trivy, Gitleaks, zizmor, yamllint, markdownlint and supply-chain checks.

### Changed

- open registration remains supported but now requires an explicit risk confirmation;
- UFW detects and preserves the configured SSH port before activation;
- secrets are no longer printed in the completion banner;
- Xray installer is pinned to an immutable commit and verified by SHA256;
- geo databases use an explicit release and verified SHA256 rather than `latest`.
- federation is public by default and large remote rooms are no longer rejected by the complexity limit;
- Synapse federation traffic uses the configured Xray proxy explicitly and validates matrix.org reachability;
- Nginx applies the configured upload limit, Coturn receives readable TLS/config permissions, and optional-service first installs are idempotent;
- LiveKit exposes both TCP and single-port UDP media transports with tuned host buffers;
- Ubuntu 26.04 is included in the supported release matrix.

### Fixed

- remote Matrix profiles, aliases and large-room joins failing behind restricted federation or an ineffective container proxy;
- file uploads rejected by Nginx before reaching Synapse;
- Coturn startup failures caused by unreadable mounted secrets and an ambiguous container command;
- ntfy health checks inheriting the outbound proxy and Element Admin being omitted during its first compose render;
- repeated non-interactive installs skipping initial administrator creation.

### Security

- GitHub Actions are pinned by full commit SHA;
- restore archives reject path traversal, links and unexpected files;
- root-level temporary files use a private runtime directory;
- release assets include SHA256 checksums;
- administrator automation accepts a password file instead of a command-line secret.

## [4.0.0] - 2026-08-14

### Added

- Synapse/PostgreSQL/Coturn base stack;
- optional MAS, LiveKit/MatrixRTC, admin UIs, ntfy and Xray;
- static render tests, diagnostics and database/config backups.

[4.1.0]: https://github.com/HubbaBubbaPrepod/Install-Matrix/compare/v4.0.0...v4.1.0
[4.0.0]: https://github.com/HubbaBubbaPrepod/Install-Matrix/releases/tag/v4.0.0
