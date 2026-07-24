#!/bin/sh
set -eu

: "${PUBLIC_BASE_URL:?PUBLIC_BASE_URL is required}"

base="${PUBLIC_BASE_URL%/}"

check_endpoint() {
  if command -v curl >/dev/null 2>&1; then
    curl --fail --silent --show-error --output /dev/null "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O /dev/null "$1"
  else
    echo "curl or wget is required for uptime checks." >&2
    exit 127
  fi
}

check_endpoint "${base}/health"
check_endpoint "${base}/ready"
