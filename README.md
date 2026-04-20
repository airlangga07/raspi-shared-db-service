# raspi-shared-db-service

Shared MySQL 8 service for the Raspberry Pi. Runs as a standalone Docker Compose stack; other app stacks on the Pi join the `shared-db-net` Docker network to reach it.

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│                Raspberry Pi 5                   │
│                                                 │
│  ┌──────────────┐      ┌──────────────────────┐ │
│  │  app stack A │      │    app stack B       │ │
│  │  (web, etc.) │      │    (web, etc.)       │ │
│  └──────┬───────┘      └──────────┬───────────┘ │
│         │                         │             │
│         └─────────┬───────────────┘             │
│                   │  shared-db-net              │
│          ┌────────▼────────┐                    │
│          │  shared-mysql   │  (mysql:8)          │
│          └─────────────────┘                    │
│                   │                             │
│           127.0.0.1:3306 (SSH-tunnel admin only) │
└─────────────────────────────────────────────────┘
```

---

## First-time setup

### 1. Create the shared network on the Pi (once only)

```bash
ssh rpi5 'docker network create shared-db-net'
```

### 2. Set secrets

```bash
cp .env.example .env
# Edit .env — set MYSQL_ROOT_PASSWORD to a strong random value, store in 1Password
```

### 3. Set per-app passwords

Edit `init/01-create-app-databases.sql` and replace every `REPLACE_ME_*` placeholder with a strong, unique password. Store each in 1Password.

> **Note:** Init scripts only run on first boot (when the data volume is empty). To add a database after the first deploy, use `docker exec` — see [Adding a new app](#adding-a-new-app).

### 4. Deploy

```bash
./deploy.sh
```

### 5. Verify

```bash
ssh rpi5 'docker compose -f ~/apps/shared-db/docker-compose.yml ps'
```

The `shared-mysql` container should show `healthy`.

---

## Adding a new app

**Provision the database/user** (after first deploy, init scripts won't re-run):

```bash
ssh rpi5
docker exec -it shared-mysql mysql -uroot -p

-- inside MySQL:
CREATE DATABASE IF NOT EXISTS my_app CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'my_app_user'@'%' IDENTIFIED BY 'a-strong-password';
GRANT ALL PRIVILEGES ON my_app.* TO 'my_app_user'@'%';
FLUSH PRIVILEGES;
```

**Wire up the app's `docker-compose.yml`:**

```yaml
services:
  web:
    environment:
      DB_HOST: shared-mysql   # resolves via Docker DNS on shared-db-net
      DB_PORT: 3306
      DB_NAME: my_app
      DB_USER: my_app_user
      DB_PASSWORD: ${DB_PASSWORD}
    networks:
      - shared-db-net
      - default

networks:
  shared-db-net:
    external: true
  default:
```

---

## Backups

`backup.sh` runs on the Pi and produces a gzipped `mysqldump` in `backups/`. It retains the 14 most recent files and prunes older ones automatically.

**Run manually:**

```bash
ssh rpi5
cd ~/apps/shared-db
./backup.sh
```

**Schedule nightly via cron** (`crontab -e` on the Pi):

```
0 3 * * * cd /home/airlangga/apps/shared-db && ./backup.sh >> backups/backup.log 2>&1
```

---

## Restore

```bash
ssh rpi5
cd ~/apps/shared-db
./restore.sh backups/all-databases-YYYYMMDD-HHMMSS.sql.gz
```

You will be prompted to confirm before any data is overwritten.

---

## Admin access from Mac

Open an SSH tunnel, then connect with any MySQL client:

```bash
# Terminal 1 — keep this open
ssh -L 3307:localhost:3306 rpi5

# Terminal 2 — connect via tunnel
mysql -h 127.0.0.1 -P 3307 -uroot -p
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `deploy.sh` exits: `shared-db-net not found` | Network not created yet | `ssh rpi5 'docker network create shared-db-net'` |
| Container stuck in `starting` | Wrong `MYSQL_ROOT_PASSWORD` or init SQL syntax error | Check `docker compose logs -f mysql` on Pi |
| App can't reach `shared-mysql:3306` | App not on `shared-db-net` | Add network to app's compose file (see above) |
| Auth failure as root | `.env` not synced to Pi | Re-run `./deploy.sh --with-env` |

**Debug on the Pi:**

```bash
ssh rpi5
cd ~/apps/shared-db
docker compose logs -f mysql
docker exec -it shared-mysql mysql -uroot -p
```

---

## Reference

- [`SHARED_DB_SPEC.md`](./SHARED_DB_SPEC.md) — bootstrap specification
- [`CLAUDE.md`](./CLAUDE.md) — project conventions for Claude Code
