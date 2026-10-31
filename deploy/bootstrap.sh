#!/usr/bin/env bash
#
# One-time (idempotent) host setup for Meerkat.
#
#   sudo bash deploy/bootstrap.sh          # install packages, dirs, env files, timers
#   bash deploy/bootstrap.sh --check       # only run the preflight report (no root needed)
#
# Assumes the repository is already cloned at STACK_DIR (default /srv/meerkat)
# as the deploy user. Safe to re-run at any time.

set -euo pipefail

STACK_DIR="${STACK_DIR:-/srv/meerkat}"
DATA_UID=65534 # `nobody` inside the image; the bind mount must be writable by it
DATA_GID=65534
OWNER="${SUDO_USER:-root}"
CHECK_ONLY=false
[ "${1:-}" = "--check" ] && CHECK_ONLY=true

bold() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '  MISSING  %s\n' "$*"; }
ok() { printf '  ok       %s\n' "$*"; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

# ---------------------------------------------------------------- sanity checks

if [ "$CHECK_ONLY" = false ] && [ "$(id -u)" -ne 0 ]; then
  die "run with sudo (or use --check to only inspect the host)"
fi

[ -d "$STACK_DIR/.git" ] || die "$STACK_DIR is not a git clone; clone the repo there first (see docs/DEPLOY.md)"

bold "Machine"
case "$(uname -m)" in
  aarch64 | arm64) echo "  arm64 — matches the published image" ;;
  x86_64) echo "  x86_64 — the published image is linux/arm64; use an A1 instance or change platforms in .github/workflows" ;;
  *) echo "  unexpected architecture: $(uname -m)" ;;
esac

# ---------------------------------------------------------------- provisioning

if [ "$CHECK_ONLY" = false ]; then
  bold "Ownership of the checkout"
  # The deploy step runs `git checkout --force` as the deploy user, so the
  # checkout must belong to them. Never touch data/ or backups/ here.
  find "$STACK_DIR" -mindepth 1 -maxdepth 1 ! -name data ! -name backups -exec chown -R "$OWNER":"$OWNER" {} +
  echo "  $STACK_DIR -> $OWNER"

  bold "Installing packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq docker.io docker-compose-v2 sqlite3 rclone ca-certificates curl openssl
  echo "  docker, compose v2, sqlite3, rclone"

  bold "Enabling docker"
  systemctl enable --now docker
  usermod -aG docker "$OWNER" || true
  echo "  docker starts at boot; $OWNER added to the docker group"

  bold "Creating directories"
  mkdir -p "$STACK_DIR/data" "$STACK_DIR/backups"
  chown "$DATA_UID":"$DATA_GID" "$STACK_DIR/data"
  chmod 0750 "$STACK_DIR/data"
  chown root:root "$STACK_DIR/backups"
  chmod 0700 "$STACK_DIR/backups"
  echo "  $STACK_DIR/data (uid $DATA_UID), $STACK_DIR/backups"

  bold "Environment files"
  if [ ! -f "$STACK_DIR/deploy/env.prod" ]; then
    install -m 600 -o "$OWNER" -g "$OWNER" "$STACK_DIR/deploy/env.prod.sample" "$STACK_DIR/deploy/env.prod"
    secret="$(openssl rand -base64 48)"
    sed -i "s|^SECRET_KEY_BASE=\$|SECRET_KEY_BASE=${secret}|" "$STACK_DIR/deploy/env.prod"
    echo "  created deploy/env.prod with a generated SECRET_KEY_BASE"
  else
    echo "  deploy/env.prod already exists, left untouched"
  fi

  if [ ! -f "$STACK_DIR/deploy/tunnel.env" ]; then
    install -m 600 -o "$OWNER" -g "$OWNER" "$STACK_DIR/deploy/tunnel.env.sample" "$STACK_DIR/deploy/tunnel.env"
    echo "  created deploy/tunnel.env (needs the tunnel token)"
  else
    echo "  deploy/tunnel.env already exists, left untouched"
  fi

  # The deploy user runs `docker compose`, which reads these files.
  chown "$OWNER":"$OWNER" "$STACK_DIR/deploy/env.prod" "$STACK_DIR/deploy/tunnel.env"
  chmod 600 "$STACK_DIR/deploy/env.prod" "$STACK_DIR/deploy/tunnel.env"

  bold "Installing the backup timer"
  ln -sfn "$STACK_DIR/deploy/meerkat-backup.service" /etc/systemd/system/meerkat-backup.service
  ln -sfn "$STACK_DIR/deploy/meerkat-backup.timer" /etc/systemd/system/meerkat-backup.timer
  systemctl daemon-reload
  systemctl enable --now meerkat-backup.timer
  echo "  meerkat-backup.timer enabled (daily 03:00 UTC)"
fi

# ------------------------------------------------------------------ preflight

bold "Preflight"
missing=0

check() { # check <description> <command...>
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    ok "$description"
  else
    fail "$description"
    missing=$((missing + 1))
  fi
}

env_set() { # env_set <file> <KEY>
  [ -f "$1" ] && grep -Eq "^$2=.+" "$1"
}

check "docker installed" command -v docker
check "compose v2 available" docker compose version
check "sqlite3 installed" command -v sqlite3
check "rclone installed" command -v rclone
check "data dir owned by uid $DATA_UID" test "$(stat -c %u "$STACK_DIR/data")" = "$DATA_UID"
check "PHX_HOST set" env_set "$STACK_DIR/deploy/env.prod" PHX_HOST
check "SECRET_KEY_BASE set" env_set "$STACK_DIR/deploy/env.prod" SECRET_KEY_BASE
check "ADMIN_ACCESS_CODE set" env_set "$STACK_DIR/deploy/env.prod" ADMIN_ACCESS_CODE
check "tunnel token set" env_set "$STACK_DIR/deploy/tunnel.env" CLOUDFLARE_TUNNEL_TOKEN
check "backup timer enabled" systemctl is-enabled meerkat-backup.timer

if [ -f "$STACK_DIR/deploy/env.prod" ] &&
  grep -Eq '^PHX_HOST=ask\.example\.com$' "$STACK_DIR/deploy/env.prod"; then
  printf '  WARNING  PHX_HOST is still the sample value\n'
fi

if [ "$missing" -eq 0 ]; then
  printf '\nAll required settings are present. Start the stack with:\n\n'
  printf '  cd %s\n' "$STACK_DIR"
  printf '  IMAGE_TAG=latest docker compose -f compose.prod.yml up -d\n\n'
else
  printf '\n%d item(s) still to do — see docs/DEPLOY.md.\n' "$missing"
fi

cat <<'NEXT'

Next steps (once, in this order):
  1. fill ADMIN_ACCESS_CODE and PHX_HOST in deploy/env.prod
  2. paste the tunnel token into deploy/tunnel.env
  3. give the host read access to GHCR:
       docker login ghcr.io -u <github-user> --password-stdin   # token with read:packages
     ...or make the ghcr.io/po-man/meerkat package public
  4. make sure this clone can `git fetch` (read-only deploy key)
  5. deploy a release tag, or for the very first start:
       IMAGE_TAG=latest docker compose -f compose.prod.yml up -d
NEXT
