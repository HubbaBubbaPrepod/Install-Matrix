# Community, demo and launch runbook

> [Русская версия](COMMUNITY.ru.md)

## Recommended GitHub topics

`matrix`, `matrix-synapse`, `synapse`, `matrix-server`, `matrix-homeserver`, `self-hosted`, `self-hosting`, `homelab`, `linux`, `ubuntu`, `debian`, `docker`, `postgresql`, `coturn`, `turn-server`, `nginx`, `letsencrypt`, `matrixrtc`, `livekit`, `privacy`.

## Matrix Space

Create a public Space only after a maintainer can moderate it:

```text
Install-Matrix
├── General
├── Support
├── Bug reports
├── Feature requests
└── Announcements
```

Publish the canonical room alias in README and `SUPPORT.md`. Do not advertise an unmoderated room.

## Demo server

Use a separate VPS and domain with disposable accounts. Never reuse production credentials. Disable federation or use a strict allowlist, set short retention, cap uploads, rate-limit registration and rebuild the demo regularly. A public demo is an operational service and is intentionally not created by repository code.

## Launch sequence

1. Publish a tested release and checksum.
2. Record the 60-second flow in [VIDEO_SCRIPT.md](VIDEO_SCRIPT.md).
3. Publish [TUTORIAL.md](TUTORIAL.md) as a technical article.
4. Share the solution and lessons learned with Matrix and self-hosting communities.
5. Ask for deployment feedback, not stars.

Useful headline:

> I built a one-command Matrix Synapse installer with backup, restore and rollback — here is what I learned.
