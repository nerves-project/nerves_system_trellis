# BootTools

Boot-time instrumentation and boot-script experiments for Nerves 2 releases.

Add as a dependency and register the build action in the app's `mix.exs`
(build plans are created before the project compiles, so the action module
has to live in `mix.exs`):

```elixir
defmodule MyApp.BootAction do
  def pre_download(plan, _), do: plan
  def post_extract(plan, _), do: plan
  def pre_assemble_steps(_, release, _), do: release
  def post_assemble_steps(_, release, _), do: apply(BootTools.Step, :run, [release])
  def rootfs_creation_steps(_, release, _), do: release
  def pre_image_creation(_, _), do: :ok
  def image_creation(_, _), do: :ok
  def post_image_creation(_, _), do: :ok
end
# project: nerves: [actions: [MyApp.BootAction]]
```

Build-time switches (environment variables):

| variable | effect |
| --- | --- |
| `BOOT_TRACE=0` | don't instrument the boot script (default on) |
| `BOOT_PRELOAD=<file>` | background-preload the listed modules (one per line) with `code:ensure_modules_loaded/1` |
| `BOOT_PRELOAD=all` | same, but with every module the boot script lists (compile-time set, no profile) |
| `BOOT_PRELOAD=reach[:depth]` | same, with modules reachable from each started app's callback module via .beam atom tables (compile-time set) |
| `BOOT_PRELOAD_CHUNK=256` | preload chunk size (default 256; best on Livebook and boot_bench) |
| `BOOT_DEFER=app1,app2` | start these apps (and dependents) in the background after the boot script |
| `BOOT_DEFER_PRIO=low` | priority of the deferred starter |
| `BOOT_FIRST_DROP=erl_parse,erl_lint,erl_eval` | drop modules from the always-loaded first boot group (they load lazily later) |
| `BOOT_EXACT_PATHS=1` | embedded mode: one boot path per module group (no lookup misses) |
| `BOOT_BUNDLE=1` | embedded mode: load modules from a single bundle file (experimental) |

On the device, `BootTools.Report.json()` prints boot-script marks, process
start times, dmesg, VintageNet events, microstate accounting and the module set
loaded at `iex.exs` time (a preload profile). Mark `iex.exs` with
`:boot_trace.mark(:iex_exs)`.
