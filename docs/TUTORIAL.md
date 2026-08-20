# I built a one-command Matrix Synapse installer

> [Русская версия](TUTORIAL.ru.md)

Running a Matrix homeserver is not just starting Synapse. A practical deployment needs PostgreSQL, HTTPS, federation discovery, TURN, firewall rules, backups and a reliable update story. Optional MAS and MatrixRTC add more moving parts.

Install-Matrix packages that single-VPS path into one reviewable Bash release while keeping every generated file visible under `/root/matrix-server`.

## Design goals

1. A newcomer should understand the DNS and port requirements before running anything.
2. The safe path should be the default, while advanced choices remain explicit.
3. A failed update should have both an image rollback and a database backup.
4. Automation must not require secrets on the command line.
5. Every supported configuration should render in CI.

## Architecture

Nginx terminates HTTPS and routes to loopback-bound services. Synapse and MAS use separate PostgreSQL databases. Coturn and LiveKit use host networking only for the media ports they require. `.well-known` keeps human-friendly Matrix IDs separate from the API hostname.

## Reliability

The installer creates custom-format PostgreSQL dumps, archives signing keys and configuration, writes SHA256 metadata, and can restore the stack. Managed image updates preserve the old image set and roll back automatically when health checks fail.

## Security

Release assets are checksummed, the Xray installer is pinned by commit and SHA256, CI actions use full commit SHAs, the current SSH port is preserved before enabling UFW, and non-interactive admin passwords come from a protected file.

## Try it

Start with the verified release instructions in the repository README, use a disposable VPS first, and report what was easy or confusing. Real deployment feedback is more valuable than a star counter.
