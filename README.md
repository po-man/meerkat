# Meerkat

Meerkat is **a real-time, anonymous Q&A app for live events** like conferences, meetups, town halls.

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
