#!/usr/bin/env python3
"""Timestamped serial boot capture for a Nerves device.

Times are host monotonic seconds relative to the first U-Boot banner line
("U-Boot 20xx") seen after the reboot request. Kernel log lines that reach the
console ("[  0.001] ...") are used to estimate the host<->kernel clock offset.
"""
import os, re, socket, subprocess, threading, time
import serial

DEV = os.environ.get("BENCH_TTY", "/dev/cu.wchusbserial1110")
HOST = os.environ.get("BENCH_HOST", "nerves-0123b817bd12a177ee.local")
KEY = os.path.expanduser(os.environ.get("BENCH_KEY", "~/.ssh/id_claude"))
SSH_OPTS = ["-i", KEY, "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
            "-o", "LogLevel=ERROR", "-o", "ConnectTimeout=5"]

UBOOT_RX = re.compile(rb"U-Boot 20\d\d")
IEX_RX = re.compile(rb"iex\([^)]*\)\d*>")
KTS_RX = re.compile(rb"^\[\s*(\d+\.\d+)\]")

def ssh(cmd, host=None, timeout=60):
    r = subprocess.run(["ssh", *SSH_OPTS, f"nerves@{host or HOST}", cmd],
                       capture_output=True, timeout=timeout, text=True)
    return r.stdout

def serial_eval(code, timeout=30, ser=None):
    """Evaluate one line of Elixir at the IEx console and return its output
    (text printed between begin/end markers). The markers are split in the
    sent text so the echoed input never matches."""
    own = ser is None
    ser = ser or serial.Serial(DEV, 115200, timeout=0.1)
    ser.write(b"\r"); time.sleep(0.2); ser.reset_input_buffer()
    line = 'IO.puts("@@B" <> "EGIN@@"); ' + code + '; IO.puts("@@E" <> "ND@@")\r'
    ser.write(line.encode())
    buf, t_end = b"", time.monotonic() + timeout
    while time.monotonic() < t_end and b"@@END@@" not in buf:
        buf += ser.read(4096)
    if own:
        ser.close()
    text = re.sub(rb"\x1b\[[0-9;?]*[A-Za-z]", b"", buf).decode(errors="replace")
    if "@@BEGIN@@" in text and "@@END@@" in text:
        return text.split("@@BEGIN@@", 1)[1].split("@@END@@", 1)[0].strip("\r\n")
    return None

def tcp_probe(ip, port, out, stop):
    """Record the first time a TCP connect to ip:port succeeds."""
    while not stop.is_set():
        try:
            socket.create_connection((ip, port), timeout=0.25).close()
            out["ssh"] = time.monotonic()
            return
        except OSError:
            time.sleep(0.02)

def capture(reboot=True, timeout=120, host=None, after_iex=0.5, probe_ip=None):
    """Reboot (optionally) and capture until the IEx prompt (and the ssh port
    if probe_ip is given). Returns dict."""
    probe, stop, started = {}, threading.Event(), False
    ser = serial.Serial(DEV, 115200, timeout=0.02)
    ser.reset_input_buffer()
    t_req = time.monotonic()
    if reboot:
        # Reboot over the serial console: it works even when the USB network is down.
        ser.write(b"\r"); time.sleep(0.1)
        ser.write(b"Nerves.Runtime.reboot()\r")
    lines, buf, line_t = [], b"", None
    marks = {}
    scanned = 0
    deadline = t_req + timeout
    while time.monotonic() < deadline:
        data = ser.read(4096)
        now = time.monotonic()
        # Stamp the restart message by when its bytes arrive: it's often
        # appended to a console line (e.g. the IEx prompt) that began long ago.
        if data and "restart" not in marks and b"Restarting system" in (buf[-40:] + data):
            marks["restart"] = now
        if not data:
            if "iex" in marks and now - marks["iex"] > after_iex and (not probe_ip or "ssh" in probe or now - marks["iex"] > 30):
                break
            continue
        for b in data:
            if line_t is None:
                line_t = now
            if b == 0x0a:
                lines.append((line_t, buf.rstrip(b"\r")))
                buf, line_t = b"", None
            else:
                buf += bytes([b])
        # Scan each completed line once, plus the partial line (the prompt has no newline)
        def scan(t, l):
            if "uboot" not in marks:
                if UBOOT_RX.search(l):
                    marks["uboot"] = t
                    if probe_ip:
                        threading.Thread(target=tcp_probe, args=(probe_ip, 22, probe, stop), daemon=True).start()
                return
            if "kernel_start" not in marks and b"Starting kernel" in l:
                marks["kernel_start"] = t
            if "iex" not in marks and IEX_RX.search(l):
                marks["iex"] = t
        while scanned < len(lines):
            scan(*lines[scanned])
            scanned += 1
        scan(line_t or now, buf)
    ser.close()
    stop.set()
    if "ssh" in probe:
        marks["ssh"] = probe["ssh"]
    if buf:
        lines.append((line_t or time.monotonic(), buf))
    t0 = marks.get("uboot", t_req)
    # host -> kernel offset: min(host - kt) over kernel lines printed after U-Boot
    offs = []
    for t, l in lines:
        if t < t0:
            continue
        m = KTS_RX.match(l)
        if m:
            offs.append(t - t0 - float(m.group(1)))
    res = {
        "t_req": round(t_req - t0, 3),
        "serial": {k: round(v - t0, 3) for k, v in marks.items()},
        "kernel_offset": round(min(offs), 3) if offs else None,
        "log": [(round(t - t0, 3), l.decode(errors="replace")) for t, l in lines if t >= t0 - 0.001],
    }
    return res

if __name__ == "__main__":
    import json, sys
    r = capture(reboot="--reboot" in sys.argv)
    for t, l in r.pop("log"):
        print(f"{t:9.3f} {l}")
    print(json.dumps(r))
