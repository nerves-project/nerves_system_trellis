#!/usr/bin/env python3
"""Reboot the device N times and record boot timing metrics.

Usage: measure.py LABEL [-n RUNS] [--no-reboot]

Each run appends a record to bench/results/results.jsonl and saves the
serial log and device report under bench/results/runs/.
"""
import argparse, json, os, socket, statistics, subprocess, sys, time
sys.path.insert(0, os.path.dirname(__file__))
import bootcap

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "results")

# Send the module source so the report also works on firmware without it (e.g. nerves_livebook).
REPORT_CMD = open(os.path.join(HERE, "boot_tools/lib/boot_tools/report.ex")).read() + "\nBootTools.Report.json()\n"

def wait_ssh(host, timeout=60):
    t_end = time.monotonic() + timeout
    while time.monotonic() < t_end:
        try:
            socket.create_connection((host, 22), timeout=1).close()
            return True
        except OSError:
            time.sleep(0.2)
    return False

def first(items, pred):
    for i in items:
        if pred(i):
            return i
    return None

def metrics(cap, rep):
    m = {}
    s = cap["serial"]
    off = cap["kernel_offset"]
    m["uboot_s"] = round(s["kernel_start"], 3) if "kernel_start" in s else None
    # Reset -> U-Boot banner: BootROM + SPL (DRAM init) + loading U-Boot proper
    m["pre_uboot_s"] = round(-s["restart"], 3) if "restart" in s else None
    m["kernel_t0"] = off  # U-Boot banner -> kernel clock zero
    m["iex_total"] = s.get("iex")  # U-Boot banner -> prompt on the console
    if off is not None and "iex" in s:
        m["iex_k"] = round(s["iex"] - off, 3)  # kernel uptime at prompt
    if off is not None and "ssh" in s:
        m["ssh_k"] = round(s["ssh"] - off, 3)  # host can open TCP/22 (usb0)
    if rep:
        init = first(rep["dmesg"], lambda d: d["msg"].startswith("Run /sbin/init"))
        m["init_k"] = init["t"] if init else None
        m["beam_k"] = rep.get("beam_proc_start")
        marks = {x["label"]: x["t"] for x in rep["marks"]}
        m["script_start_k"] = marks.get(":trace_start")
        m["script_done_k"] = marks.get(":script_done")
        m["iex_exs_k"] = marks.get(":iex_exs")
        done = [marks.get(":script_done"), marks.get(":deferred_done")]
        done = [d for d in done if d is not None]
        m["apps_k"] = max(done) if done else None
        loads = rep["marks"]
        # Sum primLoad time: each mark's duration is until the next mark
        tot = 0.0
        for a, b in zip(loads, loads[1:]):
            if a["label"].startswith("{:primLoad"):
                tot += b["t"] - a["t"]
        m["primload_s"] = round(tot, 3)
        for v in rep["vintage_net"]:
            # PropertyTable keeps the latest value per property, so this is
            # when the interface last changed connection state (e.g. :internet)
            if v["prop"].endswith(".connection") and v["value"] in (":lan", ":internet"):
                ifn = v["prop"].split(".")[1]
                m.setdefault("net_" + ifn + "_k", v["t"])
                m["net_" + ifn + "_state"] = v["value"]
        nets = [v for k, v in m.items() if k.startswith("net_") and k.endswith("_k")]
        # Priority (Jon): local systems, then console, then network. ready_k is
        # local systems + usb0; WiFi (parked) and ssh_k are informational.
        nets = [m.get("net_usb0_k")] if m.get("net_usb0_k") else []
        parts = [m.get("apps_k")] + nets
        if all(p is not None for p in parts):
            m["ready_k"] = round(max(parts), 3)
        for e in rep.get("net_events", []):
            if e["value"] == ":lan":
                m.setdefault("lan_" + e["ifname"] + "_k", e["t"])
            if e["value"] == ":ipv4":
                m.setdefault("ip_" + e["ifname"] + "_k", e["t"])
            if e["value"] == ":internet":
                m.setdefault("inet_" + e["ifname"] + "_k", e["t"])
        m["modules"] = rep.get("loaded_modules")
        m["apps"] = len(rep.get("started_apps", [])) or rep.get("apps")
        m["ring_logger"] = rep.get("ring_logger")
        m["fw"] = rep.get("fw")
    return m

def run_once(label, reboot=True, host=None):
    host = host or bootcap.HOST
    cap = bootcap.capture(reboot=reboot, host=host, probe_ip=host if os.environ.get("BENCH_SSH_PROBE") == "1" else None)
    rep = None
    # The report waits a little so late network events are recorded.
    time.sleep(float(os.environ.get("REPORT_DELAY", "8")))
    # Reports come over the serial console by default (no network needed, and
    # no ssh session open when the device reboots). BENCH_REPORT=ssh uses ssh,
    # which is needed for firmware without BootTools.Report (e.g. livebook).
    out = None
    if os.environ.get("BENCH_REPORT", "serial") == "ssh" and wait_ssh(host, timeout=20):
        try:
            out = bootcap.ssh(REPORT_CMD, host=host, timeout=30)
        except Exception:
            out = None
    if not out or '{"' not in out:
        out = bootcap.serial_eval("BootTools.Report.json()", timeout=60) or ""
    line = first(out.splitlines()[::-1], lambda l: '{"' in l)
    rep = json.loads(line[line.index('{"'):]) if line else None
    m = metrics(cap, rep)
    ts = time.strftime("%Y%m%d-%H%M%S")
    os.makedirs(os.path.join(RES, "runs"), exist_ok=True)
    base = os.path.join(RES, "runs", f"{ts}-{label}")
    with open(base + ".serial.txt", "w") as f:
        for t, l in cap["log"]:
            f.write(f"{t:9.3f} {l}\n")
    rec = {"ts": ts, "label": label, "metrics": m, "serial": cap["serial"], "kernel_offset": cap["kernel_offset"]}
    if rep:
        with open(base + ".report.json", "w") as f:
            json.dump(rep, f)
        rec["report"] = os.path.relpath(base + ".report.json", HERE)
    with open(os.path.join(RES, "results.jsonl"), "a") as f:
        f.write(json.dumps(rec) + "\n")
    return rec

def summarize(label):
    recs = [json.loads(l) for l in open(os.path.join(RES, "results.jsonl")) if json.loads(l)["label"] == label]
    # Functional check: every run should start the same apps and keep RingLogger
    apps = {r["metrics"].get("apps") for r in recs}
    rl = {r["metrics"].get("ring_logger") for r in recs}
    apps.discard(None); rl.discard(None)
    if len(apps) > 1 or False in rl:
        print(f"  WARNING functional check: apps={sorted(a for a in apps if a)} ring_logger={rl}")
    keys = ["pre_uboot_s", "uboot_s", "kernel_t0", "init_k", "beam_k", "script_start_k", "primload_s", "script_done_k", "apps_k", "iex_exs_k", "iex_k", "iex_total", "ssh_k", "ready_k"]
    keys += sorted({k for r in recs for k in r["metrics"] if (k.startswith("net_") or k.startswith("lan_") or k.startswith("inet_") or k.startswith("ip_")) and k.endswith("_k")})
    print(f"{label}: {len(recs)} runs, apps started {sorted(a for a in apps if a)}, ring_logger {rl}")
    for k in keys:
        vals = [r["metrics"].get(k) for r in recs if r["metrics"].get(k) is not None]
        if vals:
            print(f"  {k:15} median {statistics.median(vals):7.3f}  min {min(vals):7.3f}  max {max(vals):7.3f}")

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("label")
    ap.add_argument("-n", type=int, default=5)
    ap.add_argument("--no-reboot", action="store_true")
    ap.add_argument("--summary", action="store_true")
    a = ap.parse_args()
    if not a.summary:
        for i in range(a.n):
            r = run_once(a.label, reboot=not a.no_reboot)
            print(json.dumps(r["metrics"]), flush=True)
    summarize(a.label)
