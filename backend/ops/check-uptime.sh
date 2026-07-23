#!/bin/sh
set -eu

: "${PUBLIC_BASE_URL:?PUBLIC_BASE_URL is required}"

base="${PUBLIC_BASE_URL%/}"
wget -q -O /dev/null "${base}/health"
wget -q -O /dev/null "${base}/ready"
