# Experiment log

Protocol: one change at a time, ≥5 reboots per variant, compare medians of
`iex_k` (and `iex_total`, `net_*_k`). Keep a change only if the median
improves by more than the run-to-run spread.

## Baselines

### B0: nerves_livebook 0.19.6 (Nerves 1, shoehorn, squashfs, OTP 29.0) — 2026-10-17

5 soft reboots, medians: U-Boot→kernel 0.84 s, kernel clock zero 1.52 s after
the U-Boot banner, `/sbin/init` 0.56 s, `beam.smp` 0.84 s, usb0 up 17.9 s,
**IEx prompt 18.16 s uptime** (range 18.01–18.23), 19.67 s from U-Boot banner.

On-device decomposition of the ~13 s between `beam.smp` start and heart:
3,132 modules / 31.7 MB preloaded in embedded mode. Reading them by full path
costs 0.75–2 s warm / 6.2 s cold with path search, `prepare_loading` costs
7.9 s on one core / 4.6 s on two. A failed `prim_file:read_file` costs
~0.4–0.48 ms whether the cache is cold or warm, even in a missing directory. Each
app's boot path is `[consolidated, app/ebin]`, so ~3,000 modules miss once in
`consolidated/` (~1.2–1.5 s serial, split over 3 loader workers).

### B1: boot_bench (Nerves 2 pre.4 + v2 branch, EROFS lz4hc, OTP 29.1.2, interactive mode) — 2026-10-17

`mix nerves.new` template ported to Nerves 2 (nerves_pack, toolshed,
ring_logger), 38 apps, 504 modules loaded at the end. 5 runs: **IEx 5.90 s
uptime** (5.71–6.04), 7.43 s from U-Boot banner. `beam.smp` 0.75 s, VM start
0.93 s.

The template doesn't set `-mode`, so the release boots in interactive mode
(lazy loading with OTP 26+'s boot path cache). Boot-script `primLoad` is ~5
ms. The time is in app starts (one run): `vintage_net` 1.42 s,
`nerves_runtime` 0.60 s, `Config.Provider.boot` 0.57 s, `kernel` 0.48 s,
`application_controller` 0.24 s, `ssl` 0.18 s, `mdns_lite` 0.14 s. Script done
→ IEx 0.18 s.

## Results

| id | variant | IEx (uptime, median of 5) | Δ vs B1 | notes |
| --- | --- | --- | --- | --- |
| B1 | boot_bench interactive (default) | 5.90 s | — | 504 modules loaded at end |
| E1 | `-mode embedded` | 7.97 s | +2.07 s | primLoad 4.58 s, 1,073 modules |
| E2 | embedded + exact boot paths | 7.90 s / 7.85 s (2 batches) | +2.0 s | ~0.07 s better than E1: path misses aren't the cost |
| E3 | embedded + single-file bundle | crashed | — | bundle load 4.04 s for 1,021 modules (one `-init_debug` boot); then "Could not start kernel pid (application_controller) (normal)", U-Boot reverted |

| E4 | defer vintage_net/mdns_lite/ssl/inets (+dependents) to a background start | IEx 5.03 s, ready 6.16 s | IEx −0.87, ready +0.36 | moves work after IEx and competes with it; usb0 later |
| E5 | E4 with deferred starter at low priority | IEx 4.89 s, ready 6.07 s | IEx −1.0, ready +0.27 | rejected: production cares about ready, not IEx |
| B2 | baseline remeasured with ready metric | IEx 5.90 s, **ready 5.80 s** | — | ready = max(all apps started, network iface :lan) |
| E6 | profile-guided background preload (481 modules from a previous boot, app order, `code:ensure_modules_loaded/1` chunks of 16, waits for `code_server`) | IEx 5.09 s, **ready 5.45 s**, apps 4.97 s | IEx −0.81, ready −0.35, apps −0.83 | **kept**. vintage_net start drops from 1.43 s to 0.03 s; usb0 now the last item |

| E7 | E6 + no runtime config provider (RingLogger added in `Application.start/2`), same contaminated 482-module profile | ready 5.36 s | −0.44 | profile included modules loaded by my ssh report eval |
| E7b | no runtime config, no preload (1 run) | ready 5.64 s | −0.16 | |
| E8 (invalid) | E7 with a clean profile (348 modules snapshotted at `iex.exs`, before any ssh) | IEx 4.48 s, apps 4.31 s, **ready 4.83 s** | IEx −1.42, apps −1.49, **ready −0.97** | invalid: `Mix.target()` called at runtime crashed `boot_bench`'s start, so RingLogger wasn't running (temporary app, boot continued silently) |
| E8b | E8 fixed (compile-time target check), profile re-taken (349 modules) | IEx 4.72 s, apps 4.32 s, **ready 4.80 s** | IEx −1.18, apps −1.48, **ready −1.00** | **kept**. 38 apps + RingLogger verified. Profile hygiene matters |
| E9 | E8 + no `eth0` in VintageNet config | ready 4.78 s | −0.05 vs E8 | noise; not kept |

measure.py now records started apps and RingLogger state per run and warns
when they differ, after E8 showed that a broken app start can look like a win.

| E10 | E8b + `toolshed`, `ssl`, `inets` as `:load` (only toolshed needs them, for HTTP helpers) | apps 3.53 s (3 of 5 runs), **ready 4.77 s** | apps −0.8, ready −0.03 | apps finish earlier but the network doesn't move; 35 apps by design |

Critical path is now the network (diag builds with BOOT_DIAG=1 log to
/tmp/boot.log with monotonic timestamps; `diaglog.sh` + `logmap.py`): with
E10, all apps are started by 3.61 s and VintageNet starts at 3.49 s, but all
three interfaces log their first "internal configure" only at ~4.33 s, usb0 is
`:lan` at 4.91 s, and wpa_supplicant starts at 4.97 s. The ~0.8 s gap before
the first configure step is the next thing to explain. Restart-timing test
on a running device is pending (lost the USB link). Also: nerves_logging
replays ~250 kernel log lines through Logger at ~3.1 s; nerves_time sets the
system clock mid-boot (3.4–4.5 s), so log timestamps must use the monotonic
clock.

### Priorities (Jon, 2026-10-17)

Focus on time to critical local systems first, then the console (IEx), then
networking. WiFi tuning is parked. Trellis is the test bed, but the goal is
speedups that apply to Nerves systems in general (Linux + BEAM).

### WiFi (parked)

The bench now runs over WiFi (`kabellos`, configured over serial), because
the Mac's USB Ethernet driver wedges. E8b over WiFi: apps 4.28 s, IEx 4.46 s,
wlan0 `:lan` **10.41 s** (10.27–12.16). Timeline (diag build): wlan0
configure 4.33 s → rtw88 registered 4.39 s → wpa_supplicant ready 5.00 s →
**~2 s scan** → auth/assoc 7.05–7.79 s → udhcpc starts on association (7.80 s)
and its first DISCOVER (7.90 s) goes out **before the WPA 4-way handshake
completes (7.97 s)**, so it's lost and busybox retries 3 s later → lease
10.32 s. Two clear WiFi wins for later: start DHCP on CTRL-EVENT-CONNECTED or
use `udhcpc -T 1` (~−2 s), and `scan_freq` for known networks (~−1.5 s).
Patches with compile-time knobs are in `patches/` (BOOT_UDHCPC_T,
BOOT_SCAN_FREQ). The WE1 run (`-T 1`) is invalid: a forced deps.compile
outside the Nerves environment built `if_monitor` for macOS (no interfaces at
all); variant.sh now recompiles inside the Nerves env and checks the binary
is ARM.

### Kernel initcalls (`initcall_debug` via U-Boot `console_args`, no rebuild)

`jent_mod_init` (CPU jitter entropy RNG self-test) takes **230 ms**, which
explains the gap after squashfs init. Next: `deferred_probe_initcall` 80 ms,
`of_platform_default_populate_init` 20 ms, everything else <11 ms. Jitter
entropy is built in because `CONFIG_CRYPTO_ECDH=y` (in the defconfig since the
initial commit) selects the default crypto RNG → DRBG → jitterentropy. BT is a
module, so dropping `=y` should leave ECDH/DRBG/jitterentropy as modules,
loaded only if Bluetooth is used. Likely applies to other Nerves systems with
crypto options built in: check their defconfigs.

| K1 | E8b + kernel without `CONFIG_CRYPTO_ECDH=y` (no built-in jitterentropy) | init 0.32 s, beam 0.53 s, **apps 4.10 s**, U-Boot→IEx 5.79 s | init −0.23, apps −0.18, U-Boot→IEx −0.18 | **kept** (system change). `jent_mod_init` gone from boot |

| K2 | K1 + LZ4-compressed zImage (`BR2_LINUX_KERNEL_LZ4=y`; Buildroot overrides `CONFIG_KERNEL_*` in the kernel defconfig) | U-Boot→kernel clock 1.16 s, U-Boot→IEx 5.63 s | −0.12 / −0.16 | **kept**. zImage 4.85 → 5.65 MB; U-Boot +0.03 s from reading/hashing more |
| K3 | K2 + U-Boot reads only the FIT's size (header `totalsize`) instead of a fixed 8 MB `fit_count` | U-Boot→handoff 0.76 s, U-Boot→IEx 5.52 s | −0.11 / −0.11 | **kept** (`uboot/uboot.env` `fit_boot`). U-Boot MMC reads ~21 MB/s, so every unneeded MB costs ~50 ms. Applies to any FIT-based Nerves system with a padded slot |

| K4 | K3 + FIT image hashes crc32 instead of sha256 (`trellis.its`) | U-Boot→handoff 0.56 s, U-Boot→IEx 5.29 s | −0.21 / −0.22 | **kept**. Still detects storage corruption; fwup verifies images at write time; no FIT signatures are used here. Systems that sign FITs need sha256 + signature (or hardware SHA) |

(Before K4) U-Boot spent ~0.26 s on sha256 of the 5.6 MB kernel (between
"Loading kernel" and "Loading fdt").

| F1 | K4 + EROFS without compression (`BOOT_ROOTFS=erofs-none`) | script start 1.28 s, apps 4.23 s, U-Boot→IEx 5.51 s | +0.08 / +0.13 / +0.21 | rejected: rootfs 25 → 44 MB, MMC reads cost more than lz4hc decompression saves |

### Frank's asks (re-read 2026-10-17)

Primary metric: **time to IEx prompt**; WiFi is the endpoint for most
people; wants a bootchart-like view of Erlang boot; hypothesis: load Linux
drivers earlier (nerves_uevent) to overlap I/O with BEAM CPU; needs
multi-second wins. So report both `iex_k` and system readiness. The
deferred-networking variant (E4/E5, IEx −1.0 s) becomes an opt-in for the
IEx metric rather than a rejection. Still to do: driver-early hypothesis,
Livebook-scale test, shareable bootchart.

| F2 | K4 + background driver coldplug from erlinit `pre_run_exec` (Frank's hypothesis; `modprobe -a` over `/sys/bus/*/devices/*/modalias`, again 1 s later for USB) | drivers loaded 1.66–2.06 s instead of ~2.9–3.4 s; IEx 4.44 s, apps 4.06 s, wlan0 `:lan` 7.42 s | IEx −0.06, apps −0.04, wlan0 `:lan` −0.13 (vs `best`: IEx 4.50, apps 4.10, wlan0 `:lan` 7.55) | ~0.1 s, as Frank guessed. Drivers aren't on the critical path: VintageNet only starts configuring wlan0 ~4.3 s, then scan and DHCP dominate. Keep in mind for WiFi work |

| I1 | `best` + IEx-first (defer vintage_net/mdns_lite/ssl/inets to a low-priority background start) | script done 3.12 s, IEx 4.62 s, usb0 IPv4 4.56 s | IEx +0.12 | rejected with preload on: IEx then waits ~1.5 s in `iex.exs` (the MOTD needs the deferred apps) |
| I2 | `best` + MOTD printed asynchronously (`spawn(fn -> NervesMOTD.print() end)` in `iex.exs`) | **IEx 4.11 s**, U-Boot→IEx 4.97 s | **IEx −0.39** | **kept** for IEx. The template's synchronous MOTD costs ~0.4 s before the prompt (system queries + ~1.5 KB at 115200 baud). The prompt now appears ~10 ms after `iex.exs` starts |
| I3 | I1 + I2 | IEx 4.04 s, apps 4.42 s, usb0 IPv4 4.79 s | IEx −0.07 vs I2, network +0.3 | not worth it |
| I4 | I2 without `use Toolshed` | IEx 4.11 s | 0 | `use Toolshed` is cheap once preloaded. With MOTD off and Toolshed not yet preloaded it showed ~0.4 s bimodally |

**Cumulative (boot_bench, IEx metric):** B1 5.90 s uptime / 7.43 s from
U-Boot → I2 4.11 s / 4.97 s (−1.79 s / −2.46 s).

measure.py now records the first `:lan`, IPv4 and `:internet` time per
interface (BootBench.NetEvents subscribes to VintageNet at app start).
VintageNet reports `:lan` at WiFi association, before DHCP.

### Livebook (large app, 124 apps) — 2026-10-17

nerves_livebook main (7e11b91) ported to Nerves 2 (v2 branch, no shoehorn,
OTP 29.1.2) on this branch's system (K1–K4: no built-in jitterentropy, LZ4
kernel, header-sized FIT read, crc32 FIT hashes), with `boot_tools` added.
Upstream ships `-mode embedded` and keeps `Docs` chunks in beams. 5 boots
each, uptime:

| variant | IEx | U-Boot→IEx | apps started | usb0 IPv4 | wlan0 IPv4 |
| --- | --- | --- | --- | --- | --- |
| B0 original firmware (Nerves 1, OTP 29.0, squashfs) | 18.16 | 19.67 | — | — | — |
| LB1 Nerves 2 + system, `-mode embedded` | 17.28 | 18.13 | 17.01 | 16.36 | 23.24 |
| LB2 `-mode interactive` | 11.88 | 12.75 | 11.50 | 6.49 | 13.38 |
| LB3 interactive + profile-guided preload (698 modules) | **7.83** | **8.71** | 7.46 | 6.47 | 13.18 |

| LB4 | LB3 + async MOTD | **7.40** | **8.26** | 7.43 | 6.55 | — |
| LB5 | LB4 + strip `Docs` chunks | 7.41 | 8.26 | 7.44 | 6.51 | — |

| LB6 | LB4 with preload chunks of 8 | 8.19 | 9.06 | 8.24 | 6.58 | — |
| LB7 | LB4 with preload chunks of 64 | 7.07 | 7.94 | 7.10 | 6.42 | — |
| LB8 | LB4 with preload chunks of 256 | **6.60** | **7.47** | 6.66 | 6.26 | — |
| LB9 | LB4 with one batch of all 698 modules | 6.73 | 7.59 | 6.77 | 6.38 | — |

Each preload chunk ends with one `finish_loading` in `code_server`, so larger
chunks serialize less; one giant batch blocks on-demand loads a little longer.
boot_bench: chunk 64 → IEx 4.09 s, chunk 256 → **4.05 s** (16 was 4.16 s with
boot_tools). Default is now 256. **Livebook IEx: 18.16 s → 6.60 s (−11.6 s).**

LB5 is inconclusive: the firmware was identical to LB4's (the strip setting
didn't apply), and `Docs` are only ~4% of Livebook's beam bytes (220 KB of
5.4 MB), so the expected effect is small anyway.

Embedded mode preloads 3,132 modules (11.9 s of `primLoad`) although only
~700 are used by the time IEx starts. Interactive + preload: **−10.3 s to IEx
vs the original firmware**, −9.9 s to network.

Slowest Livebook steps after LB4: `vintage_net` start 1.42 s (127 lazily
loaded modules the preload hadn't reached), `Config.Provider.boot`
(`runtime.exs`) 1.39 s (267 modules: Elixir's evaluator/compiler), `kernel`
start 1.15 s (120 modules, likely Livebook's Elixir EPMD module pulling Elixir
into kernel start), `nerves_runtime` 0.52 s, `livebook` 0.37 s, `jose` 0.35 s.
CPU busy 9.45 of 12.37 CPU-s during the boot script (76%).

### Before U-Boot's banner (reset → banner) — corrected

An earlier entry here said reset → banner took 1.93 s. That was a harness
bug: lines are stamped with the arrival time of their first byte, and the
kernel's "reboot: Restarting system" message was appended to a console line
(the IEx prompt) that had started long before. bootcap now stamps the restart
message by when its own bytes arrive: **reset → banner = 0.69 s**
(0.66–0.69), of which 0.5 s is the soft-reboot watchdog delay (Linux restarts
sunxi via the watchdog at its minimum interval). U-Boot's own `reset` → banner
is 0.78 s.

A bootstage-instrumented U-Boot (`uboot/0004-sunxi-bootstage-timing.patch`:
`timer_get_boot_us()` from the 24 MHz ARM generic counter; plus
`CONFIG_{SPL_,}BOOTSTAGE`, `BOOTSTAGE_REPORT`, `BOOTSTAGE_STASH` at
0x43f00000) was written to the board (original backed up as
/root/uboot-backup-orig.bin). Counter timeline:

| µs since counter start | mark |
| --- | --- |
| 0 | reset |
| 25,424 | SPL starts |
| 81,379 | SPL done (incl. DDR3 init; DRAM auto-scan is *not* slow) |
| 82,052 | U-Boot proper `board_init_f` (driver model pre-reloc: 72 ms) |
| 211,860 | `board_init_r` |
| 309,222 | `eth_common_init` (USB gadget Ethernet / RNDIS: ~97 ms) |
| 320,703 | `main_loop` |
| 642,052 | `bootm_start` (env, FIT header + 5.7 MB read ≈ 0.27 s) |
| 751,216 | kernel starts |

U-Boot built with `CONFIG_NO_NET=y` (no USB gadget Ethernet): kernel starts
at 723 ms instead of 751 ms (−28 ms; most of the gap before
`eth_common_init` was other `board_init_r` work). Not kept: RNDIS may be used
and the gain is small. From `main_loop` to `bootm_start` (~0.32 s) is mostly
reading the 5.7 MB FIT at SD high-speed rates (~21 MB/s), so a smaller kernel
is the lever there (~50 ms/MB).

Note: every measurement so far ran the board's original U-Boot (from the
Livebook-era fresh install); fwup upgrades never rewrite U-Boot. That
original is restored after the bootstage experiments.

So a cold boot spends ~0.1 s in BootROM+SPL. U-Boot proper's biggest
avoidable items are the network/USB-gadget init (~0.1 s) and driver-model
setup (72 ms). The bootstage report itself adds ~0.13 s of console output.

### Toolchain hardening (PIE / SSP / RELRO), clean full rebuild

Buildroot defaults build everything as PIE with `-fstack-protector-strong`
and full RELRO (BIND_NOW). With all three off (`# BR2_PIC_PIE is not set`,
`BR2_SSP_NONE`, `BR2_RELRO_NONE`; `beam.smp` confirmed non-PIE), same app
settings (preload profile v4, no runtime config, async MOTD):

| app | hardened | hardening off | Δ |
| --- | --- | --- | --- |
| boot_bench apps / IEx | 3.97 / 4.03 s | 3.85 / 3.88 s | −0.12 / −0.15 |
| Livebook IEx | 6.60 s (LB8) | 6.79 s | +0.19 (noise) |

Not worth dropping hardening; reverted. Also: the earlier "slow `ssl`" and
"slow `boot_tools`" steps were waits behind the last preload batch for
modules missing from the profile (fixed by re-profiling: boot_bench-v4).

### Slimming the always-loaded first module group (`BOOT_FIRST_DROP`)

systools puts `erl_parse`, `erl_lint` and `erl_eval` (403 KB of 786 KB) in the
first primLoad group, which is loaded before anything else in every mode.
Same settings as `hard-on` (IEx 4.03 s):

| dropped from first group | script start | apps | IEx | U-Boot→IEx |
| --- | --- | --- | --- | --- |
| none (hard-on) | 1.197 | 3.966 | 4.027 | 4.902 |
| erl_lint, erl_eval | 1.133 | 3.937 | 3.995 | 4.856 |
| erl_lint, erl_eval, erl_parse | **1.071** | **3.925** | **3.961** | **4.805** |

All 39 apps and RingLogger run in both. Interactive mode loads them lazily
when used (the preload profile includes them). ~−0.07 s to IEx; worth
offering as an option, not a default, since anything that evaluates or
parses Erlang terms before `code_server` is up would break.

### erlinit: write the next boot's RNG seed in parallel (K5)

`patches/erlinit/0001-Save-the-next-boot-RNG-seed-while-Erlang-starts.patch`
(system `BR2_GLOBAL_PATCH_DIR` now includes `${NERVES_DEFCONFIG_DIR}/patches`).
seedrng's load+credit (incl. the unlink + directory fsync that must precede
crediting) stays before launch; writing + fsyncing the new seed happens in a
forked process right before erlinit execs erlexec. Same settings as hard-on:

| | hard-on | K5 | Δ |
| --- | --- | --- | --- |
| beam.smp | 0.53 | **0.45** | −0.08 |
| apps | 3.97 | **3.85** | −0.12 |
| IEx | 4.03 | **3.92** | −0.11 |

`crng init done` still at 0.447 s (before the BEAM), and the next boot's
`seed.credit` is written. General erlinit improvement; worth upstreaming.

### WiFi hints, measured (final config + patched deps, 5 boots each)

| variant | wlan0 associated (`:lan`) | wlan0 IPv4 |
| --- | --- | --- |
| final-bb (stock vintage_net) | 7.39 s | 10.41 s |
| + `udhcpc -T 1` (`BOOT_UDHCPC_T=1`) | 7.24 s | **8.34 s** (−2.07) |
| + `scan_freq=2412` (`BOOT_SCAN_FREQ`) | 5.74 s | **6.37 s** (−1.98 more) |

The `-T 1` result confirms the lost-first-DISCOVER diagnosis (DISCOVER sent
before the WPA 4-way handshake completes). A fixed `scan_freq` is fragile
(the AP can change channel and wpa_supplicant then won't find it); the
robust version is scanning the last-known frequency first with a full-scan
fallback, which would be a VintageNet/VintageNetWiFi feature.

### nerves_uevent (Frank's suggestion to pick on it)

`BOOT_PROC_SNAPSHOT=1` records every process's reductions when the boot
script finishes; the report adds `NervesUEvent.UEvent.stats/0`, the property
count and the uevent port's CPU time (including reaped modprobe children).
Final small-app config, at script end (3.87 s):

- Coldplug: 398 uevents (395 `add`), 382 properties. NervesUEvent's
  processes (UEvent, its PropertyTable updater, InputListener) ≈ 54k
  reductions, ~7% of live processes' reductions (`code_server` is 45%).
- Port program: 30 ms CPU; its modprobe children: **230 ms CPU**, nearly
  all kernel time loading the WiFi stack.

| variant | apps | IEx | wlan0 IPv4 |
| --- | --- | --- | --- |
| ue-base (final config) | 3.87 | 3.92 | — |
| modprobe off, drivers loaded by a pre-BEAM background coldplug | 3.97 | 4.01 | 10.41 |
| + no coldplug scan at all (`NERVES_UEVENT_SKIP_DISCOVER`, upper bound) | 3.85 | 3.84 | 10.38 |

So handling the coldplug event storm costs ~0.12–0.17 s here, and loading
drivers before the BEAM doesn't help on 2 busy cores (it competes with BEAM
startup). Every event is its own port message plus its own
`PropertyTable.put` call; batching (e.g. `put_many` per port read) is the
obvious improvement. Boards with more devices pay proportionally more.

Bug found: `NervesUEvent.stats/0` (nerves_uevent 0.1.7) is
`def stats(), do: NervesUEvent.stats()` and recurses forever; it should
delegate to `NervesUEvent.UEvent.stats/0`. Calling it hung the IEx console.

### Kernel trim (not kept)

Dropped built-in SquashFS, IPv6 Mobile IPv6, CAN debug devices and the
SUN4I_SS/SUN8I_SS crypto drivers (other SoCs), and made CAN + J1939 + ISO-TP +
sun4i CAN modules: zImage 5.65 → 5.47 MB. Kernel clock zero 0.842 vs 0.858 s
(−16 ms), U-Boot→IEx 4.74 vs 4.78 s (noise). Reverted: not worth changing
what's built in. The kernel's config is already lean; image size costs
~50 ms/MB of U-Boot read.

### Where app-start time goes (microstate accounting, current best, 1 boot)

`boot_trace` turns on ERTS microstate accounting at boot-script start and
snapshots it plus /proc/stat at `script_done`. Boot script (1.20 → 4.11 s,
2.91 s wall, 5.82 CPU-s available on 2 cores): system busy 3.96 CPU-s (user
3.07 + kernel 0.89), idle 1.65, iowait 0.17. BEAM normal schedulers:
emulator 3.62 s (Erlang code incl. `prepare_loading`), GC 0.08, sleep 1.87.
Dirty I/O schedulers: 1.65 s inside file NIFs (reads and stats). So the
phase is mostly CPU-bound: code loading/execution plus file reads, including
in-kernel EROFS lz4hc decompression. A per-process sampler was too costly on
the T113 (~40 ms per tick, +0.5 s boot); it stays in `boot_trace` for faster
CPUs but is off.

### BEAM start (beam.smp exec → boot script start ≈ 0.67 s after K1)

A second, throwaway VM on the running board (warm cache) with the
release's `start_clean` boot: 780 ms to `halt`. With `-init_debug` the first
`primLoad` group (32 modules, 786 KB, always loaded before `code_server` can
load lazily) takes **262 ms**. Half of those bytes are `erl_parse` (226 KB),
`erl_lint` (129 KB) and `erl_eval` (48 KB): systools marks them mandatory
because `application_controller` parses `sys.config` with them before any
lazy loading is possible. Leads: avoid text `sys.config` parsing at boot, or
make the first group smaller/faster to prepare.

Harness hardening: variant.sh aborts on build failure (it used to flash the
previous image), touches mix.exs to force env-driven recompiles, and checks
the running firmware UUID. Reboots go over the serial console and reports
fall back to serial when ssh is down.

Network bring-up (E9 trace): `nerves_uevent` runs modprobe at 2.71 s, the
rtw88 WiFi driver registers at 3.38 s, `wlan0` reaches `:configured` at 4.76 s
(wpa_supplicant 4.78 s) and usb0 goes `:lan` right after, at 4.79 s. Next:
find out why usb0 waits for wlan0, and load drivers before the BEAM.

Takeaways so far:

Takeaways so far: interactive mode with OTP's boot path cache already
gets most of the benefit of the "known layout" idea. In embedded mode the cost
is `prepare_loading` (CPU), not lookups. For apps like Livebook built with
`-mode embedded`, simply switching to interactive is probably worth seconds.

### Frank's review, round 2 (2026-10-18)

#### What `:preload_start` is doing

Preload-chunks run, per-chunk marks.
`boot_preload` starts at 1.068 s and first waits 397 ms for `code_server`
(started inside the kernel app). Chunk 1 (256 modules) then takes 886 ms and
chunk 2 (97) 196 ms; preload is done at 2.548 s. `ensure_modules_loaded`
spawns one process per module, so during chunk 1 the boot process itself is
starved on 2 cores: its kernel → next step took 945 ms. In effect the preload
front-loads ~350 modules in parallel. The bootchart now draws preload chunks
in their own lane, and boot-step durations only use the boot process's marks.

#### Order of the list

The preload list is not in load order: the profile
(`.mods`) is alphabetical, and the boot script's list is grouped by
application start order and alphabetical within each app. Comments fixed.

#### A compile-time module set (no profile)

Same build
(`BOOT_NO_RUNTIME_CONFIG=1 BOOT_FIRST_DROP=…`, sync MOTD), 5 boots each:

| label | preload set | modules | apps_k | iex_k |
| --- | --- | --- | --- | --- |
| bb-nopreload | none | 0 | 5.248 | 5.909 |
| preload-chunks (3) | profile (`boot_bench-v4.mods`) | 350 | **3.845** | **4.207** |
| bb-preload-all | every module in the boot script | 1,028 | 5.549 | 5.924 |
| bb-reach-2 | reachable from app callback modules, 2 hops | 386 | 5.037 | 5.466 |
| bb-reach | reachable, all hops | 767 | 6.054 | 6.298 |

Reachability follows module names in each `.beam`'s atom table from each
started app's `mod` callback, limited to modules in the boot script
(`BOOT_PRELOAD=reach[:depth]`). Depth 2 covers 222 of the profile's 350
modules plus 164 that aren't used at boot; depth ≥4 covers ~305 but drags in
~450 extras. Extra loads compete with the boot process for the 2 cores, so
the best compile-time set (depth 2) gets only ~25% of the profile's IEx gain
(−0.44 s vs −1.70 s) and loading everything is a wash or worse. The profile
wins because it is both small and nearly all used.

#### Does the preload order matter? No

Recorded the real first-load order on a
no-preload boot (`boot_load_order` in the report: `erlang:loaded/0`
reversed; stable across 3 boots, mean rank change < 1), then preloaded the
same 356 modules in different orders (5 boots each, chunks of 256 unless noted):

| label | order | apps_k | iex_k |
| --- | --- | --- | --- |
| bb-order-rec (3) | no preload | 5.338 | 5.979 |
| ord-app | grouped by app start order, alphabetical within app (the default) | 3.846 | 4.279 |
| ord-load | recorded first-load order (`BOOT_PRELOAD_ORDER=file`) | 3.848 | 4.291 |
| ord-alpha | alphabetical | 3.845 | 4.326 |
| ord-rev | first-load order reversed (control) | 3.866 | 4.275 |
| ord-load-c64 | first-load order, chunks of 64 | 3.879 | 4.373 |

All within noise (±0.05 s), even reversed. The order doesn't matter on this
app: the preload finishes (~2.5 s) long before the boot script reaches most
of the modules, so what counts is which modules are in the set, not their
order. Smaller chunks are slightly worse, as before.

#### Console coupling (async MOTD)

`apps_k` is the same with sync MOTD
(best 4.098 s), async (4.114 s) and no MOTD (4.122 s): printing to the
console does not delay app start. The MOTD only delays the prompt (gathering
its info plus ~1.5 KB at 115200 baud). Async MOTD is cosmetic; dropped from
"adopt".

### Ideas for Erlang/OTP (2026-10-18)

What OTP 29.1.2 does today (source read): embedded mode's `primLoad`
already prepares modules in parallel (`erl_prim_loader:get_modules`, a
bounded pool of `schedulers + schedulers/2` workers reading files directly),
but one application's group at a time. `code:ensure_modules_loaded/1` (used
by our preload) spawns one process per module, and each one asks
`code_server` for the file and reads it through `erl_prim_loader`.
`erts_internal:prepare_loading/2` runs to completion on a normal scheduler
(no yielding, no reductions bumped). Template app unless noted, stock OTP,
5 boots each, medians.

#### 1. Load all embedded-mode groups in one pass (`BOOT_ELOAD`): a win

`boot_eload` replaces every `primLoad` group after `kernel_load_completed`
with one call: N workers read files by exact path and prepare them, the boot
process installs them in batches of 128 and reports them to init like
`primLoad` does.

| label | app | load phase | apps_k | iex_k |
| --- | --- | --- | --- | --- |
| emb-base | template, `-mode embedded` | 4.394 | 7.271 | 7.618 |
| emb-eload | same, one pass | 4.003 | 6.896 | 7.283 |
| lb-emb-base | Livebook, `-mode embedded` (3,132 modules) | | | 16.605 |
| lb-emb-eload | same, one pass | | | **15.175** |

−0.35 s on the template app, **−1.43 s on Livebook** (124 groups). In OTP
this would be a change to `init` (load consecutive `primLoad` groups
together, using each group's path) or to `systools` (emit one group). First
attempt crashed the boot: the boot process traps exits, so linked workers'
`'EXIT'` messages were taken by init's next `kernelProcess` start as its
reply ("Could not start kernel pid (application_controller) (normal)");
monitors fixed it.

#### 2. Bounded preload pool (`BOOT_PRELOAD_POOL`): no win

Pool of N workers reading by exact path (no `code_server`/`erl_prim_loader`
round trips), preparing before `code_server` starts, installing in batches
of 32 via `code_server:call({finish_loading, …})`.

| label | preload | apps_k | iex_k |
| --- | --- | --- | --- |
| ord-app | `ensure_modules_loaded`, chunks of 256 (current) | **3.846** | **4.279** |
| pool2 | 2 workers | 4.073 | 4.554 |
| pool2-low | 2 workers, low priority | 3.916 | 4.454 |
| pool1 | 1 worker | 4.202 | 4.610 |
| pool1-low | 1 worker, low priority | 4.113 | 4.522 |

Why: without preload the kernel app starts in 0.47 s; with any preload it
takes ~0.94 s, because preloading competes with the boot process for the 2
cores. Low priority barely helps: a single `prepare_loading` holds a
scheduler for up to 98 ms (`unicode_util`), whatever the priority.

#### 3. `prepare_loading` on a dirty CPU scheduler (OTP patch): no win

Patch in `bench/patches/otp/` (branch `dirty-prepare-loading` in a local
OTP clone): modules > 16 KB are prepared on a dirty CPU scheduler, like
`integer_to_list/1` does for big integers. Applied to the system's Erlang:

| preload | stock apps / IEx | patched apps / IEx |
| --- | --- | --- |
| none | 5.338 / 5.979 | 5.300 / 6.110 |
| `ensure_modules_loaded` (current) | **3.846 / 4.279** | 4.070 / 4.519 |
| pool, 2 workers | 4.073 / 4.554 | 3.878 / 4.366 |
| pool, 2 workers, low | 3.916 / 4.454 | 3.900 / 4.360 |

It helps the pool but hurts the current preload, and the best result is
no better. Not worth proposing for boot time. The system was rebuilt with
stock Erlang afterwards.

#### 4. Concurrent application start (`BOOT_CONCURRENT=1`): faster apps and network, same prompt

Replaces the boot script's sequential `application:start_boot/2` calls
(after kernel and stdlib) with one `application:ensure_all_started(Apps,
permanent, concurrent)`.

| label | app | apps_k | iex_k | usb0 IPv4 |
| --- | --- | --- | --- | --- |
| ord-app | template | 3.846 | 4.279 | 4.25 |
| conc | template, concurrent | **3.061** | 4.367 | **3.09** |
| lb-best | Livebook (interactive + preload) | 6.522 | 6.891 | 6.10 |
| lb-conc | same, concurrent | 6.598 | 6.969 | 5.98 |

Template app: all apps are up 0.8 s sooner and usb0 gets its address 1.2 s
sooner, but the prompt doesn't move: `iex.exs` starts at 3.0 s and the
synchronous MOTD then takes 1.37 s instead of 0.38 s while the apps finish
their post-start work. Livebook: no change (it's CPU-bound with the
preload). Worth offering as a boot script option (systools/`mix release`).

#### 5. Mandatory first group: no win alone

systools' `mandatory_modules/0` says only `error_handler` is truly
mandatory; the rest are "almost always needed". Recorded first-load order:
`sys.config` parsing loads `erl_scan`, `erl_anno`, `erl_features`,
`erl_parse` (#38–41); `erl_lint` isn't loaded before IEx and `erl_eval`
only at #354 of 356.

| label | first group | apps_k | iex_k |
| --- | --- | --- | --- |
| first-full | as shipped | 3.877 | 4.255 |
| first-drop2 | without `erl_lint`, `erl_eval` | 3.853 | 4.287 |
| ord-app | without `erl_lint`, `erl_eval`, `erl_parse` | 3.846 | 4.279 |

Within noise once the preload runs on the second core.

#### 6. Per-module load cost (`probes/prepcost.exs`)

All 1,093 release beams (12.9 MB) prepare in 3.54 s on one core: ~258 µs
per KB plus ~0.65 ms per module (517 modules under 4 KB cost 338 ms).
Literal tables are stored uncompressed (OTP 28+), debug info is stripped
(0.1%), and removing the `Line` (3.48 s) or `Type`/`Meta` (3.60 s) chunks
changes nothing. The cost is the loader translating code.

## Ideas queue (ranked by expected gain on boot-to-IEx)

1. Interactive code loading instead of embedded preload (`-mode interactive`).
   Livebook preloads 3,132 modules (31.7 MB) before any app starts: ~6 s
   reading + ~8 s `prepare_loading` (single core) on the T113.
2. Profile-guided preload: preload only modules used during boot, lazy-load
   the rest.
3. Concurrent application start (`application:ensure_all_started/3` with
   `:concurrent`) instead of sequential `start_boot`.
4. Start IEx before slow/non-essential apps finish.
5. Rootfs format/compression: squashfs gzip/xz/lz4/zstd/none, EROFS lz4/lzma.
6. Smaller beams: strip more chunks, fewer apps/modules.
7. Kernel: LZ4 or uncompressed Image (0.69 s handoff today), skip FIT sha256.
8. Coldplug kernel modules from erlinit before the BEAM starts (overlap I/O
   with module loading). Mostly helps WiFi.
9. CPU at 1.2 GHz instead of 1008 MHz (needs hardware/voltage confirmation).
10. JIT branch (`origin/jit`): measure effect on load time.
