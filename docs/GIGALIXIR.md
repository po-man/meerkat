# Deploying the demo to Gigalixir (free tier)

This is a **second, parallel deployment** used as a demo/staging environment.
The production stack described in [DEPLOY.md](DEPLOY.md) is unchanged: it keeps
running on a single VM with SQLite behind Cloudflare Tunnel.

Gigalixir's free tier cannot run this app on SQLite because its disk is
**ephemeral** — the database file is wiped on every restart and deploy. The
Gigalixir build therefore uses Gigalixir's free Postgres database.

Production builds default to Postgres. The Dockerfile explicitly sets
`QA_ECTO_ADAPTER=sqlite` so the VM/Cloudflare stack keeps using SQLite.

```
GitHub tag rel.gigalixir.*
        │
        ▼
GitHub Actions ── tests ──► git push gigalixir ──► buildpacks
                                                      │
                                                      ▼
                              meerkat.gigalixirapp.com ──► free Postgres
```

## What the free tier gives you

| Resource | Limit | Consequence |
|---|---|---|
| Instances | 1 instance, size 0.5 (500 MB RAM) | Matches the app's single-node design (PubSub, Presence, VoteStore, expiry timer). |
| Disk | Ephemeral | SQLite is impossible; Postgres is required. |
| Postgres | 2 connections, 10,000 rows, no backups | Fine for a demo. A busy event can exceed 10k rows. |
| SSH | Not available | `gigalixir ps:migrate` / remote console do not work; migrations run at boot. |
| Inactivity | Scaled to 0 after 30 days without a deploy | Tagging a release keeps it alive. |
| WebSockets / TLS / custom domains | Supported | LiveView works. |

This database is explicitly **not suitable for production**. Use the VM stack
(or a Gigalixir Standard database) for real events.

## One-time setup

```bash
# Install the CLI and log in (already done on the owner's machine).
curl https://get.gigalixir.com/cli | bash
gigalixir login
gigalixir account

# The app name is global and permanent.
gigalixir create -n meerkat

# Free Postgres; also sets DATABASE_URL and POOL_SIZE.
gigalixir pg:create --free
gigalixir ps:scale --replicas=1 --size=0.5

gigalixir config:set \
  POOL_SIZE=1 \
  PHX_HOST=meerkat.gigalixirapp.com \
  ADMIN_ACCESS_CODE=<secret>
```

Notes:

- `POOL_SIZE=1` is deliberate. During a zero-downtime deploy Gigalixir runs the
  old and new instance side by side, and the free database allows only **two**
  connections in total.
- `SECRET_KEY_BASE`, `DATABASE_URL`, and `PORT` are injected by Gigalixir.
- `DATABASE_SSL` defaults to `true`; it is only set to `false` for local/CI
  Postgres instances.

## Migrations

`rel/overlays/Procfile` runs `bin/migrate` before `bin/server`:

```
web: /app/bin/migrate && /app/bin/server
```

The application's supervision tree also runs `Ecto.Migrator` on release boot,
so the Procfile step is a belt-and-braces check that fails the boot if the
schema cannot be applied. Ecto's advisory lock makes concurrent boots safe.

## Deploying

Deploys are tag driven and independent of the VM's `release.*` tags:

```bash
git tag rel.gigalixir.2026.11.02.1
git push origin rel.gigalixir.2026.11.02.1
```

`.github/workflows/gigalixir.yml`:

1. **verify** — the tag must match `rel.gigalixir.YYYY.MM.DD.X` and the commit
   must be an ancestor of `main`.
2. **test** — reuses the normal CI workflow (SQLite suite + Postgres migration
   job).
3. **deploy** — pushes the tag to `git.gigalixir.com` as `main`, then polls
   `https://meerkat.gigalixirapp.com/healthz` for up to 10 minutes.

### GitHub secrets

| Secret | Value |
|---|---|
| `GIGALIXIR_APP_NAME` | `meerkat` |
| `GIGALIXIR_EMAIL` | Your Gigalixir email, **URI-encoded** (`you%40example.com`). |
| `GIGALIXIR_API_KEY` | Key from `gigalixir login` (also in `~/.netrc`). |

The optional `gigalixir` GitHub environment can hold these secrets and add a
manual approval step.

### Deploying by hand

```bash
gigalixir git:remote meerkat   # adds the authenticated remote if missing
git push gigalixir main
gigalixir logs -a meerkat
```

## Verifying a deploy

```bash
curl -fsS https://meerkat.gigalixirapp.com/healthz   # ok
gigalixir ps                                         # 1 replica, healthy
gigalixir logs -a meerkat
```

Then open the secret admin path, create an admin with `ADMIN_ACCESS_CODE`,
create a room, and submit/vote from two browser tabs to confirm LiveView.

After a restart the data must still be there (proving Postgres, not the
ephemeral disk):

```bash
gigalixir ps:restart
```

## Rollback

Instant rollback to the previous Gigalixir release (no rebuild):

```bash
gigalixir releases
gigalixir releases:rollback
```

Or re-run the **Release (Gigalixir)** workflow with a previous
`rel.gigalixir.*` tag. That rebuilds the old source.

Migrations are never reversed by a rollback, so schema changes must remain
backwards compatible with the previous release (expand/contract).

## Known limitations

- **10,000 rows** across the whole database. Expired rooms are deleted (and
  cascade their questions/votes), which keeps normal usage bounded, but a
  single very busy event can still hit the cap.
- **2 database connections**, so the app runs with `POOL_SIZE=1` and serializes
  database access. This is fine for a demo, not for a large live audience.
- **No backups.** Losing the database loses the demo data.
- **No SSH**, so no remote console or observer. Debug with `gigalixir logs`.
- Idle database connections are dropped after 5 minutes; Postgrex reconnects on
  the next checkout, but the first query after a long idle period can fail.
- The free app is scaled to 0 after 30 days without a deploy.

## Custom domain (optional)

```bash
gigalixir domains:add ask.example.com -a meerkat
```

Point a `CNAME` at `meerkat.gigalixirapp.com`, then change `PHX_HOST`:

```bash
gigalixir config:set PHX_HOST=ask.example.com
```

`PHX_HOST` is used for links, LiveView origin checks, and moderator QR codes.
