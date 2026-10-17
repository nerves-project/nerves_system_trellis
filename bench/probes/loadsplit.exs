# Decompose embedded-mode preload cost: cold read vs. prepare_loading.
ver = :init.script_id() |> elem(1) |> to_string()
boot = Path.wildcard("/srv/erlang/releases/#{ver}/*.boot") |> Enum.reject(&(&1 =~ ~r/start_clean/)) |> Enum.sort_by(&(&1 =~ ~r/shoehorn/), :desc) |> hd()
{:script, _, instrs} = :erlang.binary_to_term(File.read!(boot))
mods = for {:primLoad, ms} <- instrs, m <- ms, do: m
files = for m <- mods, f = :code.which(m), is_list(f), do: {m, f}
File.write!("/proc/sys/vm/drop_caches", "3")
{tread, bins} = :timer.tc(fn -> Enum.map(files, fn {m, f} -> {:ok, bin, _} = :erl_prim_loader.get_file(f); {m, bin} end) end)
bytes = bins |> Enum.map(&byte_size(elem(&1, 1))) |> Enum.sum()
{tread2, _} = :timer.tc(fn -> Enum.each(files, fn {_m, f} -> :erl_prim_loader.get_file(f) end) end)
{tprep, _} = :timer.tc(fn -> Enum.each(bins, fn {m, bin} -> :erlang.prepare_loading(m, bin) end) end)
{tprep2, _} = :timer.tc(fn ->
  bins |> Enum.chunk_every(div(length(bins), 2) + 1)
  |> Enum.map(fn c -> Task.async(fn -> Enum.each(c, fn {m, bin} -> :erlang.prepare_loading(m, bin) end) end) end)
  |> Enum.each(&Task.await(&1, :infinity))
end)
IO.puts("boot=#{boot} modules_in_script=#{length(mods)} found=#{length(files)} bytes=#{bytes}")
IO.puts("cold_read_ms=#{div(tread,1000)} warm_read_ms=#{div(tread2,1000)} prepare_1core_ms=#{div(tprep,1000)} prepare_2core_ms=#{div(tprep2,1000)}")
