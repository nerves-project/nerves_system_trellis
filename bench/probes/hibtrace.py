#!/usr/bin/env python3
"""One hibernate+resume cycle with kernel PM debug output, timestamped by
the host from the moment the save is triggered. Arms via the serial console
(probes/hib_arm.exs) with HIB_IMAGE_SIZE / HIB_EXTRA_ARGS from the env."""
import os, sys, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import serial, bootcap
here = os.path.dirname(os.path.abspath(__file__))
code = "; ".join(l.strip() for l in open(os.path.join(here, os.environ.get("HIB_ARM", "hib_arm.exs"))) if l.strip() and not l.strip().startswith("#"))
pre = "".join(f'System.put_env("{k}", "{os.environ[k]}"); ' for k in ("HIB_IMAGE_SIZE", "HIB_EXTRA_ARGS") if k in os.environ)
out = bootcap.serial_eval(pre + code + '; File.write!("/proc/sys/kernel/printk", "7")', timeout=60) or ""
if "armed" not in out: sys.exit("arm failed")
s = serial.Serial(bootcap.DEV, 115200, timeout=0.02)
s.write(b"\r"); time.sleep(0.3); s.reset_input_buffer()
s.write(b'File.write!("/sys/power/disk", "reboot"); File.write("/sys/power/state", "disk")\r')
t0 = time.monotonic(); cur = b""; lines = []; probe = 0; ub = None
while time.monotonic() - t0 < 75:
    c = s.read(4096); now = time.monotonic() - t0
    if c:
        cur += c
        while b"\n" in cur:
            l, cur = cur.split(b"\n", 1); l = l.decode(errors="replace").strip()
            lines.append((now, l))
            if ub is None and "U-Boot 20" in l: ub = now
            if "RDYUP" in l and "IO.puts" not in l: lines.append((now, "== READY")); break
        else:
            pass
    if any(l == "== READY" for _, l in lines): break
    if any("Starting kernel" in l for _, l in lines) and now - probe > 0.3:
        s.write(b'#iex:break\rIO.puts("RDY" <> "UP" <> File.read!("/proc/uptime"))\r'); probe = now
for t, l in lines:
    print(f"{t - (ub or 0):7.3f} {l}")
