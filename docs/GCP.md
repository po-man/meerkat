# Google Cloud setup (Always Free e2-micro)

Console-side setup for the host that runs Meerkat. The current deployment target:
**e2-micro, Ubuntu 24.04, `us-central1`**, which is one of the three regions where
the always-free tier applies.

Free allowance per month: **1 non-preemptible e2-micro** (744 h, by time not by
instance), **30 GB standard disk**, **1 GB egress from North America**. Stay
inside that and the VM costs $0 — the console's price estimate shows list price
(~$6.11/mo) and does not subtract the free allowance.

## 1. Project and billing

1. <https://console.cloud.google.com> → create/select a project (e.g. `meerkat`).
2. Link a billing account. A card is required even when usage stays free.
3. **Billing → Budgets & alerts** → create a **$1** budget with email alerts.
   This is your alarm for the two things that are *not* in the free allowance
   (see "What can cost money" below).

## 2. Network

A firewall rule decides who may reach the box. The tunnel is outbound-only, so
the only rule you need is SSH.

Compute Engine → **VPC network → Firewall**:

- **Create** `allow-ssh-meerkat`: direction *Ingress*, targets = tag `meerkat`,
  source IPv4 range = **your IP/32** (`curl -4 ifconfig.me`), protocol `tcp:22`.
- **Delete** `default-allow-ssh` (it allows `0.0.0.0/0`).
- Add nothing for 80/443. Ports stay closed.

## 3. Instance

Compute Engine → **VM instances → Create instance**:

| Field | Value |
|-------|-------|
| Name | `meerkat` |
| Region / zone | `us-central1` (or `us-west1`, `us-east1`), zone *Any* |
| Machine type | **e2-micro** (2 vCPU shared, 1 GB) |
| Boot disk | **Ubuntu 24.04 LTS**, **Standard** persistent disk, **20 GB** (30 GB max) |
| Network tag | `meerkat` ← the firewall rule matches on this |
| External IP | *Ephemeral* (default) |

e2-micro is **x86_64**, which is why the image is published as `linux/amd64`.

## 4. Connect

```bash
gcloud compute ssh --zone "us-central1-c" meerkat --project "<your-project>"
whoami    # this is your DEPLOY_USER — on GCP it is your own username, not `ubuntu`
```

Then continue with [DEPLOY.md](DEPLOY.md#2-clone-and-bootstrap): create a deploy
key, clone into `/srv/meerkat`, run `sudo bash deploy/bootstrap.sh`, fill the two
env files, log in to GHCR, and start the stack.

`bootstrap.sh` uses `SUDO_USER`, so it works for any username; `/srv` must be
owned by that user (`sudo chown $USER:$USER /srv` before cloning).

## What can cost money

| Item | Cost | Notes |
|------|------|-------|
| e2-micro hours | $0 | Free for 744 h/month, one instance |
| 20 GB standard disk | $0 | 30 GB is the free ceiling; Standard only (not Balanced/SSD) |
| External IPv4 | **~$0.005/h ≈ $3.65/mo** | Not listed in the free allowance. Check `Billing → Reports` after a day; the $1 budget alert will tell you. |
| Egress | **1 GB/month free**, then ~$0.12/GB | The real constraint. Cloudflare caches `/assets/*`; HTML and WebSocket frames still count. |

If the external IP is billed and you want to stay at $0, remove it and reach the
host through IAP instead (`gcloud compute ssh --tunnel-through-iap`), with a
Cloud NAT (~$1.40/mo) for `cloudflared`'s outbound connections. That trades
~$3.65 for ~$1.40 plus extra setup — decide once the first bill is visible.

Reduce egress: keep the Cloudflare cache rule for `/assets/*` enabled, and avoid
serving large media from the app.

## Operating notes

- **Reboots**: Docker is enabled at boot and `restart: unless-stopped` brings the
  stack back. GCP may live-migrate the VM during maintenance; that is transparent.
- **Resizing**: `e2-micro` is the free shape. Anything larger is billed hourly, so
  keep it.
- **Disk**: 20 GB holds the OS, Docker images (~200 MB) and a SQLite database of a
  few MB with plenty of room.
- **1 GB RAM is enough, but add swap as insurance** against an OOM kill during a
  busy event:
  ```bash
  sudo fallocate -l 1G /swapfile && sudo chmod 600 /swapfile
  sudo mkswap /swapfile && sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  ```
- **Switching to Oracle A1 later**: change `linux/amd64` → `linux/arm64` and
  `runs-on: ubuntu-24.04` → `ubuntu-24.04-arm` in `ci.yml` and `release.yml`.
  Nothing else in the repo is architecture-specific.
