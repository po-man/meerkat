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

# App runtime config. These are Gigalixir config vars, not GitHub secrets.
gigalixir config:set \
  POOL_SIZE=2 \
  PHX_HOST=meerkat.gigalixirapp.com \
  ADMIN_ACCESS_CODE=<secret>
```

Notes:

- **`POOL_SIZE=2` is required**, not 1. Ecto's migrator uses one connection for
  the advisory lock and one to run migrations, so a pool of 1 crashes at boot
  with `Migrations failed to run because the connection pool size is less than 2`.
  The free database allows exactly 2 connections.
- Keep **one replica**. A rolling deploy briefly runs two pods, so the 2-connection
  budget is tight; the app's PubSub/Presence/VoteStore are in-process and cannot
  span replicas either.
- `SECRET_KEY_BASE`, `DATABASE_URL`, and `PORT` are injected by Gigalixir.
- `DATABASE_SSL` defaults to `true`; it is only set to `false` for local/CI
  Postgres instances.
- Use a long random `ADMIN_ACCESS_CODE` (`openssl rand -hex 16`) and create the
  first admin at `https://<app>.gigalixirapp.com/login` right away. Until an
  admin exists, that page is the setup form and the code is the only gate.
- These variables live on the **app**, not in GitHub. The deploy workflow can
  sync `ADMIN_ACCESS_CODE` from a GitHub secret and `PHX_HOST` from a repository
  variable (defaulting to `<app>.gigalixirapp.com`). `DATABASE_URL` is not
  synced; it stays on the app, set by `pg:create --free` or the console.
- Free databases are **GCP-only** (`us-central1`/`europe-west1`). If the app was
  created on AWS, it reaches the database cross-cloud: functional, but with more
  latency than a same-region pair.

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
3. **deploy** — syncs the runtime config from GitHub (`ADMIN_ACCESS_CODE` from
   a secret, optional `PHX_HOST` from a variable, `POOL_SIZE=2`), verifies that
   `ADMIN_ACCESS_CODE`, `PHX_HOST`, and `DATABASE_URL` exist and that
   `POOL_SIZE >= 2`, pushes the tag to `git.gigalixir.com` as `main`, scales the
   app to **one replica at size 0.5**, then polls
   `https://meerkat.gigalixirapp.com/healthz` until the body is `ok` (up to
   10 minutes).

### GitHub secrets and variables

| Secret | Value |
|---|---|
| `GIGALIXIR_APP_NAME` | `meerkat` |
| `GIGALIXIR_EMAIL` | Your Gigalixir email. The workflow accepts raw or `%40`-encoded and normalizes it. |
| `GIGALIXIR_API_KEY` | Key from `gigalixir login` (also in `~/.netrc`). |
| `ADMIN_ACCESS_CODE` | Optional. If set, the workflow syncs it to the app on every deploy. |

| Repository variable | Value |
|---|---|
| `PHX_HOST` | Optional. Bare hostname. Defaults to `<app>.gigalixirapp.com` when the app has no value yet. |

`DATABASE_URL` is **not** a GitHub secret: it belongs to the app and is set by
`gigalixir pg:create --free` or the console. If you set `ADMIN_ACCESS_CODE` in
GitHub, treat it as the source of truth — a deploy overwrites the app value.

The optional `gigalixir` GitHub environment can hold these secrets and add a
manual approval step.

### Deploying by hand

```bash
gigalixir git:remote meerkat   # adds the authenticated remote if missing
git push gigalixir main
# ps:scale fails until the first release exists, so run it after the push:
gigalixir ps:scale --replicas=1 --size=0.5 -a meerkat
gigalixir logs -a meerkat
```

## Verifying a deploy

```bash
curl -fsS https://meerkat.gigalixirapp.com/healthz   # must print: ok
gigalixir ps -a meerkat                              # 1 replica, healthy
gigalixir logs -a meerkat
```

An empty `200` from `/healthz` is Gigalixir's default ingress answering while
the app has no running pods — it is **not** the app. The workflow therefore
checks the body (`ok`), not just the status code.

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
- **2 database connections**, which is exactly what `POOL_SIZE=2` uses and what
  Ecto's migrator needs. The app runs with no spare connection, and a rolling
  deploy briefly overlaps two pods, so deploys during heavy traffic can run out
  of connections. This is fine for a demo, not for a large live audience.
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
