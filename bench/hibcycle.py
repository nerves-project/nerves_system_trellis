#!/usr/bin/env python3
"""Resume-boot timing: N cycles of arm (probes/hib_arm.exs over ssh),
hibernate with reboot, then time the resume on the serial console.

Times are seconds from the U-Boot banner (as iex_total in measure.py):
kernel = "Starting kernel", exit = restored kernel's "hibernation exit",
ready = IEx answers a probe typed after the kernel starts, ping = first
ICMP reply. Usage: hibcycle.py LABEL -n N
"""
import argparse, json, os, subprocess, threading, time
import serial

DEV = os.environ.get("BENCH_TTY", "/dev/cu.wchusbserial1110")
HOST = os.environ.get("BENCH_HOST", "nerves-0123b817bd12a177ee.local")
KEY = os.path.expanduser(os.environ.get("BENCH_KEY", "~/.ssh/id_claude"))
HERE = os.path.dirname(os.path.abspath(__file__))
SSH = ["ssh", "-i", KEY, "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-o", "LogLevel=ERROR"]

def resolve(host):
    out = subprocess.run(["dscacheutil", "-q", "host", "-a", "name", host], capture_output=True, text=True).stdout
    for l in out.splitlines():
        if l.startswith("ip_address"): return l.split()[1]
    return host

def arm(ip):
    # Over the serial console: networking doesn't reliably survive a resume.
    import bootcap
    code = "; ".join(l.strip() for l in open(os.path.join(HERE, "probes", os.environ.get("HIB_ARM", "hib_arm.exs")))
                     if l.strip() and not l.strip().startswith("#"))
    if os.environ.get("HIB_IMAGE_SIZE"):
        code = f'System.put_env("HIB_IMAGE_SIZE", "{os.environ["HIB_IMAGE_SIZE"]}"); ' + code
    out = bootcap.serial_eval(code, timeout=60) or ""
    if "armed: /" not in out: raise SystemExit("arm failed:\n" + out[-2000:])

def cycle(ip, n):
    ser = serial.Serial(DEV, 115200, timeout=0.02)
    ser.write(b"\r"); time.sleep(0.3); ser.reset_input_buffer()
    ser.write(b'File.write!("/sys/power/disk", "reboot"); File.write("/sys/power/state", "disk")\r')
    t0 = time.monotonic(); buf = b""; ev = {}
    ping = {}
    def pinger():
        while "ping" not in ping and time.monotonic() - t0 < 90:
            if "kernel" in ev and subprocess.run(["ping", "-c", "1", "-t", "1", ip], capture_output=True).returncode == 0:
                ping["ping"] = time.monotonic()
            time.sleep(0.05)
    threading.Thread(target=pinger, daemon=True).start()
    probe_sent = 0
    token = f"RDY{n}X"
    while time.monotonic() - t0 < 90:
        c = ser.read(4096); now = time.monotonic()
        if c:
            buf += c
            for key, pat in (("saved", b"Image saving done"), ("restart", b"reboot: Restarting"), ("uboot", b"U-Boot 20"),
                             ("kernel", b"Starting kernel"), ("exit", b"hibernation: hibernation exit"), ("ready", token.encode() + b"UP")):
                if key not in ev and pat in buf: ev[key] = now
        if "kernel" in ev and "ready" not in ev and now - probe_sent > 0.25:
            ser.write(b"#iex:break\r")
            sigdev = os.environ.get("HIB_SIGDEV", "/dev/mmcblk0p4")
            sigoff = int(os.environ.get("HIB_SIGOFF", str(9729 * 4096 + 4086)))
            ser.write(f'IO.puts("{token}" <> "UP" <> File.read!("/proc/uptime") <> "SIG" <> inspect(elem(:file.pread(elem(:file.open("{sigdev}", [:read, :raw, :binary]), 1), {sigoff}, 10), 1)))\r'.encode()); probe_sent = now
        if "ready" in ev and ("ping" in ping or now - ev["ready"] > 10): break
    if "ping" in ping: ev["ping"] = ping["ping"]
    ser.close()
    if "uboot" not in ev: return {"error": "no U-Boot banner", "log": buf.decode(errors="replace")[-1500:]}
    u = ev["uboot"]
    # A resumed kernel's uptime continues from before the save.
    import re
    m = re.search(token.encode() + rb"UP([0-9.]+)", buf)
    uptime = float(m.group(1)) if m else None
    pm = [l.strip()[-40:] for l in buf.decode(errors="replace").splitlines() if l.startswith("SIG") or "PM: Image size" in l or "Wrote" in l][-3:]
    return {k: round(v - u, 3) for k, v in ev.items()} | {"resumed": bool(uptime and uptime > 15), "uptime": uptime, "pm": pm}

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("label"); ap.add_argument("-n", type=int, default=3)
    a = ap.parse_args(); ip = resolve(HOST)
    res = []
    for i in range(a.n):
        arm(ip)
        r = cycle(ip, i); r["label"] = a.label; r["ts"] = time.strftime("%Y%m%d-%H%M%S")
        print(json.dumps({k: v for k, v in r.items() if k != "pm"})); res.append(r)
        if not r.get("resumed"): print("   PM log:", " | ".join(r.get("pm", [])))
        with open(os.path.join(HERE, "results/hibernate.jsonl"), "a") as f: f.write(json.dumps(r) + "\n")
        time.sleep(8)
    ok = [r for r in res if "ready" in r and r.get("resumed")]
    for k in ("kernel", "exit", "ready", "ping"):
        v = sorted(r[k] for r in ok if k in r)
        if v: print(f"  {k:8} median {v[len(v)//2]:6.3f}  min {v[0]:6.3f}  max {v[-1]:6.3f}  (n={len(v)})")

if __name__ == "__main__":
    main()
