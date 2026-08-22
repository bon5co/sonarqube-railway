#!/usr/bin/env bash
# Replace SonarQube's default admin login with the deployer's SONAR_ADMIN_PASSWORD.
#
# SonarQube ships a fixed default administrator login and does NOT force a change on
# first use: it validates over the API, mints admin tokens and creates projects. On a
# public Railway URL that hands the first stranger the deployer's code-analysis instance.
# There is no environment variable upstream for seeding it, so it is done over the API
# as soon as the web server answers.
#
# Idempotent by design, because the container can be killed at any point during a long
# first boot: if the seeded value already works there is nothing to do, and if neither
# the default nor the seeded value works the operator changed it themselves and this
# script must leave it alone.
set -uo pipefail

API="http://127.0.0.1:${SONAR_WEB_PORT:-9000}"
LOGIN=admin
DEFAULT=admin
TARGET="${SONAR_ADMIN_PASSWORD:-}"

[ -n "$TARGET" ] || exit 0

for _ in $(seq 1 240); do
  status=$(curl -fsS --max-time 5 "$API/api/system/status" 2>/dev/null || true)
  case "$status" in *'"UP"'*) break ;; esac
  sleep 5
done

if curl -fsS --max-time 10 -u "$LOGIN:$TARGET" "$API/api/authentication/validate" 2>/dev/null \
    | grep -q '"valid":true'; then
  echo "[railway] admin login already matches SONAR_ADMIN_PASSWORD; nothing to do."
  exit 0
fi

if curl -fsS --max-time 15 -o /dev/null -X POST -u "$LOGIN:$DEFAULT" \
     "$API/api/users/change_password" \
     --data-urlencode "login=$LOGIN" \
     --data-urlencode "previousPassword=$DEFAULT" \
     --data-urlencode "password=$TARGET" 2>/dev/null; then
  echo "[railway] admin login seeded from SONAR_ADMIN_PASSWORD; the default login is now rejected."
else
  echo "[railway] WARNING: admin login is neither the shipped default nor SONAR_ADMIN_PASSWORD." >&2
  echo "[railway] It was most likely changed by hand. Leaving it untouched." >&2
fi
