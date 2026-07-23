#!/bin/sh
set -eu

: "${DATABASE_URL:?DATABASE_URL is required}"
: "${BACKUP_FILE:?BACKUP_FILE is required}"
: "${CONFIRM_RESTORE:?Set CONFIRM_RESTORE=restore-zoid99 to continue}"

if [ "$CONFIRM_RESTORE" != "restore-zoid99" ]; then
  echo "Restore confirmation did not match." >&2
  exit 2
fi

test -f "$BACKUP_FILE"
test -f "${BACKUP_FILE}.sha256"
sha256sum --check "${BACKUP_FILE}.sha256"
pg_restore --list "$BACKUP_FILE" >/dev/null
pg_restore \
  --dbname="$DATABASE_URL" \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges \
  --exit-on-error \
  "$BACKUP_FILE"
