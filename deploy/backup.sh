#!/usr/bin/env bash
#
# Nightly, consistent SQLite snapshot + upload to Cloudflare R2.
#
# `VACUUM INTO` is safe to run against a live WAL database: it takes a read
# snapshot, so the app keeps serving and the copy is transactionally consistent
# (no need to stop the container or copy -wal/-shm by hand).
#
# Requires on the host: sqlite3 (>= 3.27) and rclone.
#   apt-get install -y sqlite3 rclone
#   rclone config        # create an "r2" remote (S3-compatible, endpoint from
#                        # the Cloudflare dashboard) and a bucket, e.g. meerkat-backups
#
# Environment overrides:
#   STACK_DIR  (default /srv/meerkat)
#   R2_REMOTE  (default r2:meerkat-backups)
#   KEEP_DAYS  (default 7 local copies; R2 keeps what you copy there)

set -euo pipefail

STACK_DIR="${STACK_DIR:-/srv/meerkat}"
R2_REMOTE="${R2_REMOTE:-r2:meerkat-backups}"
KEEP_DAYS="${KEEP_DAYS:-7}"

DB_PATH="$STACK_DIR/data/prod.sqlite3"
BACKUP_DIR="$STACK_DIR/backups"
STAMP="$(date -u +%Y-%m-%d)"
TARGET="$BACKUP_DIR/prod-$STAMP.sqlite3"
PARTIAL="$TARGET.partial"

if [ ! -f "$DB_PATH" ]; then
  echo "backup: no database at $DB_PATH" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"
rm -f "$PARTIAL"

# Write to a .partial name first so a crashed run can never be mistaken for a
# valid backup.
sqlite3 "$DB_PATH" "VACUUM INTO '$PARTIAL'"
mv "$PARTIAL" "$TARGET"

echo "backup: wrote $TARGET ($(du -h "$TARGET" | cut -f1))"

rclone copy --no-traverse "$TARGET" "$R2_REMOTE/"
echo "backup: uploaded $TARGET to $R2_REMOTE"

# Prune local copies only after a successful upload.
find "$BACKUP_DIR" -maxdepth 1 -name 'prod-*.sqlite3' -type f -mtime "+$KEEP_DAYS" -print -delete

echo "backup: done"
