# Boot-time bench (Trellis / Nerves Starter Kit)

Closed-loop tooling used to measure and reduce Nerves boot time on a Trellis
board connected over USB-C (serial console on the WCH adapter, USB gadget
Ethernet) and WiFi. Start with `FINDINGS.md` (results and where each change
lives), then `EXPERIMENTS.md` (the full lab notebook, including what didn't
work).

## Layout

| path | what |
| --- | --- |
| `bootcap.py` | Serial capture with host timestamps (U-Boot banner, "Starting kernel", IEx prompt, restart) and a serial `serial_eval` helper. Reboots go over the console. |
| `measure.py LABEL -n N` | N reboots → `results/results.jsonl` + per-run serial log and device report in `results/runs/`. `--summary` prints medians. |
| `variant.sh LABEL N -- ENV=…` | Build the app with build-time switches, flash over ssh (fwup), check the running firmware UUID, then run `measure.py` and `bootchart.py`. `BENCH_APP=nerves_livebook` selects Livebook. |
| `bootchart.py --latest LABEL` | HTML bootchart for one run (kernel clock; U-Boot/handoff, kernel, erlinit, boot-script steps, app starts, events). |
| `profile.sh LABEL NAME` | Save the module set loaded at `iex.exs` time from a run's report as `profiles/NAME.mods` (a preload profile). |
| `boot_tools/` | Elixir library + Nerves 2 build-action step: boot-script tracing, profile-guided preload, deferred app start, first-group slimming, exact paths, bundle, on-device report. See `boot_tools/README.md`. |
| `boot_bench/` | The `mix nerves.new` template app ported to Nerves 2, with `boot_tools` and build-time switches (`BOOT_MODE`, `BOOT_MOTD`, `BOOT_NO_RUNTIME_CONFIG`, `BOOT_LOAD_ONLY`, `BOOT_ROOTFS`, `BOOT_EARLY_COLDPLUG`, `BOOT_DIAG`, …). |
| `livebook/` | Patch porting nerves_livebook (commit 7e11b91) to Nerves 2 + this system + `boot_tools`; `livebook/setup.sh` clones and applies it. |
| `patches/` | VintageNet WiFi experiment knobs (`apply_dep_patches.sh`) and the diagnostic U-Boot bootstage patch. |
| `write_uboot.sh` | Write a `u-boot-sunxi-with-spl.bin` to the board (fwup upgrades never rewrite U-Boot). Backs up the original once. |
| `diaglog.sh`, `logmap.py` | Fetch a `BOOT_DIAG=1` build's debug log (monotonic timestamps) mapped onto uptime. |
| `probes/` | One-off on-device probes from the first investigation (module read vs. prepare cost, path-search misses). |
| `results/` | Raw data: `results.jsonl` (one record per boot), per-run serial logs + reports, bootcharts, diag logs. Firmware images aren't committed. |

## Quick start

```sh
# Host: OTP 29.1.2 + Elixir 1.20.4 (bench/mise.toml), nerves_bootstrap,
# fwup, mkfs.erofs (erofs-utils), Docker for the system build.
python3 -m venv .venv && .venv/bin/pip install pyserial
export BENCH_PY=$PWD/.venv/bin/python
export BENCH_TTY=/dev/cu.wchusbserial1110            # serial console
export BENCH_KEY=~/.ssh/id_ed25519                    # key in authorized_keys

# Build the system from this branch once (from boot_bench):
(cd boot_bench && mix deps.get && ../apply_dep_patches.sh \
  && MIX_TARGET=trellis mix nerves.artifact.build nerves_system_trellis)

# Current best template-app configuration, 5 boots:
./variant.sh best 5 -- BOOT_PRELOAD=$PWD/profiles/boot_bench-v4.mods \
  BOOT_NO_RUNTIME_CONFIG=1 BOOT_MOTD=async BOOT_FIRST_DROP=erl_lint,erl_eval,erl_parse

# Livebook:
livebook/setup.sh
BENCH_APP=nerves_livebook ./variant.sh lb 5 -- BOOT_MODE=interactive \
  BOOT_PRELOAD=$PWD/profiles/livebook.mods BOOT_MOTD=async
```

The scripts default to the board's mDNS name (`nerves-0123b817bd12a177ee`);
set `BENCH_HOST` for another board. Firmware is flashed over ssh; reboots and
reports use the serial console, so measurements keep working if the network
drops.

## Metrics (seconds)

| key | meaning |
| --- | --- |
| `pre_uboot_s` | restart message → U-Boot banner (includes 0.5 s watchdog on soft reboot) |
| `uboot_s` | U-Boot banner → "Starting kernel" |
| `kernel_t0` | U-Boot banner → kernel clock zero (includes kernel decompression) |
| `init_k` / `beam_k` | uptime when erlinit / `beam.smp` start |
| `script_start_k` / `script_done_k` | boot script start / all apps started |
| `apps_k` | all OTP apps started (including any deferred ones) |
| `iex_k` | uptime when the IEx prompt reaches the console |
| `iex_total` | U-Boot banner → IEx prompt |
| `lan_<if>_k`, `ip_<if>_k`, `inet_<if>_k` | first `:lan`, first IPv4 address, first `:internet` per interface |

Soft reboots skip power-on; a cold boot adds ~0.18 s of BootROM + SPL before
the banner instead of the 0.5 s watchdog delay.
