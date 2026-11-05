# Meerkat

[![CI](https://github.com/po-man/meerkat/actions/workflows/ci.yml/badge.svg)](https://github.com/po-man/meerkat/actions/workflows/ci.yml)

Meerkat is **a real-time, anonymous Q&A app for live events** like conferences, meetups, town halls.

https://github.com/user-attachments/assets/f109cf0a-ebf4-4c55-a744-b4c54ba547d7

_A quick tour — the audience joins by QR, the room fills up live, and questions and upvotes land on the moderator's dashboard in real time._

Audience members:
- join a room with a short link,
- submit questions without signing up, and
- upvote the questions they want answered.

Moderators:
- watch the feed on a live dashboard, and
- manage the questions raised.

## Why "Meerkat"

Meerkats stand up, scan the horizon, and signal what deserves the group's attention:
- an audience member popping up with a question,
- moderators spotting what matters.

## Why Elixir

- **LiveView** keeps a persistent connection per visitor and sends only what changed, so new questions and votes reach everyone without page reloads or polling.
- **Phoenix PubSub** broadcasts updates to every connected client in-process — no external broker to install or run.
- **The Erlang VM (BEAM)** runs each connection on lightweight processes, a natural fit for a large audience on one server.

## Requirements

- Elixir 1.17+

## Run locally

```bash
git clone git@github.com:po-man/meerkat.git
cd meerkat

# Create the env file and set a value for ADMIN_ACCESS_CODE
cp .env.sample .env

# Install dependencies and set up the database
mix setup

# Start the server (or: iex -S mix phx.server)
mix phx.server
```

Open [`localhost:4000`](http://localhost:4000). On first run, go to [`/login`](http://localhost:4000/login) to create the admin account using the access code from your `.env`, then create moderators and rooms from the admin dashboard.

## Deploy

Deployment is tag driven and runs on Gigalixir's free tier with Postgres; see
[`docs/GIGALIXIR.md`](docs/GIGALIXIR.md) for the app setup, release process,
verification and rollback.

A production `Dockerfile` is included for self-hosting. It builds the SQLite
variant (`QA_ECTO_ADAPTER=sqlite`) and expects `PHX_HOST`, `SECRET_KEY_BASE`,
`ADMIN_ACCESS_CODE` and a volume mounted at `/data`.
