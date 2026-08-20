# Security policy

> [Русская версия](SECURITY.ru.md)

## Supported versions

| Version | Security fixes |
|---|---|
| 4.1.x | Supported |
| 4.0.x | Critical fixes only until the next minor release |
| Earlier | Unsupported |

## Reporting a vulnerability

Do not open a public issue containing an exploit, credential, server address or private configuration. Use GitHub Private Vulnerability Reporting in the repository Security tab. If it is unavailable, contact the maintainer through the private address published on the GitHub profile and request an encrypted channel.

Include the installer version, affected component, reproduction steps, impact and suggested mitigation. Do not test against systems you do not own or administer.

## Response targets

- acknowledgement: 3 business days;
- initial assessment: 7 business days;
- coordinated disclosure after a fix or agreed deadline.

## If credentials are compromised

1. Restrict network access and preserve logs.
2. Rotate PostgreSQL, TURN, registration, MAS and LiveKit secrets.
3. Revoke affected Matrix devices/sessions and ntfy credentials.
4. Replace the VLESS credential and inspect `/usr/local/etc/xray/config.json`.
5. Review federation/admin logs and restore only from a known-good backup.

## Supply-chain model

- install from tagged GitHub release assets and verify `SHA256SUMS`;
- external root-level installers are pinned by commit and checksum;
- GitHub Actions are pinned by full commit SHA;
- default container images are pinned by both version tag and OCI digest;
- weekly workflows verify pinned downloads and scan the repository with Trivy, Gitleaks and zizmor.

## Host hardening

Use SSH keys, restrict administrative IPs, keep the host patched, encrypt offsite backups and monitor disk space. The installer preserves the SSH port detected by `sshd -T` before enabling UFW.
