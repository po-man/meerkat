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

- A host: Google Cloud **Always Free e2-micro** (Ubuntu 24.04, `us-central1`) is
  the current target — see [GCP.md](GCP.md) for the console walkthrough. Oracle
  Cloud `VM.Standard.A1.Flex` also works if you rebuild for arm64; see
  [ORACLE.md](ORACLE.md).
- A domain hosted on Cloudflare (free plan is enough).
- An R2 bucket (10 GB free) with an `rclone` remote named `r2`.

## One-time setup

### 1. Create the VM

Follow [GCP.md](GCP.md): project, budget alert, firewall rule (SSH from your IP
only, no 80/443), the e2-micro instance, and the deploy user. Everything below
happens over SSH on that host.

> On GCP the SSH user is **your own username**, not `ubuntu` — run `whoami` on
> the host and use that for `DEPLOY_USER` and for the `chown` below.

### 2. Clone and bootstrap

```bash
sudo mkdir -p /srv && sudo chown "$USER:$USER" /srv
git clone git@github.com:po-man/meerkat.git /srv/meerkat
cd /srv/meerkat
sudo bash deploy/bootstrap.sh
```

`bootstrap.sh` is idempotent and does the error-prone parts:

- installs Docker Engine + Compose v2, `sqlite3`, `rclone`, `openssl`,
- enables Docker at boot (so `restart: unless-stopped` survives a reboot),
- creates `data/` owned by `65534` (`nobody`, the user inside the image) and
  `backups/`,
- generates `deploy/env.prod` from the sample with a random `SECRET_KEY_BASE`,
- installs and enables the nightly backup timer,
- prints a preflight report of anything still missing.

Use `bash deploy/bootstrap.sh --check` any time to only re-run the report.

### 3. Secrets

```bash
nano /srv/meerkat/deploy/env.prod      # PHX_HOST, ADMIN_ACCESS_CODE
nano /srv/meerkat/deploy/tunnel.env    # CLOUDFLARE_TUNNEL_TOKEN
```

`deploy/env.prod`:

| Variable | Meaning |
|----------|---------|
| `PHX_HOST` | Public hostname, bare (no scheme), e.g. `ask.example.com`. Used for links and moderator QR codes; the app refuses to boot without it. |
| `SECRET_KEY_BASE` | Cookie/session signing key. Rotating it logs everyone out. |
| `ADMIN_ACCESS_CODE` | Code used on the secret admin path to create the first admin. |
| `DATABASE_PATH` | Always `/data/prod.sqlite3` (the mounted volume). |
| `PORT` / `POOL_SIZE` | Defaults `4000` / `5` are fine. |

Both files must stay `600` and owned by the deploy user: the deploy step runs
`docker compose` as that user, which reads them.

### 4. Registry access

The host pulls `ghcr.io/po-man/meerkat`. Either make the package public, or:

```bash
docker login ghcr.io -u <github-user> --password-stdin   # token with read:packages
```

### 5. Cloudflare Tunnel

Run this on your laptop (it needs a browser), not on the host:

```bash
cloudflared tunnel login
cloudflared tunnel create meerkat
cloudflared tunnel token meerkat          # paste into deploy/tunnel.env on the host
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

`bootstrap.sh` already installed and enabled the timer; only the R2 credentials
are missing:

```bash
rclone config            # create a remote named "r2" (S3-compatible, endpoint from the R2 dashboard)
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

Tag a commit on `main`; GitHub Actions runs the tests, builds the arm64 image,
pushes it to GHCR, and deploys it over SSH:

```bash
git tag release.2026.10.31.1
git push origin release.2026.10.31.1
```

The pipeline (`.github/workflows/release.yml`):

1. **verify** — the tag must match `release.YYYY.MM.DD.X` and the commit must be
   an ancestor of `main`.
2. **test** — runs the same workflow as every PR (`mix precommit`).
3. **build-push** — `ghcr.io/po-man/meerkat:<tag>` plus `:latest`, arm64 only.
4. **deploy** — over SSH: `git fetch` + `git checkout <tag>` in `/srv/meerkat`
   (so the compose file and deploy scripts always match the running image),
   `docker compose pull`, `up -d --no-deps web`, then polls `/healthz` for up to
   60 s. A failing probe fails the deployment.

### Dry run

Run the **Release** workflow manually with `dry_run` enabled to exercise the
pipeline without a host: tests run, the image is built and pushed, but only under
the scratch tag `ghcr.io/po-man/meerkat:dry-run-<sha>` — no release tag, no
`:latest` move, no deployment. Useful as a first end-to-end check before the VM
and deploy secrets exist.

### GitHub setup

Repository secrets (Settings → Secrets and variables → Actions):

| Secret | Value |
|--------|-------|
| `DEPLOY_HOST` | Public IP or hostname of the VM. |
| `DEPLOY_USER` | SSH user (member of the `docker` group). On GCP this is **your own username** (`whoami` on the host), on Oracle it is `ubuntu`. |
| `DEPLOY_SSH_KEY` | Private key for that user (paste the whole key, including header/footer). |

Two host-side requirements the pipeline depends on:

- **Read access to the repo**, because the deploy step does `git fetch` in
  `/srv/meerkat`. Use a read-only deploy key for the host.
- **Read access to the GHCR package**, because the deploy step runs
  `docker compose pull`. Either make `ghcr.io/po-man/meerkat` public, or run
  `docker login ghcr.io -u <user> --password-stdin` once on the host with a
  token that has `read:packages`.

Optional hardening: add `fingerprint: <host key fingerprint>` to the SSH step.

The host checkout is managed by the pipeline: `git checkout --force <tag>` means
local edits to tracked files (compose file, deploy scripts) are discarded on every
deploy. Keep host-specific settings in `deploy/env.prod`, which is gitignored.

### Deploying by hand

```bash
cd /srv/meerkat
IMAGE_TAG=release.2026.10.31.1 docker compose -f compose.prod.yml pull web
IMAGE_TAG=release.2026.10.31.1 docker compose -f compose.prod.yml up -d --no-deps web
curl -fsS http://127.0.0.1:4000/healthz
```

### Rollback

Run the **Release** workflow manually (`workflow_dispatch`) with the previous
`image_tag`. Nothing is rebuilt or retagged — the existing image is redeployed,
so the rollback is exactly the code that ran before. Manually:

```bash
IMAGE_TAG=release.<previous> docker compose -f compose.prod.yml up -d --no-deps web

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
