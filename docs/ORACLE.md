# Oracle Cloud setup (Always Free)

One-time, console-side setup for the host that runs Meerkat. Budget 30–60
minutes, most of it waiting for the instance to boot.

Target: **VM.Standard.A1.Flex, 2 OCPU / 12 GB, Ubuntu 24.04 aarch64**. This is
the current Always Free Ampere allowance (Oracle halved it from 4/24 on
2026-06-15 — do not request more or you will be billed).

## 1. Account and billing

1. Sign in at <https://cloud.oracle.com>.
2. Note your **home region** — it cannot be changed later. Pick the one closest
   to your audience; A1 capacity differs per region and availability domain.
3. **Recommended: upgrade to Pay As You Go** (Billing & Cost Management →
   Upgrade to Paid). Always Free resources still cost $0 on PAYG, but:
   - idle Always Free instances are **not** reclaimed (on a free tenancy Oracle
     can stop them after 7 days of low CPU/network/memory use),
   - A1 capacity is easier to get.

## 2. Network

1. Networking → **Virtual Cloud Networks** → **Start VCN Wizard** →
   *Create VCN with Internet Connectivity*.
2. Name it `meerkat`, keep the defaults (10.0.0.0/16), create.
3. Open the VCN → **Security Lists** → *Default Security List*:
   - **remove** the default `0.0.0.0/0 → TCP 22` rule,
   - **add** `TCP 22` from **your IP only** (Ingress).
   - Do **not** add 80/443. Nothing else needs to be reachable; traffic arrives
     through the Cloudflare Tunnel, which dials out.

## 3. Instance

Compute → **Instances** → **Create instance**:

| Field | Value |
|-------|-------|
| Name | `meerkat` |
| Placement | default availability domain |
| Image | **Canonical Ubuntu 24.04** (aarch64 build) |
| Shape | **Ampere** → `VM.Standard.A1.Flex`, **2 OCPU**, **12 GB** |
| Primary network | the `meerkat` VCN, public subnet, **assign a public IPv4** |
| SSH keys | paste your **public** key (or let Oracle generate a pair and download the private key) |
| Boot volume | *Specify a custom boot volume size* → **100 GB** (200 GB is the Always Free total) |

Public IPv4 addresses for Always Free instances are included (six per tenancy),
so this stays at $0.

If you get **"Out of host capacity"**: retry, try another availability domain,
or try again later — it is the single most common blocker. As a fallback you can
use `VM.Standard.E2.1.Micro` (amd64, 1 GB), but then the Docker image must be
built for `linux/amd64`: change `platforms` in `.github/workflows/ci.yml` and
`release.yml` and `runs-on: ubuntu-24.04` for the build jobs.

## 4. First login

```bash
ssh ubuntu@<public-ip>          # or: ssh -i ~/.ssh/meerkat ubuntu@<public-ip>
```

`ubuntu` has passwordless sudo. Ubuntu's cloud image only accepts key auth.

## 5. Bootstrap the host

The deploy pipeline needs the repository checked out at `/srv/meerkat`, so give
the host read access first:

```bash
ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519     # if the host has no key yet
cat ~/.ssh/id_ed25519.pub
```

Add that public key in GitHub → repo → **Settings → Deploy keys → Add deploy
key** (leave *Allow write access* unchecked).

```bash
# on the host
sudo mkdir -p /srv && sudo chown ubuntu:ubuntu /srv
git clone git@github.com:po-man/meerkat.git /srv/meerkat
cd /srv/meerkat
sudo bash deploy/bootstrap.sh
```

The script installs Docker + Compose v2, sqlite3 and rclone, creates
`data/` with the UID the container runs as, generates `deploy/env.prod` with a
random `SECRET_KEY_BASE`, installs the nightly backup timer, and prints a
preflight report. Re-run it any time (`bash deploy/bootstrap.sh --check` to only
inspect).

Then fill in the two secrets it cannot know:

```bash
nano /srv/meerkat/deploy/env.prod     # PHX_HOST, ADMIN_ACCESS_CODE
nano /srv/meerkat/deploy/tunnel.env   # CLOUDFLARE_TUNNEL_TOKEN
```

## 6. Container registry access

The host pulls `ghcr.io/po-man/meerkat`. Either make the package public
(GitHub → your profile → Packages → the package → Settings → Change
visibility), or log in once:

```bash
docker login ghcr.io -u <github-user> --password-stdin   # token with read:packages
```

## 7. Then

Continue with [DEPLOY.md](DEPLOY.md#5-cloudflare-tunnel), which covers the
tunnel, DNS, the GitHub secrets, the first start and the release flow.

## Operating notes

- **Idle reclamation** only applies to free tenancies; the PAYG upgrade above
  removes it. If an instance is ever stopped, the boot volume survives and
  `restart: unless-stopped` brings the stack back on boot.
- **Reboots**: Docker is enabled at boot and the stack restarts itself.
- **Disk**: 100 GB is plenty; the SQLite database is a few MB. Watch
  `df -h /` if logs are ever unbounded (they are capped at 3 × 10 MB).
- **Capacity**: you can change the shape only by stopping the instance; keep it
  at 2 OCPU / 12 GB.
