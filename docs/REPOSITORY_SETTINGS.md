# One-time GitHub repository settings

> [Русская версия](REPOSITORY_SETTINGS.ru.md)

These owner-only settings cannot be expressed entirely in the Git tree. Apply them after the branch containing this release is pushed.

## General

- Description: `Production-ready Matrix Synapse deployment for Ubuntu and Debian`
- Website: link to the documentation or a future project site.
- Enable **Issues** and **Discussions**.
- Upload `docs/assets/social-preview.png` as the repository social preview.
- Add the topics listed in [COMMUNITY.md](COMMUNITY.md).

## Security

- Enable private vulnerability reporting and Dependabot security updates.
- Protect `main`: require pull requests, CI and Security checks, resolved conversations and no force pushes.
- Keep workflow token permissions read-only by default.
- Add the `install-matrix-e2e` self-hosted runner only on a disposable VPS; never attach it to a production homeserver.

## First release

Follow [RELEASING.md](RELEASING.md) to create the signed `v4.1.0` tag. The release workflow publishes the standalone installer and `SHA256SUMS`. Confirm the release exists before advertising the versioned quick-start URL.

## Community services

A demo VPS and Matrix Space require a domain, credentials, moderation and an operating budget. Use the safeguards in [COMMUNITY.md](COMMUNITY.md); do not reuse production infrastructure or publish an unmoderated room.
