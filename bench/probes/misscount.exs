ver = :init.script_id() |> elem(1) |> to_string()
boot = Path.wildcard("/srv/erlang/releases/#{ver}/*.boot") |> Enum.reject(&(&1 =~ ~r/start_clean/)) |> Enum.sort_by(&(&1 =~ ~r/shoehorn/), :desc) |> hd()
{:script, _, instrs} = :erlang.binary_to_term(File.read!(boot))
root = to_string(:code.root_dir())
{_, misses, hits, npaths} =
  Enum.reduce(instrs, {[], 0, 0, []}, fn
    {:path, ps}, {_, m, h, np} -> ps = Enum.map(ps, &String.replace(to_string(&1), "$ROOT", root)); {ps, m, h, [length(ps) | np]}
    {:primLoad, mods}, {ps, m, h, np} ->
      {m2, h2} = Enum.reduce(mods, {m, h}, fn mod, {m, h} ->
        idx = Enum.find_index(ps, fn d -> File.exists?(Path.join(d, "#{mod}.beam")) end)
        if idx, do: {m + idx, h + 1}, else: {m + length(ps), h}
      end)
      {ps, m2, h2, np}
    _, acc -> acc
  end)
IO.puts("path instrs=#{inspect(Enum.reverse(npaths))} modules=#{hits} failed_opens=#{misses}")
# cost of a failed open
dirs = :code.get_path() |> Enum.take(100)
{us, _} = :timer.tc(fn -> for _ <- 1..10, d <- dirs, do: :prim_file.read_file(:filename.join(d, ~c"nonexistent_mod.beam")) end)
IO.puts("failed open cost: #{Float.round(us / (10 * length(dirs)), 1)} us each")
