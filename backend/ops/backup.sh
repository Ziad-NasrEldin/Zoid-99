#!/bin/sh
set -eu

: "${DATABASE_URL:?DATABASE_URL is required}"
: "${BACKUP_DIRECTORY:?BACKUP_DIRECTORY is required}"

umask 077
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
destination="${BACKUP_DIRECTORY%/}/zoid99-${timestamp}.dump"
temporary="${destination}.partial"

mkdir -p "$BACKUP_DIRECTORY"
pg_dump --dbname="$DATABASE_URL" --format=custom --compress=9 --no-owner --no-privileges --file="$temporary"
pg_restore --list "$temporary" >/dev/null
mv "$temporary" "$destination"
sha256sum "$destination" >"${destination}.sha256"
printf '%s\n' "$destination"
