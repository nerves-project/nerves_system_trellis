# Nerves boot-time findings (Trellis / Nerves Starter Kit, 2026-10-17)

Board: Allwinner T113-S4, 2× Cortex-A7 @ 1008 MHz, 256 MB, BEAM without JIT.
Soft reboots, 5 boots per variant, medians. "Uptime" = kernel clock.
Full log: `EXPERIMENTS.md`. Tooling: `README.md`, `boot_tools/README.md`.

## How to read this branch

`git log --reverse origin/main..` tells the story one commit at a time. The
branch is `main` + Frank's `erofs` commit (Nerves 2 + EROFS) + this work:

1. Tooling: harness (`bench/`), `boot_tools`, the template test app.
2. One commit per kept system change, each with its measured before/after:
   built-in jitterentropy, LZ4 kernel, header-sized FIT read, crc32 FIT
   hashes, erlinit seed save.
3. App-level patches: the nerves_livebook port, VintageNet WiFi knobs, the
   diagnostic U-Boot bootstage patch.
4. Results (raw per-boot data, bootcharts) and these notes.

Nothing outside this repo needs a branch: the erlinit change is a Buildroot
patch in `patches/erlinit/`, Livebook and VintageNet changes are patch files
under `bench/` with scripts that apply them, and Nerves (v2 branch) itself is
unchanged. `bench/README.md` has the commands to reproduce every number.

Assets too large to commit (the ~65 firmware images built during the
measurements, ~1.8 GB, plus build outputs) are with Jon and can be shared if
needed.

## Headline numbers (time to IEx prompt)

| app | before | after | change |
| --- | --- | --- | --- |
| nerves_livebook (124 apps), uptime: original firmware (Nerves 1, squashfs) | 18.16 s | **6.82 s** | −11.3 s |
| nerves_livebook, uptime: same app on Nerves 2 + this system, `-mode embedded` | 17.28 s | **6.82 s** | −10.5 s |
| `mix nerves.new` app (39 apps), uptime | 5.90 s | **3.89 s** | −2.0 s |
| `mix nerves.new` app, U-Boot banner → IEx | 7.43 s | **4.74 s** | −2.7 s |

Final configuration (all kept changes together), 5 boots: template app IEx
3.89 s (3.87–3.90), usb0 IPv4 4.31 s; Livebook IEx 6.82 s (6.36–6.91,
best run 6.60 s), usb0 IPv4 6.06 s. Livebook varies ±0.3 s run to run, so
Livebook deltas below ~0.3 s are noise; the template app varies ±0.05 s. A cold boot adds ~0.18 s of
BootROM + SPL before the U-Boot banner (soft reboots add 0.5 s of watchdog
delay instead).

Livebook's network comes up ~10 s sooner too (usb0 IPv4 16.4 → 6.3 s,
WiFi IPv4 23.2 → 13.2 s). No changes to Livebook's own code.

## What to adopt (general to Nerves)

1. **Don't use `-mode embedded` for big apps.** Livebook preloads 3,132
   modules (11.9 s) but uses ~700 by the time IEx starts. Interactive mode
   (OTP 26+ caches boot paths) saved 5.4 s on Livebook. On the small template
   app embedded mode is 2 s slower too. The trade-off: embedded mode finds a
   missing module at boot; interactive mode only when it's first called.
   The preload in (2) keeps a build-time list, so the release could also
   check that every listed module exists.
2. **Profile-guided background preload** (`boot_tools`, `BOOT_PRELOAD`):
   record the modules loaded at `iex.exs` time, then at boot load them with
   `code:ensure_modules_loaded/1` in chunks of 256 from a process started by
   the boot script (it waits for `code_server`). Uses the otherwise idle second
   core. Livebook 11.9 → 6.6 s; small app 5.9 → 4.1 s together with (3).
   Profiles must be captured before any ssh/eval session, or they pick up
   evaluator modules.
3. **Print the MOTD asynchronously** in `iex.exs`. The synchronous
   `NervesMOTD.print()` costs ~0.4 s before the prompt.
4. **Keep `runtime.exs` trivial.** Evaluating it loads Elixir's evaluator and
   compiler: 0.16 s on the small app, 1.4 s on Livebook.
5. **Kernel: look for built-in self-tests.** `CONFIG_CRYPTO_ECDH=y` pulled in
   a built-in jitterentropy RNG self-test (230 ms). Find such things for free
   with `initcall_debug` in U-Boot's `console_args`.
6. **Boot image:** LZ4 kernel (`BR2_LINUX_KERNEL_LZ4=y`; Buildroot overrides
   `CONFIG_KERNEL_*`) −0.16 s; read only the FIT's real size in U-Boot
   (`fdt header get ... totalsize`) −0.11 s; crc32 instead of sha256 FIT
   hashes −0.22 s. **Needs Frank's sign-off:** crc32 only detects corruption,
   so systems that sign FITs (or want tamper evidence) keep sha256.

7. **erlinit: write the next boot's RNG seed in parallel** (patch in
   `patches/erlinit/`): the seed write + fsync delayed the BEAM by ~80 ms.
   Loading/crediting the old seed stays before launch. IEx −0.11 s.
   **Needs Frank's review:** if power is lost before the new seed is written,
   the next boot has no creditable seed (the old one was already consumed).
8. **Optional: slim the first module group.** Removing `erl_parse`,
   `erl_lint`, `erl_eval` from the always-loaded first group
   (`BOOT_FIRST_DROP`) starts the boot script 126 ms earlier and IEx ~70 ms
   earlier on the small app (they load lazily later). Boots fine here; test
   per app.

## Tried, no help

- Exact boot paths (no failed lookups in embedded mode): ~0.07 s. Single-file
  module bundle: ~0.5 s ceiling, crashed; interactive mode beats both.
- Uncompressed EROFS: +0.2 s (more MMC reads than lz4hc decompression saves).
- Loading drivers before the BEAM (Frank's nerves_uevent idea): drivers load
  1.3 s earlier, IEx/WiFi gain ~0.1 s or less. VintageNet only starts
  configuring wlan0 at ~4.3 s, then scan + DHCP dominate; and on 2 busy
  cores, pre-BEAM driver loading competes with BEAM startup.
- nerves_uevent's coldplug: 398 uevents at boot, each its own port message
  and `PropertyTable.put`. Skipping the scan entirely (upper bound) saves
  ~0.12–0.17 s; modprobe children use 0.23 s of CPU. Batching the
  PropertyTable updates is the likely improvement. Also found a bug:
  `NervesUEvent.stats/0` recurses forever (should call
  `NervesUEvent.UEvent.stats/0`).
- Turning off toolchain hardening (PIE/SSP/RELRO): ≤0.15 s on the small app,
  nothing measurable on Livebook. Not worth the security trade-off.
- U-Boot without networking (`CONFIG_NO_NET`): −28 ms.
- Trimming built-ins from an already lean kernel (−180 KB): −16 ms.
- Deferring network apps until after IEx: helped before preload existed,
  not after (the MOTD waits on them).

## WiFi (measured, patched deps in `patches/`)

WiFi IPv4 on the template app: **10.41 s → 6.37 s (−4.0 s)**.

- udhcpc starts on association and its first DISCOVER goes out before the WPA
  4-way handshake completes, so it's lost and retried 3 s later. `udhcpc -T 1`
  (or starting DHCP on CTRL-EVENT-CONNECTED): −2.07 s.
- A full scan takes ~2 s before the first auth attempt. Restricting to the
  AP's channel (`scan_freq`): −1.98 s more. A fixed `scan_freq` is fragile;
  the real fix is "try the last-known channel first, then full scan".

## Open

- Reset → U-Boot banner is 0.69 s, but 0.5 s of that is the soft-reboot
  watchdog delay; BootROM + SPL (incl. DDR3 init) take only ~80 ms. U-Boot
  proper spends ~0.1 s initializing USB gadget Ethernet (RNDIS) and 72 ms in
  driver-model setup before reading the FIT (bootstage timeline in
  EXPERIMENTS.md).
- The first boot-script module group (262 ms) is half `erl_parse`/`erl_lint`/
  `erl_eval`, needed to parse `sys.config` before lazy loading works.
- JIT: not pursued. Boot time is favored over the JIT (JIT only for explicit
  cases); Frank's ARM32 JIT patch targets OTP 29.0.6 and doesn't apply to
  29.1.2 anyway, and boot is dominated by code loading.
