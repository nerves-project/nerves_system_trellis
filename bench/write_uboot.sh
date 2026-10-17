#!/bin/sh
# Write a u-boot-sunxi-with-spl.bin to the board's MMC at 8 KiB (where fwup's
# complete task puts it) and verify the read-back. The original is backed up
# once to /root/uboot-backup-orig.bin on the board.
# Usage: write_uboot.sh path/to/u-boot-sunxi-with-spl.bin
set -e
HOST=${BENCH_HOST:-$(dscacheutil -q host -a name nerves-0123b817bd12a177ee.local | awk '/ip_address/{print $2; exit}')}
OPTS="-i ${BENCH_KEY:-$HOME/.ssh/id_claude} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
SIZE=$(stat -f %z "$1")
# scp (SFTP mode) exits non-zero against nerves_ssh even when the copy works;
# the size check below is what matters.
scp -q $OPTS "$1" nerves@$HOST:/tmp/uboot.bin || true
ssh $OPTS nerves@$HOST '
new = File.read!("/tmp/uboot.bin")
if byte_size(new) != '$SIZE', do: raise "upload size mismatch: #{byte_size(new)}"
{:ok, dev} = :file.open(~c"/dev/mmcblk0", [:read, :write, :raw, :binary])
{:ok, old} = :file.pread(dev, 8192, 8176 * 512)
unless File.exists?("/root/uboot-backup-orig.bin"), do: File.write!("/root/uboot-backup-orig.bin", old)
:ok = :file.pwrite(dev, 8192, new)
:ok = :file.sync(dev)
{:ok, check} = :file.pread(dev, 8192, byte_size(new))
:file.close(dev)
IO.puts(if check == new, do: "uboot written OK (#{byte_size(new)} bytes)", else: "VERIFY FAILED")' 2>&1 | grep -E "uboot written|VERIFY"
