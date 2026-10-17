defmodule BootTools.Defer do
  @moduledoc """
  Boot script transform: move `application:start_boot/2` of the given apps
  (and every app that depends on them) to a background process started at the
  end of the boot script.
  """

  def transform(instrs, release, seeds) do
    deferred = closure(MapSet.new(seeds), release)

    {kept, moved} =
      Enum.reduce(instrs, {[], []}, fn
        {:apply, {:application, :start_boot, [app, type]}} = i, {k, m} ->
          if app in deferred, do: {k, [{app, type} | m]}, else: {[i | k], m}

        i, {k, m} ->
          {[i | k], m}
      end)

    moved = Enum.reverse(moved)
    Mix.shell().info("* deferring #{inspect(Enum.map(moved, &elem(&1, 0)))}")
    # Insert just before the final {progress, started}
    {before, after_} = Enum.split_while(Enum.reverse(kept), &(&1 != {:progress, :started}))
    before ++ [{:apply, {:boot_defer, :start, [moved, String.to_atom(System.get_env("BOOT_DEFER_PRIO", "normal"))]}} | after_]
  end

  defp closure(set, release) do
    more =
      for {app, props} <- release.applications,
          not MapSet.member?(set, app),
          Enum.any?(Keyword.get(props, :applications, []), &MapSet.member?(set, &1)),
          into: MapSet.new(),
          do: app

    if MapSet.size(more) == 0, do: set, else: closure(MapSet.union(set, more), release)
  end
end
