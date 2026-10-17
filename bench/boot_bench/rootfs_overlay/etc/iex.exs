:boot_trace.mark(:iex_exs)

# Boot-time experiment: the MOTD costs ~0.4 s before the prompt on a T113.
# :sync (template default), :async (print just after the prompt) or :off.
case Application.get_env(:boot_bench, :motd, :sync) do
  :sync -> NervesMOTD.print()
  :async -> spawn(fn -> NervesMOTD.print() end)
  :off -> :ok
end

# Add Toolshed helpers to the IEx session (BOOT_TOOLSHED=0 skips it)
if Application.get_env(:boot_bench, :toolshed, true), do: use(Toolshed)
