#!/usr/bin/env bash
# Railway wrapper entrypoint for SonarQube Community.
#
# What upstream's image cannot do on Railway, and is handled here:
#   1. Railway mounts volumes root-owned; the SonarQube image runs as uid 1000 and refuses
#      to run as root, so ownership is taken as root and then dropped with setpriv.
#   2. Railway gives a service one volume. It carries the deployer's installed plugins AND
#      the Elasticsearch index, seeded from the image on first boot only.
#   3. Railway injects $PORT and SonarQube reads sonar.web.port, never $PORT.
#   4. The shipped admin login is a documented default with no forced change.
set -euo pipefail

SQ_HOME=/opt/sonarqube
VOL="$SQ_HOME/extensions"

# Refuse to boot rather than serve a public code-analysis instance whose administrator login
# is still the shipped default. That default is a full takeover: it validates over the API
# with no forced password change, mints admin tokens and creates projects.
if [ -z "${SONAR_ADMIN_PASSWORD:-}" ]; then
  echo "FATAL: SONAR_ADMIN_PASSWORD is not set. Refusing to start SonarQube on a public URL with the default administrator login." >&2
  exit 1
fi

export SONAR_WEB_PORT="${PORT:-9000}"

mkdir -p "$VOL"

# Seed the volume from the image ONCE. Re-copying on every boot would overwrite plugins the
# deployer installed through the Marketplace on each redeploy.
if [ ! -e "$VOL/.railway-seeded" ]; then
  cp -a "$SQ_HOME/extensions-image/." "$VOL/" 2>/dev/null || true
  touch "$VOL/.railway-seeded"
fi

mkdir -p "${SONAR_PATH_DATA:-$VOL/.sq-data}"

chown -R 1000:0 "$VOL"
chmod -R g+rwX "$VOL"

# Seeds the administrator login once the web server answers. Backgrounded so it cannot delay
# or block startup, and idempotent so a container killed mid-boot simply retries next time.
/usr/local/bin/railway-seed-admin &

exec setpriv --reuid=1000 --regid=0 --clear-groups \
  "$SQ_HOME/docker/entrypoint.sh" "$@"
