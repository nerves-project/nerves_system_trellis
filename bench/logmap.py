#!/usr/bin/env python3
"""Map a diag boot log ("<monotonic_us> message") onto kernel uptime.
Input file: line 1 = "<uptime> <monotonic_us>" sampled together, then the log.
Usage: logmap.py FILE [REGEX]"""
import re, sys
L = open(sys.argv[1]).read().splitlines()
up, mono = L[0].split()[:2]
off = float(up) - int(mono) / 1e6
rx = re.compile(sys.argv[2]) if len(sys.argv) > 2 else None
for l in L[1:]:
    m = re.match(r"^(-?\d{6,}) (.*)", re.sub(r"\x1b\[[0-9;]*m", "", l))
    if m and (not rx or rx.search(m.group(2))):
        print(f"{int(m.group(1)) / 1e6 + off:7.3f} {m.group(2)[:170]}")
