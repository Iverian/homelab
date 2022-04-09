#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

DUCKDNS_DOMAIN="${DUCKDNS_DOMAIN}"
DUCKDNS_TOKEN="${DUCKDNS_TOKEN}"

DUCKDNS_URL="https://www.duckdns.org/update?verbose&domains=${DUCKDNS_DOMAIN}&token=${DUCKDNS_TOKEN}"

main() {
  curl -fsS "${DUCKDNS_URL}" | return $?
  return 0
}

main || exit $?
