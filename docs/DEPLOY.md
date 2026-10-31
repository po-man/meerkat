# Deploying Meerkat

Meerkat runs as **one always-on container** on a small VM, reachable only through
a **Cloudflare Tunnel**. Cloudflare terminates TLS and proxies traffic; the host
never accepts inbound HTTP and needs no certificates.

```
ask.example.com ──► Cloudflare (DNS, TLS, CDN, WAF)
                          │  outbound-only tunnel
                          ▼
                    cloudflared ──► web:4000 ──► /data/prod.sqlite3
```

Why a single node: SQLite has a single writer, `Phoenix.Presence` and PubSub are
in-process, and `RoomExpiryScheduler` runs timers locally. **Never scale `web`
beyond one replica.**

## Prerequisites

- A host: Oracle Cloud Always Free `VM.Standard.A1.Flex` (2 OCPU / 12 GB, Ubuntu
  24.04 aarch64) is the intended target. `VM.Standard.E2.1.Micro` (amd64, 1 GB)
  also works.
- A domain hosted on Cloudflare (free plan is enough).
- Docker Engine + Compose plugin on the host.
- `sqlite3` and `rclone` on the host (backups).
- An R2 bucket (10 GB free) with an `rclone` remote named `r2`.

## One-time setup

### 1. Host firewall

Oracle's VCN security list is the real firewall. Allow **only** SSH, ideally
restricted to your IP:

| Direction | Port | Source |
|-----------|------|--------|
| Ingress | 22 | your IP |
| Egress | all | — |

Do not open 80/443/4000. The tunnel is outbound, so nothing else is reachable.

### 2. Docker

```bash
sudo apt-get update && sudo apt-get install -y docker.io docker-compose-v2 sqlite3 rclone
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"   # re-login afterwards
```

Make sure the Docker daemon starts at boot; `restart: unless-stopped` then brings
the stack back after a reboot.

### 3. Directory layout

```bash
sudo mkdir -p /srv/meerkat/{data,backups}
sudo chown 65534:65534 /srv/meerkat/data      # the container runs as `nobody`
git clone git@github.com:po-man/meerkat.git /srv/meerkat
cd /srv/meerkat
```

`data/` holds the live SQLite database. It must be readable/writable by UID
`65534` (`nobody`), which is the user inside the image.

### 4. Secrets

```bash
cd /srv/meerkat
install -m 600 deploy/env.prod.sample deploy/env.prod
install -m 600 deploy/tunnel.env.sample deploy/tunnel.env
openssl rand -base64 48     # paste into SECRET_KEY_BASE
```

`deploy/env.prod`:

| Variable | Meaning |
|----------|---------|
| `PHX_HOST` | Public hostname, bare (no scheme), e.g. `ask.example.com`. Used for links and moderator QR codes; the app refuses to boot without it. |
| `SECRET_KEY_BASE` | Cookie/session signing key. Rotating it logs everyone out. |
| `ADMIN_ACCESS_CODE` | Code used on the secret admin path to create the first admin. |
| `DATABASE_PATH` | Always `/data/prod.sqlite3` (the mounted volume). |
| `PORT` / `POOL_SIZE` | Defaults `4000` / `5` are fine. |

### 5. Cloudflare Tunnel

```bash
cloudflared tunnel login
cloudflared tunnel create meerkat
cloudflared tunnel token meerkat          # paste into deploy/tunnel.env
cloudflared tunnel route dns meerkat ask.example.com
```

Then in the Cloudflare dashboard:

- **SSL/TLS → Overview**: mode **Full** (or Full (strict)).
- **SSL/TLS → Edge Certificates**: enable **Always Use HTTPS**.
- **Speed → Optimization**: **Rocket Loader off** (it interferes with LiveView's
  client JS).
- Optional, recommended: a cache rule `Cache Everything` for `ask.example.com/assets/*`
  — digested filenames never change, so this cuts origin egress.

### 6. Backups

```bash
cd /srv/meerkat
sudo ln -s /srv/meerkat/deploy/meerkat-backup.service /etc/systemd/system/
sudo ln -s /srv/meerkat/deploy/meerkat-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now meerkat-backup.timer
sudo systemctl start meerkat-backup.service      # prove it works now
journalctl -u meerkat-backup.service -n 20
```

The script takes a transactionally consistent `VACUUM INTO` snapshot (safe while
the app is running), uploads it to R2, then prunes local copies older than 7 days.

### 7. First start

```bash
cd /srv/meerkat
IMAGE_TAG=latest docker compose -f compose.prod.yml up -d
docker compose -f compose.prod.yml ps          # web should become healthy
curl -fsS http://127.0.0.1:4000/healthz        # ok
curl -fsS https://ask.example.com/healthz      # ok, through the tunnel
```

Migrations run automatically on boot (`Ecto.Migrator` in the supervision tree).
`bin/migrate` / `bin/qa_app eval` are available inside the container if you need
to run them by hand.

Then open `https://ask.example.com/<secret admin path>` and create the first
admin account with `ADMIN_ACCESS_CODE`.

## Deploying a release

Push a tag; GitHub Actions builds an arm64 image, pushes it to GHCR, and runs the
deploy step over SSH:

```bash
git tag release.2026.10.31.1 && git push origin release.2026.10.31.1
```

Manually, on the host:

```bash
cd /srv/meerkat
IMAGE_TAG=release.2026.10.31.1 docker compose -f compose.prod.yml pull web
IMAGE_TAG=release.2026.10.31.1 docker compose -f compose.prod.yml up -d --no-deps web
curl -fsS http://127.0.0.1:4000/healthz
```

### Rollback

Re-run the workflow with the previous `image_tag` (`workflow_dispatch`), or:

```bash
IMAGE_TAG=release.<previous> docker compose -f compose.prod.yml up -d --no-deps web
```

Migrations are applied automatically and never reversed by a rollback, so any
schema change must be **backwards compatible with the previous image**
(expand/contract: add columns in one release, drop them in a later one).

## Day-2 operations

```bash
docker compose -f compose.prod.yml logs -f web        # application logs
docker compose -f compose.prod.yml ps                 # health status
docker exec meerkat-web-1 bin/qa_app rpc 'QaApp.Repo.aggregate(QaApp.Events.Room, :count)'
```

Restore drill (do this before you need it):

```bash
# 1. Pull the latest snapshot and prove it is a healthy SQLite database.
rclone copy r2:meerkat-backups/ /tmp/restore/
sqlite3 /tmp/restore/prod-<date>.sqlite3 'PRAGMA integrity_check; SELECT count(*) FROM events_rooms;'

# 2. Restore: stop the stack, swap the file, fix ownership (container user), start.
cd /srv/meerkat
docker compose -f compose.prod.yml down
cp /tmp/restore/prod-<date>.sqlite3 data/prod.sqlite3
rm -f data/prod.sqlite3-wal data/prod.sqlite3-shm
sudo chown 65534:65534 data/prod.sqlite3
docker compose -f compose.prod.yml up -d
curl -fsS http://127.0.0.1:4000/healthz
```

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| Container exits with `environment variable ADMIN_ACCESS_CODE is missing` | `deploy/env.prod` is missing or unreadable by the `docker` user. |
| Container exits with `environment variable PHX_HOST is missing` | Same. `PHX_HOST` must be a bare hostname. |
| `SQLite3.Error: unable to open database file` | `/srv/meerkat/data` is not owned by UID `65534`. |
| 502 from Cloudflare | `web` is unhealthy or restarting: `docker compose ps`, then logs. |
| LiveView connects then immediately drops | Socket origin rejected. `PHX_HOST` must equal the public hostname; see the "Could not check origin" error in the logs. |
| `database is locked` under load | Unexpected: the app uses WAL + `busy_timeout`. Check that only one `web` replica is running. |

## Costs

This setup is **$0/month** on Oracle Always Free + Cloudflare Free + R2's 10 GB
free tier. The only paid risk is exceeding Oracle's Always Free limits (2 OCPU /
12 GB A1, 200 GB block storage, 10 TB egress); leaving the shape at the quotas
above keeps it at zero.
