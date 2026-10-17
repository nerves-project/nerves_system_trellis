#!/bin/sh
# Apply the WiFi experiment patches to boot_bench's deps (run after
# `mix deps.get`). They only add compile-time knobs (BOOT_UDHCPC_T,
# BOOT_SCAN_FREQ); without those env vars the deps behave as upstream.
set -e
cd "$(dirname "$0")"
for pkg in vintage_net vintage_net_wifi nerves_uevent; do
  for p in patches/$pkg-*.patch; do
    if patch -p1 -N --dry-run -s -d boot_bench/deps/$pkg < "$p" >/dev/null 2>&1; then
      patch -p1 -N -s -d boot_bench/deps/$pkg < "$p" && echo "applied $p"
    else
      echo "skipped $p (already applied?)"
    fi
  done
done
