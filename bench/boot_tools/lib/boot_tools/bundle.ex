defmodule BootTools.Bundle do
  @moduledoc """
  Boot script transform: put every module that the boot script would load
  after `kernel_load_completed` into one `boot.bundle` file and load it with
  `:boot_bundle.load/1` right before the first such `primLoad`.
  """

  @target_root "/srv/erlang"

  def transform(instrs, release) do
    vars = %{"ROOT" => release.path, "RELEASE_LIB" => Path.join(release.path, "lib")}
    {before, [klc | rest]} = Enum.split_while(instrs, &(&1 != {:kernel_load_completed}))

    {entries, _} =
      Enum.flat_map_reduce(rest, [], fn
        {:path, dirs}, _ -> {[], dirs}
        {:primLoad, mods}, dirs -> {Enum.map(mods, &locate(&1, dirs, vars, release)), dirs}
        _, dirs -> {[], dirs}
      end)

    rel_dir = Path.join([release.path, "releases", release.version])
    bundle = Path.join(rel_dir, "boot.bundle")
    File.write!(bundle, :erlang.term_to_binary(entries))
    Mix.shell().info("* boot bundle: #{length(entries)} modules, #{File.stat!(bundle).size} bytes")

    target = Path.join([@target_root, "releases", release.version, "boot.bundle"])
    # The bundle loader itself must be in the first (always loaded) group.
    before =
      Enum.map(before, fn
        {:path, p} -> {:path, [~c"$ROOT/lib/boot_trace/ebin" | p]}
        i -> i
      end)

    [first_load | _] = Enum.filter(before, &match?({:primLoad, _}, &1))
    before = List.replace_at(before, Enum.find_index(before, &(&1 == first_load)), {:primLoad, [:boot_bundle | elem(first_load, 1)]})
    before ++ [klc, {:apply, {:boot_bundle, :load, [String.to_charlist(target)]}} | rest]
  end

  defp locate(m, dirs, vars, release) do
    hit =
      Enum.find_value(dirs, fn d ->
        host = expand(d, vars)
        f = Path.join(host, "#{m}.beam")
        File.exists?(f) && {host, f}
      end) || raise "#{m}.beam not found"

    {host_dir, file} = hit
    target_full = String.replace_prefix(Path.join(host_dir, "#{m}.beam"), release.path, @target_root)
    {m, String.to_charlist(target_full), File.read!(file)}
  end

  defp expand(dir, vars) do
    case Regex.run(~r{^\$(\w+)/(.*)$}, to_string(dir)) do
      [_, var, rest] -> Path.join(Map.fetch!(vars, var), rest) |> Path.expand()
      _ -> to_string(dir)
    end
  end
end
