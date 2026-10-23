# Multi-stage Dockerfile for Elixir Release

# --- Stage 1: Build Image ---
FROM elixir:1.16-alpine AS builder

# Install build dependencies
RUN apk add --no-ca-cache build-base git nodejs npm

WORKDIR /app

# Install Hex and Rebar
RUN mix local.hex --force && mix local.rebar --force

# Set build environment
ENV MIX_ENV=prod

# Copy mix files and fetch dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy assets and build assets
COPY assets assets
COPY priv priv
COPY lib lib
RUN mix assets.deploy

# Compile release
RUN mix compile
RUN mix release

# --- Stage 2: Runtime Image ---
FROM alpine:3.19 AS runner

RUN apk add --no-ca-cache libstdc++ ncurses-libs sqlite-dev tzdata

WORKDIR /app

# Copy release from builder
COPY --from=builder /app/_build/prod/rel/qa_app ./

# Create data directory for persistent SQLite database
RUN mkdir -p /app/data && chown -R nobody:nobody /app

USER nobody

ENV PORT=4000
ENV PHX_SERVER=true
ENV DATABASE_PATH=/app/data/prod.sqlite3

EXPOSE 4000

CMD ["bin/qa_app", "start"]
