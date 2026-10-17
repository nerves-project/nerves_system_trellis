#!/bin/sh
# Fetch /tmp/boot.log from a BOOT_DIAG=1 firmware, aligned to uptime. Usage: diaglog.sh OUT
timeout 60 ssh -i ~/.ssh/id_claude -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR nerves@${BENCH_HOST:-$(dscacheutil -q host -a name nerves-0123b817bd12a177ee.local | awk "/ip_address/{print \$2; exit}")} '
off = BootTools.Report.mono_to_uptime_offset()
IO.puts("#{(System.monotonic_time(:microsecond) + off) / 1_000_000} #{System.monotonic_time(:microsecond)}")
IO.puts(File.read!("/tmp/boot.log"))' 2>/dev/null | grep -v '^:ok$' > "$1"
