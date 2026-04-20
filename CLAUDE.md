# CLAUDE.md

Project conventions for Claude Code working on `raspi-shared-db-service`.

---

## 🎯 Project summary

A shared MySQL database service for the Raspberry Pi. Runs as a standalone Docker Compose stack; other app stacks on the Pi opt into its network to consume it. See `SHARED_DB_SPEC.md` for the full bootstrap spec.

---

## 🏗️ What this repo is (and isn't)

This repo is **infrastructure**, not an application:
- No application code, no language runtime, no framework
- Just Docker Compose + SQL + shell scripts + docs
- Treat it like Terraform or Ansible — declarative, idempotent where possible

---

## 🐳 Docker conventions

- Use the upstream `mysql:8` image — don't build a custom Dockerfile unless there's a concrete reason
- Pin major versions in compose (`mysql:8`, not `mysql:latest`)
- Always run with `restart: unless-stopped`
- Healthchecks are mandatory — the DB is a dependency for other stacks
- Named volumes for data (`mysql-data`), never bind mounts for DB state
- Init scripts go in `init/` and mount as `:ro`

---

## 🌐 Networking

- MySQL is **never** exposed on `0.0.0.0` — only on `127.0.0.1:3306` of the Pi (for SSH-tunnel admin)
- Cross-stack access happens via the external Docker network `shared-db-net`
- The network is created manually once: `docker network create shared-db-net` — don't try to auto-create it in compose
- Don't add MySQL to any other Docker network

---

## 🔐 Secrets handling

- `MYSQL_ROOT_PASSWORD` and per-app user passwords live in `.env` (gitignored)
- `.env.example` is the template — always keep it in sync
- Init SQL file contains placeholder passwords like `REPLACE_ME_APPNAME` — these must be edited before first deploy
- **Never commit `.env`**. Never commit a real password to `init/*.sql` — use `REPLACE_ME` placeholders and document the replacement step in README

---

## 🧑‍🏫 SQL conventions

- All `CREATE DATABASE` statements use `IF NOT EXISTS`
- All `CREATE USER` statements use `IF NOT EXISTS`
- All tables/DBs: `CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`
- Grant `ALL PRIVILEGES` scoped to `app_name.*` only — never grant global privileges to app users
- End every init script with `FLUSH PRIVILEGES;`
- One app per section, with a comment header identifying which app owns it

---

## 📜 Shell script conventions

- `#!/bin/bash` + `set -e` at the top of every script
- Source `.env` at the top: `set -a && source .env && set +a`
- Fail fast with clear error messages — don't let a missing env var turn into a cryptic Docker error
- Use `ssh rpi5` (the alias), not full `ssh user@host` strings — the alias is configured on the Mac
- All scripts must be executable (`chmod +x`) before committing

---

## 🚢 Deployment conventions

- `deploy.sh` is the **only** supported way to deploy from Mac
- The Pi's app lives at `/home/airlangga/apps/shared-db/` — don't put it elsewhere
- Never SSH in and run ad-hoc `docker` commands for deploys — if it's not in `deploy.sh`, it shouldn't be a deploy step
- `rsync --delete` so the Pi's copy mirrors the repo exactly

---

## 💾 Backup conventions

- Backups are gzipped SQL dumps in `backups/` (gitignored)
- `backup.sh` keeps the 14 most recent backups; older ones get pruned
- Restore path: `restore.sh path/to/backup.sql.gz` — must prompt for confirmation before overwriting
- Nightly cron runs via the Pi's user crontab, not root

---

## 📝 Commit messages

Conventional Commits format:

```
<type>: <short description>

[optional body]
```

**Types**: `feat`, `fix`, `chore`, `docs`, `refactor`, `ci`, `build`

Examples:
- `feat: add per-app init SQL for mikael_site`
- `fix: deploy.sh fails fast when shared-db-net is missing`
- `docs: document SSH-tunnel admin workflow`
- `chore: bump mysql to 8.4`

One logical change per commit. Subject line under ~72 chars.

---

## 🌿 Branching

- `main` is always deployable
- Feature branches: `feat/<thing>`, `fix/<thing>`, `docs/<thing>`
- Squash-merge to `main`
- For solo work, direct commits to `main` are fine

---

## ✅ Before considering any change "done"

1. `docker compose config` parses without errors
2. All scripts are executable (`ls -l *.sh` shows `x` permissions)
3. `.env.example` is up to date with any new env vars
4. No secrets committed (`git diff --cached` before `git commit`)
5. README updated if behaviour or setup steps changed

---

## 🚫 Do not

- Expose port 3306 on `0.0.0.0`
- Create the `shared-db-net` network inside compose (it must be external)
- Grant global/root privileges to per-app users
- Use `latest` tags on production images
- Commit `.env`, `backups/`, `*.sql.gz`, or `.DS_Store`
- Add a web UI (phpMyAdmin, Adminer) to the compose stack — use SSH tunnel + native clients instead
- Add additional databases (Postgres, Redis) to this repo — each deserves its own stack

---

## 🍓 Raspberry Pi context (important gotchas)

The deployment target has known quirks documented in Notion:

- **Tailscale DNS is disabled** on the Pi (`--accept-dns=false`) — do not re-enable it; it breaks DNS resolution
- **Docker daemon DNS** is set to `8.8.8.8`, `1.1.1.1` in `/etc/docker/daemon.json` — don't override
- WiFi-connected, ~40 Mbps — assume slow image pulls
- SSH alias: `rpi5` → user `airlangga` → hostname `mipi`
- Architecture: `arm64` — `mysql:8` is multi-arch so this is fine, but verify any new images

Debug on the Pi:
```bash
ssh rpi5
cd ~/apps/shared-db
docker compose logs -f mysql
docker exec -it shared-mysql mysql -uroot -p
```

---

## 🧠 When uncertain

- Prefer fewer moving parts over clever automation
- Prefer documented manual steps over magic (e.g. creating the network manually is better than auto-creating and complicating the graph)
- Prefer explicit over implicit (pinned versions, named volumes, explicit user grants)
- If a decision would meaningfully change architecture (e.g. adding replication, moving to Postgres), surface it before implementing

---

## 📚 Reference

- `SHARED_DB_SPEC.md` — bootstrap specification (what to build)
- `README.md` — end-user docs (how to run, deploy, back up)
- This file — how we work
