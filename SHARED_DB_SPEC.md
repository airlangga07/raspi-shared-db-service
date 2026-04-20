# shared-db — Project Spec

Instruction file for Claude Code. Bootstrap a new repo that runs a **shared MySQL** service on the Raspberry Pi, consumable by multiple app stacks via a shared Docker network.

---

## 🎯 Goal

A minimal, standalone repo that:
1. Runs MySQL 8 in Docker as a **long-lived, shared database service** on the Pi
2. Creates an **external Docker network** (`shared-db-net`) so other app stacks can opt in
3. Provisions **per-app databases and users** from SQL init scripts
4. Is **not exposed** to the Pi's LAN or the public internet — only to containers on `shared-db-net`, plus localhost on the Pi for SSH-tunnel admin access
5. Includes a simple backup script and a one-command deploy from the local Mac

---

## 🧱 Stack

| Layer | Choice |
|---|---|
| Database | MySQL 8 |
| Base image | `mysql:8` (multi-arch — supports arm64) |
| Container runtime | Docker + Docker Compose |
| Target arch | linux/arm64 (Raspberry Pi 5) |
| Network model | External Docker network, joined by DB and each app |

---

## 🌍 Deployment context

- SSH alias: `rpi5`
- Remote user: `airlangga`
- Remote app root: `/home/airlangga/apps/shared-db`
- Pi has Docker v29.4.0 + Docker Compose plugin
- Pi Docker daemon DNS: `8.8.8.8`, `1.1.1.1` (don't override)

---

## 📁 Repo structure

```
shared-db/
├── .dockerignore
├── .env.example
├── .gitignore
├── README.md
├── backup.sh
├── deploy.sh
├── docker-compose.yml
├── restore.sh
└── init/
    └── 01-create-app-databases.sql
```

No Dockerfile — this uses the upstream `mysql:8` image as-is.

---

## 📝 File specs

### `docker-compose.yml`

One service (`mysql`) plus an external-network declaration:

```yaml
services:
  mysql:
    image: mysql:8
    container_name: shared-mysql
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
    command:
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_unicode_ci
      - --default-authentication-plugin=caching_sha2_password
    volumes:
      - mysql-data:/var/lib/mysql
      - ./init:/docker-entrypoint-initdb.d:ro
    networks:
      - shared-db-net
    ports:
      - "127.0.0.1:3306:3306"   # localhost-only on Pi, for SSH-tunnel admin
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-uroot", "-p${MYSQL_ROOT_PASSWORD}"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s

networks:
  shared-db-net:
    external: true   # must be created manually once: docker network create shared-db-net

volumes:
  mysql-data:
```

Key rules:
- **No `ports:` published to `0.0.0.0`** — only `127.0.0.1:3306:3306`
- **`shared-db-net` is external** — created once with `docker network create shared-db-net`
- Init scripts run only on first boot (empty data volume)

### `init/01-create-app-databases.sql`

Seed with databases and users for known apps. Use placeholder passwords that the user replaces before first deploy. Example:

```sql
-- mikaelairlangga-site
CREATE DATABASE IF NOT EXISTS mikael_site CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'mikael_site_user'@'%' IDENTIFIED BY 'REPLACE_ME_MIKAEL_SITE';
GRANT ALL PRIVILEGES ON mikael_site.* TO 'mikael_site_user'@'%';

FLUSH PRIVILEGES;
```

Add a prominent README section explaining: **these scripts only run on first boot**. To add a database later, run SQL manually via `docker exec`.

### `.env.example`

```
MYSQL_ROOT_PASSWORD=generate-a-strong-random-password-and-store-in-1password
```

### `.gitignore`
Standard + `.env`, `backups/`, `*.sql.gz`, `.DS_Store`.

### `.dockerignore`
`.git`, `.env`, `backups/`, `README.md`.

### `deploy.sh`

Bash script that:
1. Verifies `.env` exists locally
2. Verifies `shared-db-net` exists on Pi (SSH over + run `docker network inspect shared-db-net` — if it fails, run `docker network create shared-db-net`)
3. `rsync -avz --delete` the repo to `airlangga@rpi5:/home/airlangga/apps/shared-db/` (exclude `.git`, `backups`, `.DS_Store`)
4. SSH in and run: `cd ~/apps/shared-db && docker compose pull && docker compose up -d`
5. Wait for healthcheck, then print `docker compose ps`

Make executable (`chmod +x deploy.sh`).

### `backup.sh`

Run **on the Pi** (or via SSH). Dumps all databases to a gzipped file:

```bash
#!/bin/bash
set -e
BACKUP_DIR="${BACKUP_DIR:-/home/airlangga/apps/shared-db/backups}"
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUT="$BACKUP_DIR/all-databases-$TIMESTAMP.sql.gz"

docker exec shared-mysql \
  mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" \
  --all-databases --single-transaction --routines --triggers \
  | gzip > "$OUT"

echo "Backup written: $OUT"

# Keep only the 14 most recent backups
ls -1t "$BACKUP_DIR"/all-databases-*.sql.gz | tail -n +15 | xargs -r rm --
```

Sources `MYSQL_ROOT_PASSWORD` from `.env` at the top. Document in README how to schedule via cron on the Pi:

```
0 3 * * * cd /home/airlangga/apps/shared-db && ./backup.sh >> backups/backup.log 2>&1
```

### `restore.sh`

Reverse operation. Takes a backup path as arg, pipes `gunzip` into `docker exec ... mysql` as root. Include a `read -p "Are you sure? This will overwrite current data [y/N]: "` confirmation. Document usage in README.

### `README.md`

Sections:
1. **What this is** — shared MySQL service for Pi apps
2. **Architecture diagram** — ASCII showing apps → shared-db-net → shared-mysql
3. **First-time setup** — the exact order of operations (see below)
4. **Adding a new app** — how to provision a new DB/user and wire up from an app compose file
5. **Backups** — how `backup.sh` works, how to schedule, where backups go
6. **Restore** — `./restore.sh backups/<file>.sql.gz`
7. **Admin access from Mac** — SSH tunnel + connect via local MySQL client

---

## 🚀 First-time setup (document in README)

```bash
# 1. On the Pi, create the shared network (once, outside any compose project)
ssh rpi5 "docker network create shared-db-net"

# 2. Locally, copy .env.example and fill in a strong root password
cp .env.example .env
# edit .env

# 3. Deploy
./deploy.sh

# 4. Verify health
ssh rpi5 "docker compose -f ~/apps/shared-db/docker-compose.yml ps"
```

---

## 🔌 How apps consume this DB (document in README)

In an app's `docker-compose.yml`:

```yaml
services:
  web:
    # ...
    environment:
      DB_HOST: shared-mysql    # resolves via Docker DNS on shared-db-net
      DB_PORT: 3306
      DB_NAME: <app_database>
      DB_USER: <app_user>
      DB_PASSWORD: ${DB_PASSWORD}
    networks:
      - shared-db-net
      - default

networks:
  shared-db-net:
    external: true
  default:
```

The app's compose stack does **not** need to run its own MySQL — it just joins the network.

---

## ✅ Done criteria

- [ ] `docker network create shared-db-net` succeeds on the Pi
- [ ] `./deploy.sh` brings up the `shared-mysql` container and it reports healthy
- [ ] `docker exec -it shared-mysql mysql -uroot -p` works from the Pi
- [ ] A test app container on `shared-db-net` can `ping shared-mysql` and open a TCP connection to port 3306
- [ ] `3306` is **not** reachable from the Pi's LAN IP (only from `127.0.0.1` and `shared-db-net`)
- [ ] `./backup.sh` produces a gzipped dump
- [ ] `./restore.sh` restores it cleanly after wiping the DB in a test container
- [ ] README covers first-time setup, adding an app, backup, and restore

---

## 🚫 Out of scope for v1

- Replication, HA, failover
- Managed backups to S3/B2 (v1 is local file + retention)
- Prometheus / Grafana metrics (add later if needed)
- Postgres alongside MySQL (add a separate service later if desired)
- Automatic per-app user provisioning via API (manual SQL is fine at this scale)

---

## 📌 Notes for Claude Code

- `git init` the repo and make an initial commit after scaffolding
- Ensure scripts are executable (`chmod +x deploy.sh backup.sh restore.sh`)
- Do NOT commit `.env`, only `.env.example`
- Do NOT commit `backups/`
- Verify `docker compose config` parses cleanly before considering done
- Init SQL should use `IF NOT EXISTS` so re-running is safe (even though it normally won't re-run)
