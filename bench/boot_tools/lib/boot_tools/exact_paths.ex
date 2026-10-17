defmodule BootTools.ExactPaths do
  @moduledoc """
  Boot script transform: make every embedded-mode module lookup hit on the
  first try.

  `erl_prim_loader` loads each module of a `primLoad` group by trying
  `<dir>/<Mod>.beam` for each dir of the current `{path, Dirs}` in order. Mix
  releases emit `[consolidated, app/ebin]` for every Elixir-dependent app, so
  each non-protocol module costs one failed open in `consolidated/` (~0.4 ms
  on a T113). Since the release layout is known at build time, split each group
  by the directory that actually holds each module.
  """

  def transform(instrs, release) do
    vars = %{"ROOT" => release.path, "RELEASE_LIB" => Path.join(release.path, "lib")}

    {out, _} =
      Enum.flat_map_reduce(instrs, [], fn
        {:path, dirs} = i, _ -> {[i], dirs}
        {:primLoad, mods}, dirs when length(dirs) > 1 -> {split(mods, dirs, vars) ++ [{:path, dirs}], dirs}
        i, dirs -> {[i], dirs}
      end)

    out
  end

  defp split(mods, dirs, vars) do
    host_dirs = Enum.map(dirs, &{&1, expand(&1, vars)})

    mods
    |> Enum.map(fn m ->
      {dir, _} =
        Enum.find(host_dirs, fn {_, hd} -> File.exists?(Path.join(hd, "#{m}.beam")) end) ||
          raise "#{m}.beam not found in #{inspect(dirs)}"

      {dir, m}
    end)
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.flat_map(fn [{dir, _} | _] = chunk -> [{:path, [dir]}, {:primLoad, Enum.map(chunk, &elem(&1, 1))}] end)
  end

  defp expand(dir, vars) do
    dir = to_string(dir)

    case Regex.run(~r{^\$(\w+)/(.*)$}, dir) do
      [_, var, rest] -> Path.join(Map.fetch!(vars, var), rest) |> Path.expand()
      _ -> dir
    end
  end
end
