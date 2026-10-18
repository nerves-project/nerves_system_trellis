defmodule BootTools.Preload do
  @moduledoc """
  Boot script transform: start a background preload of a profiled module
  list (one module name per line) right after the boot script starts.
  The list is grouped by application in the boot script's start order
  (alphabetical within each application). That's an approximation of when
  modules are needed, not the order a previous boot actually loaded them.
  """

  def transform(instrs, release, list_file, chunk) do
    wanted =
      cond do
        String.starts_with?(list_file, "reach") ->
          depth = case String.split(list_file, ":") do [_, d] -> String.to_integer(d); _ -> 1000 end
          reachable(instrs, release, depth)

        list_file == "all" ->
        # Compile-time set: every module the boot script lists after the
        # always-loaded first group (what embedded mode would load).
        {_, after_first} = Enum.split_while(instrs, &(&1 != {:kernel_load_completed}))
        for({:primLoad, ms} <- after_first, m <- ms, do: m) |> MapSet.new()

        true ->
          list_file |> File.read!() |> String.split() |> Enum.map(&String.to_atom/1) |> MapSet.new()
      end

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

  # Compile-time set: modules reachable from each started application's
  # callback module, following module names found in each .beam's atom table
  # (which survives beam stripping), up to `depth` hops.
  defp reachable(instrs, release, depth) do
    apps = for {:apply, {:application, :start_boot, [a, _]}} <- instrs, do: a
    listed = for({:primLoad, ms} <- instrs, m <- ms, do: m) |> MapSet.new()

    beams =
      Path.wildcard(Path.join([release.path, "lib", "*", "ebin", "*.beam"])) ++
        Path.wildcard(Path.join([release.path, "releases", release.version, "consolidated", "*.beam"]))

    refs =
      for f <- beams, into: %{} do
        {:ok, {m, [atoms: atoms]}} = :beam_lib.chunks(String.to_charlist(f), [:atoms])
        {m, for({_, a} <- atoms, a != m, MapSet.member?(listed, a), do: a)}
      end

    roots =
      for a <- apps,
          props = release.applications[a],
          props != nil,
          {m, _} <- [Keyword.get(props, :mod, {nil, nil})],
          m != nil,
          do: m

    Enum.reduce_while(1..depth, {MapSet.new(roots), roots}, fn _, {set, frontier} ->
      new = frontier |> Enum.flat_map(&Map.get(refs, &1, [])) |> Enum.uniq() |> Enum.reject(&MapSet.member?(set, &1))
      if new == [], do: {:halt, {set, []}}, else: {:cont, {MapSet.union(set, MapSet.new(new)), new}}
    end)
    |> elem(0)
  end

  defp consolidated?(m, release) do
    File.exists?(Path.join([release.path, "releases", release.version, "consolidated", "#{m}.beam"]))
  end
end
