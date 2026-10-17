defmodule BootTools.Preload do
  @moduledoc """
  Boot script transform: start a background preload of a profiled module
  list (one module name per line) right after the boot script starts.
  Modules are ordered by their application's position in the boot script.
  """

  def transform(instrs, release, list_file, chunk) do
    wanted = list_file |> File.read!() |> String.split() |> Enum.map(&String.to_atom/1) |> MapSet.new()

    app_order =
      for {:apply, {:application, :start_boot, [app, _]}} <- instrs, do: app

    app_index = app_order |> Enum.with_index() |> Map.new()

    mods =
      for {app, props} <- release.applications,
          m <- Keyword.get(props, :modules, []),
          MapSet.member?(wanted, m),
          do: {Map.get(app_index, app, 999), m}

    mods = mods |> Enum.sort() |> Enum.map(&elem(&1, 1))
    # Consolidated protocols aren't in any app's module list; add them as-is.
    in_apps = MapSet.new(mods)
    extra = wanted |> Enum.reject(&MapSet.member?(in_apps, &1)) |> Enum.filter(&consolidated?(&1, release))
    mods = mods ++ extra
    Mix.shell().info("* preload #{length(mods)} modules in chunks of #{chunk}")

    {a, b} = Enum.split_while(instrs, &(&1 != {:progress, :kernel_load_completed}))
    a ++ [hd(b), {:apply, {:boot_preload, :start, [mods, chunk]}} | tl(b)]
  end

  defp consolidated?(m, release) do
    File.exists?(Path.join([release.path, "releases", release.version, "consolidated", "#{m}.beam"]))
  end
end
