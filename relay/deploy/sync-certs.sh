#!/bin/sh
# Copies relay.zigdash.app's certificate from the host Caddy's data volume to
# ./certs, readable by Mosquitto (uid 1883), and asks Mosquitto to reload it
# when it changed. Run daily (zigdash-relay-certs.timer) and once after the
# first certificate is issued.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
src="${CADDY_CERT_DIR:?folder holding relay.zigdash.app.crt and .key}"
mkdir -p "$here/certs"
changed=0
for f in relay.zigdash.app.crt relay.zigdash.app.key; do
  [ -f "$src/$f" ] || { echo "no $src/$f yet"; exit 1; }
  if ! cmp -s "$src/$f" "$here/certs/$f" 2>/dev/null; then
    install -m 0640 -o 1883 -g 1883 "$src/$f" "$here/certs/$f"
    changed=1
  fi
done
if [ "$changed" = 1 ] && docker ps --format '{{.Names}}' | grep -qx zigdash-relay-mosquitto-1; then
  docker kill -s HUP zigdash-relay-mosquitto-1 >/dev/null
  echo "certificate updated, mosquitto reloaded"
fi
