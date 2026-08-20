# FAQ

> [Русская версия](FAQ.ru.md)

## Is this a replacement for matrix-docker-ansible-deploy?

No. Install-Matrix optimizes for a simple single-VPS deployment and interactive UX. Ansible deployments offer broader customization and multi-host automation.

## Does it install Element Web or Element Call?

No. Any compatible Matrix client can connect to the homeserver. LiveKit is the server-side MatrixRTC component.

## Is open registration supported?

Yes. `closed`, `token` and `open` modes are available. Open registration requires explicit confirmation because it can be abused by automated signups.

## Why is port 8448 closed?

Federation is delegated to Nginx on standard HTTPS port 443 through `.well-known/matrix/server`.

## Where are secrets stored?

Under `/root/matrix-server` with restrictive permissions. The completion banner does not print them.

## Does backup include media?

No. Database/config backups remain fast and predictable; `media_store` must be copied independently to offsite storage.

## Can I use Cloudflare proxying?

Certificate issuance requires ports 80/443 to reach the VPS. Federation and large uploads may require provider-specific limits. Test without proxying first.

## Can I use ARM64?

It is not release-gated yet. Every selected container image and host package must support the architecture.

## How do I report a problem?

Run `sudo ./install-matrix.sh diagnose`, redact domains/IPs when necessary, and use the bug template. Report vulnerabilities privately via [SECURITY.md](../SECURITY.md).
