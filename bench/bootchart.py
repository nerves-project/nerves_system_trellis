#!/usr/bin/env python3
"""Render a bootchart (self-contained HTML/SVG) for one measured boot.

Usage: bootchart.py [RUN_PREFIX | --latest LABEL] [-o out.html]

Everything is placed on the kernel uptime clock (t=0 is the kernel's first
timestamp). U-Boot and kernel handoff appear at negative times.
"""
import argparse, glob, html, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "results")

def load(label=None, prefix=None):
    recs = [json.loads(l) for l in open(os.path.join(RES, "results.jsonl"))]
    if prefix:
        recs = [r for r in recs if r["ts"].startswith(prefix) or (r["ts"] + "-" + r["label"]).startswith(prefix)]
    if label:
        recs = [r for r in recs if r["label"] == label]
    rec = recs[-1]
    rep = json.load(open(os.path.join(HERE, rec["report"]))) if rec.get("report") else {}
    return rec, rep

def short(label):
    label = label.replace("Elixir.", "")
    m = re.match(r"\{:primLoad, :?([\w.]+), (\d+)\}", label)
    if m: return f"load {m.group(1)} ({m.group(2)} mods)", "load"
    m = re.match(r"\{:(start_boot|load), :?([\w.]+)\}", label)
    if m: return (f"start {m.group(2)}", "start") if m.group(1) == "start_boot" else (f"app load {m.group(2)}", "misc")
    m = re.match(r"\{:kernelProcess, :?(\w+)\}", label)
    if m: return f"kernel proc {m.group(1)}", "misc"
    return label, "misc"

def build_segments(rec, rep):
    segs = []  # (row_label, start, end, kind)
    off = rec.get("kernel_offset")
    s = rec["serial"]
    if off is not None and "kernel_start" in s:
        segs.append(("U-Boot", -off, s["kernel_start"] - off, "boot"))
        segs.append(("kernel handoff/decompress", s["kernel_start"] - off, 0.0, "boot"))
    m = rec["metrics"]
    if m.get("init_k"):
        segs.append(("Linux kernel", 0.0, m["init_k"], "kernel"))
        if m.get("beam_k"):
            segs.append(("erlinit", m["init_k"], m["beam_k"], "kernel"))
    marks = rep.get("marks", [])
    if marks and m.get("beam_k"):
        segs.append(("BEAM start → boot script", m["beam_k"], marks[0]["t"], "misc"))
    agg = {}
    for a, b in zip(marks, marks[1:]):
        name, kind = short(a["label"])
        if a["label"] == ":script_done":
            continue
        dur = b["t"] - a["t"]
        if dur < 0.004 and kind == "misc":
            continue
        segs.append((name, a["t"], b["t"], kind))
    done = next((x["t"] for x in marks if x["label"] == ":script_done"), None)
    iex_k = m.get("iex_k")
    if done and iex_k:
        segs.append(("script done → IEx prompt", done, iex_k, "misc"))
    return segs

COLORS = {"boot": "#8a8f98", "kernel": "#5b8def", "load": "#e8a33d", "start": "#3dae7a", "misc": "#a07be0"}

def render(rec, rep, out):
    segs = build_segments(rec, rep)
    m = rec["metrics"]
    events = []
    for v in rep.get("vintage_net", []):
        if v["prop"].endswith(".connection"):
            events.append((v["t"], f'{v["prop"].split(".")[1]} {v["value"]}'))
    if m.get("iex_k"):
        events.append((m["iex_k"], "IEx prompt"))
    for p in rep.get("procs", []):
        if p["t"] > 0.5 and not p["cmd"].startswith("/srv/erlang/erts"):
            events.append((p["t"], "proc " + os.path.basename(p["cmd"].split()[0])))
    for d in rep.get("dmesg", []):
        if re.search(r"Firmware version|wlan0|link becomes ready|nerves_heart: kernel", d["msg"]):
            events.append((d["t"], "k: " + d["msg"][:60]))
    events.sort()
    tmin = min([sg[1] for sg in segs] + [0])
    tmax = max([sg[2] for sg in segs] + [e[0] for e in events] + [1])
    W, LW, RH = 1100, 270, 16
    scale = (W - LW - 20) / (tmax - tmin)
    X = lambda t: LW + (t - tmin) * scale
    rows = len(segs) + len(events) + 3
    H = rows * RH + 60
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" font-family="ui-monospace,Menlo,monospace" font-size="11">']
    # grid
    t = int(tmin)
    while t <= tmax:
        o.append(f'<line x1="{X(t):.1f}" y1="20" x2="{X(t):.1f}" y2="{H-10}" class="grid"/>'
                 f'<text x="{X(t)+2:.1f}" y="14" class="dim">{t}s</text>')
        t += 1
    y = 26
    for name, a, b, kind in segs:
        w = max((b - a) * scale, 1)
        o.append(f'<text x="4" y="{y+11}" class="fg">{html.escape(name[:38])}</text>'
                 f'<rect x="{X(a):.1f}" y="{y+2}" width="{w:.1f}" height="{RH-4}" fill="{COLORS[kind]}" rx="2">'
                 f'<title>{html.escape(name)}: {a:.3f} → {b:.3f} ({(b-a)*1000:.0f} ms)</title></rect>')
        if b - a >= 0.15:
            o.append(f'<text x="{X(b)+3:.1f}" y="{y+11}" class="dim">{(b-a):.2f}s</text>')
        y += RH
    y += RH
    for t, name in events:
        o.append(f'<text x="4" y="{y+11}" class="fg">{html.escape(name[:38])}</text>'
                 f'<circle cx="{X(t):.1f}" cy="{y+8}" r="4" fill="#e25555"><title>{html.escape(name)} @ {t:.3f}s</title></circle>'
                 f'<text x="{X(t)+7:.1f}" y="{y+11}" class="dim">{t:.2f}s</text>')
        y += RH
    o.append("</svg>")
    keys = ["uboot_s", "kernel_t0", "init_k", "beam_k", "script_start_k", "primload_s", "script_done_k", "iex_k", "iex_total"] + sorted(k for k in m if k.startswith("net_"))
    table = "".join(f"<tr><td>{k}</td><td>{m[k]}</td></tr>" for k in keys if m.get(k) is not None)
    doc = f"""<!doctype html><html><head><meta charset="utf-8"><title>Boot chart</title>
<style>
:root{{--bg:#fff;--fg:#1d1f23;--dim:#6b7078;--grid:#e6e8eb}}
@media (prefers-color-scheme: dark){{:root{{--bg:#16181c;--fg:#e4e6ea;--dim:#9096a0;--grid:#2a2d33}}}}
body{{background:var(--bg);color:var(--fg);font-family:system-ui,sans-serif;margin:16px}}
.fg{{fill:var(--fg)}} .dim{{fill:var(--dim)}} .grid{{stroke:var(--grid)}}
.wrap{{overflow-x:auto}} td{{padding:1px 10px;font-family:ui-monospace,monospace;font-size:12px}}
</style></head><body>
<h2>Boot chart: {html.escape(rec['label'])} <small style="color:var(--dim)">{rec['ts']}</small></h2>
<p>Kernel uptime clock. Grey: U-Boot/handoff (serial). Blue: kernel/erlinit. Orange: boot-script module loading. Green: OTP application start. Red dots: events.</p>
<table>{table}</table>
<div class="wrap">{''.join(o)}</div></body></html>"""
    open(out, "w").write(doc)
    print(out)

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("run", nargs="?")
    ap.add_argument("--latest")
    ap.add_argument("-o")
    a = ap.parse_args()
    rec, rep = load(label=a.latest, prefix=a.run)
    out = a.o or os.path.join(RES, f"bootchart-{rec['ts']}-{rec['label']}.html")
    render(rec, rep, out)
