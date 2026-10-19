#!/usr/bin/env python3
"""Suspend-to-idle cycles on the serial console: suspend, sleep SLEEP s,
wake by sending a byte (ttyS4 is made a wakeup source), and time it.

Host clock is aligned to the kernel's printk clock with the "PM: suspend
entry" line (console printing stays on: console_suspend=N, printk 7).
Reports per cycle: suspend entry -> tasks frozen (kernel), wake byte ->
"Restarting tasks" / "PM: suspend exit" (kernel, host-aligned), wake byte ->
IEx prints its result. Usage: suspendcycle.py LABEL -n N [--sleep S]"""
import argparse, json, os, re, subprocess, threading, time
import serial, bootcap

def cycle(sleep_s):
    bootcap.serial_eval('File.write!("/sys/class/tty/ttyS4/power/wakeup", "enabled"); '
                        'File.write!("/sys/module/printk/parameters/console_suspend", "N"); '
                        'File.write!("/proc/sys/kernel/printk", "7")', timeout=15)
    s = serial.Serial(bootcap.DEV, 115200, timeout=0.01)
    s.write(b"\r"); time.sleep(0.3); s.reset_input_buffer()
    pre = os.environ.get("PRE_EXPR", ":ok"); post = os.environ.get("RESUME_EXPR", ":ok")
    s.write(f'{pre}; r = File.write("/sys/power/state", "mem"); post = ({post}); IO.puts("WOKE" <> "UP #{{inspect(r)}}")\r'.encode())
    t0 = time.monotonic(); lines = []; cur = b""; woke = None; done = None
    def pump():
        nonlocal cur
        c = s.read(4096); now = time.monotonic()
        if c:
            cur += c
            while b"\n" in cur:
                l, cur = cur.split(b"\n", 1); lines.append((now, l.decode(errors="replace").strip()))
    while time.monotonic() - t0 < sleep_s: pump()
    woke = time.monotonic(); s.write(b"\r")
    pings = {}
    def pinger(name, ip):
        while time.monotonic() - woke < 30:
            if subprocess.run(["ping", "-c", "1", "-W", "150", ip], capture_output=True).returncode == 0:
                pings[name] = time.monotonic(); return
    for name, ip in (("wlan0", os.environ.get("WLAN_IP", "10.1.1.52")), ("usb0", "172.31.3.157")):
        threading.Thread(target=pinger, args=(name, ip), daemon=True).start()
    while time.monotonic() - woke < 15:
        pump()
        if done is None and any("WOKEUP" in l and "IO.puts" not in l for _, l in lines): done = lines[-1][0]
        if done and len(pings) == 2: break
    s.close()
    def kts(pat):
        for h, l in lines:
            m = re.search(r"\[\s*([0-9.]+)\]\s*" + pat, l)
            if m: return h, float(m.group(1))
        return None, None
    h_entry, k_entry = kts(r"PM: suspend entry")
    _, k_frozen = kts(r"Freezing remaining freezable tasks completed")
    before = [float(m.group(1)) for h, l in lines if h < woke for m in [re.search(r"\[\s*([0-9.]+)\]", l)] if m]
    k_last = max(before) if before else None
    _, k_restart = kts(r"Restarting tasks: Starting")
    _, k_exit = kts(r"PM: suspend exit")
    if k_entry is None or k_exit is None: return {"error": "no PM lines", "tail": [l for _, l in lines][-8:]}
    off = h_entry - k_entry  # host time = kernel ts + off (upper bound: console line latency)
    r = {"freeze_ms": round((k_frozen - k_entry) * 1000, 1) if k_frozen and k_frozen > k_entry else None,
         "suspend_ms": round((k_last - k_entry) * 1000) if k_last else None,
         "wake_to_restart_ms": round((k_restart + off - woke) * 1000) if k_restart else None,
         "wake_to_exit_ms": round((k_exit + off - woke) * 1000),
         "wake_to_iex_ms": round((done - woke) * 1000) if done else None,
         "asleep_s": round(k_exit - k_entry, 2)} | {f"wake_to_ping_{k}_ms": round((v - woke) * 1000) for k, v in pings.items()}
    return r

if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("label"); ap.add_argument("-n", type=int, default=5); ap.add_argument("--sleep", type=float, default=3)
    a = ap.parse_args(); rs = []
    for i in range(a.n):
        r = cycle(a.sleep) | {"label": a.label, "ts": time.strftime("%Y%m%d-%H%M%S")}
        print(json.dumps(r)); rs.append(r)
        with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "results/suspend.jsonl"), "a") as f: f.write(json.dumps(r) + "\n")
        time.sleep(2)
    for k in ("freeze_ms", "suspend_ms", "wake_to_restart_ms", "wake_to_exit_ms", "wake_to_iex_ms", "wake_to_ping_wlan0_ms", "wake_to_ping_usb0_ms"):
        v = sorted(r[k] for r in rs if r.get(k) is not None)
        if v: print(f"  {k:20} median {v[len(v)//2]:7}  min {v[0]:7}  max {v[-1]:7}")
