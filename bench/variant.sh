#!/bin/bash
# Build boot_bench with the given env settings, flash it, validate it, and
# measure it. Usage: variant.sh LABEL [RUNS] -- [ENV=VALUE ...]
#   e.g. variant.sh exact-paths 5 -- BOOT_EXACT_PATHS=1
set -e
LABEL=$1; RUNS=${2:-5}; shift 2 || shift $#
[ "$1" = "--" ] && shift
HERE=$(cd "$(dirname "$0")" && pwd)
PY=${BENCH_PY:-python3}  # needs pyserial
# Resolve the board over mDNS (WiFi, or usb0 when that's the only link)
HOST=${BENCH_HOST:-$(dscacheutil -q host -a name nerves-0123b817bd12a177ee.local | awk '/ip_address/{print $2; exit}')}
[ -n "$HOST" ] || { echo "can't resolve the board's address"; exit 1; }
SSH="ssh -i ${BENCH_KEY:-$HOME/.ssh/id_claude} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
APP=${BENCH_APP:-boot_bench}
cd "$HERE/$APP"
FW=_build/trellis_prod/nerves/images/$APP.fw
rm -f $FW
# Env-driven settings in mix.exs (deps, release apps) need a full recompile
touch mix.exs
# Deps patched with compile-time env knobs (see patches/) must be rebuilt too
# (inside the Nerves cross-compile environment, or the C helpers get built for the host)
if [ "$APP" = boot_bench ]; then
  env "$@" MIX_TARGET=trellis MIX_ENV=prod mise x -- mix do nerves_bootstrap.init + deps.compile vintage_net vintage_net_wifi nerves_uevent --force > "$HERE/results/depscompile-$LABEL.log" 2>&1 || { echo "deps.compile failed"; exit 1; }
fi
env "$@" MIX_TARGET=trellis MIX_ENV=prod mise x -- mix firmware > "$HERE/results/build-$LABEL.log" 2>&1 || { echo "BUILD FAILED, see results/build-$LABEL.log"; grep -E "\*\* \(" "$HERE/results/build-$LABEL.log"; exit 1; }
grep -E "^\* " "$HERE/results/build-$LABEL.log" | grep -v creating
[ -f $FW ] || { echo "no firmware produced"; exit 1; }
# Sanity check: target C helpers must be ARM binaries
file _build/trellis_prod/lib/vintage_net/priv/if_monitor | grep -q "ARM" || { echo "if_monitor is not an ARM binary; refusing to flash"; exit 1; }
cp $FW "$HERE/results/fw-$LABEL.fw" 2>/dev/null || { mkdir -p "$HERE/results"; cp $FW "$HERE/results/fw-$LABEL.fw"; }
UUID=$(fwup -m -i $FW | sed -n 's/meta-uuid="\(.*\)"/\1/p')
for try in 1 2 3; do
  if cat $FW | $SSH -s nerves@$HOST fwup 2>&1 | tr '\r' '\n' | grep -q "^Success"; then break; fi
  echo "fwup upload failed (try $try)"; sleep 10
done
echo "flashed $LABEL ($UUID); waiting for boot"
# fwup reboots the device; wait for ssh, check the running firmware, then
# validate so later reboots stay on this slot
sleep 15
# Validate and read the running UUID over the serial console (no ssh session
# left open across later reboots).
RUNNING=""
for i in $(seq 1 30); do
  RUNNING=$(cd "$HERE" && $PY -c 'import bootcap; print(bootcap.serial_eval("Nerves.Runtime.validate_firmware(); IO.puts(Nerves.Runtime.KV.get_active(\"nerves_fw_uuid\"))", timeout=10) or "")' 2>/dev/null | grep -oE "[0-9a-f]{8}-[0-9a-f-]{27}" | head -1) && [ -n "$RUNNING" ] && break
  sleep 2
done
if [ "$RUNNING" != "$UUID" ]; then echo "device runs $RUNNING, expected $UUID"; exit 1; fi
cd "$HERE"
BENCH_HOST=$HOST $PY measure.py "$LABEL" -n "$RUNS"
$PY bootchart.py --latest "$LABEL"
