defmodule BootTools.Step do
  @moduledoc """
  Mix release step that instruments the release boot script with
  `:boot_trace.mark/1` calls around every instruction.

  Add it after `:assemble` in the release steps.
  """

  def run(%Mix.Release{} = release) do
    rel_dir = Path.join([release.path, "releases", release.version])

    if System.get_env("BOOT_EXACT_PATHS") == "1" do
      rewrite!(Path.join(rel_dir, "start.boot"), &BootTools.ExactPaths.transform(&1, release))
      Mix.shell().info("* exact boot paths applied")
    end

    if System.get_env("BOOT_BUNDLE") == "1" do
      rewrite!(Path.join(rel_dir, "start.boot"), &BootTools.Bundle.transform(&1, release))
    end

    if defer = System.get_env("BOOT_DEFER") do
      seeds = defer |> String.split(",", trim: true) |> Enum.map(&String.to_atom/1)
      rewrite!(Path.join(rel_dir, "start.boot"), &BootTools.Defer.transform(&1, release, seeds))
    end

    if System.get_env("BOOT_PROC_SNAPSHOT") == "1" do
      rewrite!(Path.join(rel_dir, "start.boot"), fn instrs ->
        {a, b} = Enum.split_while(instrs, &(&1 != {:progress, :started}))
        a ++ [{:apply, {:boot_trace, :proc_snapshot, []}} | b]
      end)
    end

    if drop = System.get_env("BOOT_FIRST_DROP") do
      mods = drop |> String.split(",", trim: true) |> Enum.map(&String.to_atom/1)
      rewrite!(Path.join(rel_dir, "start.boot"), &drop_from_first_group(&1, mods))
      Mix.shell().info("* dropped from the first primLoad group: #{inspect(mods)}")
    end

    if list = System.get_env("BOOT_PRELOAD") do
      chunk = String.to_integer(System.get_env("BOOT_PRELOAD_CHUNK", "256"))
      rewrite!(Path.join(rel_dir, "start.boot"), &BootTools.Preload.transform(&1, release, list, chunk))
    end

    if true do
      copy_beam!(release)
    end

    if System.get_env("BOOT_TRACE", "1") == "1" do
      mod_app =
        for {app, props} <- release.applications, m <- Keyword.get(props, :modules, []), into: %{},
          do: {m, app}

      for boot <- ["start.boot"], path = Path.join(rel_dir, boot), File.exists?(path) do
        instrument_file!(path, mod_app)
      end
    end

    release
  end

  defp copy_beam!(release) do
    dest_dir = Path.join([release.path, "lib", "boot_trace", "ebin"])
    File.mkdir_p!(dest_dir)

    for m <- [:boot_trace, :boot_bundle, :boot_defer, :boot_preload] do
      {:module, _} = Code.ensure_loaded(m)
      File.cp!(:code.which(m), Path.join(dest_dir, "#{m}.beam"))
    end
  end

  defp instrument_file!(path, mod_app) do
    rewrite!(path, &instrument(&1, mod_app))
    Mix.shell().info("* boot_trace instrumented #{path}")
  end

  # Remove modules from the always-loaded first primLoad group(s) (before
  # kernel_load_completed). In interactive mode they're then loaded lazily.
  defp drop_from_first_group(instrs, mods) do
    {pre, post} = Enum.split_while(instrs, &(&1 != {:kernel_load_completed}))

    pre =
      Enum.map(pre, fn
        {:primLoad, ms} -> {:primLoad, ms -- mods}
        i -> i
      end)

    pre ++ post
  end

  defp rewrite!(path, fun) do
    {:script, id, instrs} = path |> File.read!() |> :erlang.binary_to_term()
    File.write!(path, :erlang.term_to_binary({:script, id, fun.(instrs)}))
  end

  defp instrument(instrs, mod_app) do
    # Load boot_trace with the first path/primLoad, then start it.
    {pre, rest} = Enum.split_while(instrs, &(not match?({:primLoad, _}, &1)))
    [{:primLoad, first} | rest] = rest

    pre =
      Enum.map(pre, fn
        {:path, p} -> {:path, [~c"$ROOT/lib/boot_trace/ebin" | p]}
        other -> other
      end)

    groups = Enum.map(rest, &wrap(&1, mod_app))

    pre ++
      [
        {:primLoad, [:boot_trace, :boot_defer, :boot_preload | first]},
        {:apply, {:boot_trace, :start, []}},
        {:apply, {:boot_trace, :mark, [{:primLoad, :first, length(first)}]}}
      ] ++ List.flatten(groups) ++ [{:apply, {:boot_trace, :mark, [:script_done]}}]
  end

  defp wrap({:path, _} = i, _), do: [i]
  defp wrap(i, mod_app), do: [{:apply, {:boot_trace, :mark, [label(i, mod_app)]}}, i]

  defp label({:primLoad, [m | _] = mods}, mod_app), do: {:primLoad, Map.get(mod_app, m, :unknown), length(mods)}
  defp label({:primLoad, []}, _), do: {:primLoad, :none, 0}
  defp label({:kernelProcess, name, _}, _), do: {:kernelProcess, name}
  defp label({:apply, {:application, f, [app | _]}}, _) when is_atom(app), do: {f, app}
  defp label({:apply, {:application, f, [{:application, app, _} | _]}}, _), do: {f, app}
  defp label({:apply, {m, f, _}}, _), do: {:apply, m, f}
  defp label({:progress, p}, _), do: {:progress, p}
  defp label({:kernel_load_completed}, _), do: :kernel_load_completed
  defp label(other, _), do: {:other, elem(other, 0)}

end
