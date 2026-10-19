# Where does prepare_loading's CPU go? Prepare every .beam in the release on
# one core, as shipped and with optional chunks removed, plus a per-size and
# per-chunk breakdown. Run via: ssh nerves@host < prepcost.exs
root = :code.root_dir() |> to_string()
files = Path.wildcard(root <> "/lib/*/ebin/*.beam") ++ Path.wildcard(root <> "/releases/*/consolidated/*.beam")
bins = for f <- files, do: {f |> Path.basename(".beam") |> String.to_atom(), File.read!(f)}
bytes = bins |> Enum.map(&byte_size(elem(&1, 1))) |> Enum.sum()

strip = fn bin, drop ->
  {:ok, m, chunks} = :beam_lib.all_chunks(bin)
  {:ok, out} = :beam_lib.build_module(for {id, b} <- chunks, id not in drop, do: {id, b})
  _ = m
  out
end

prep = fn set ->
  {us, _} = :timer.tc(fn -> Enum.each(set, fn {m, b} -> :erlang.prepare_loading(m, b) end) end)
  div(us, 1000)
end

# Warm up (first touch of each binary, caches)
_ = prep.(bins)
base = prep.(bins)
no_line = bins |> Enum.map(fn {m, b} -> {m, strip.(b, [~c"Line"])} end)
no_type = bins |> Enum.map(fn {m, b} -> {m, strip.(b, [~c"Type", ~c"Meta"])} end)
IO.puts("files=#{length(bins)} bytes=#{bytes}")
IO.puts("prepare_ms as_shipped=#{base} no_Line=#{prep.(no_line)} no_Type_Meta=#{prep.(no_type)}")

# Cost per module vs size: top 10 by time
per =
  for {m, b} <- bins do
    {us, _} = :timer.tc(fn -> :erlang.prepare_loading(m, b) end)
    {us, byte_size(b), m}
  end

total_us = per |> Enum.map(&elem(&1, 0)) |> Enum.sum()
IO.puts("sum_us=#{total_us} us_per_kb=#{Float.round(total_us / (bytes / 1024), 1)}")
small = per |> Enum.filter(&(elem(&1, 1) < 4096))
IO.puts("modules<4KB: #{length(small)} files, #{small |> Enum.map(&elem(&1, 0)) |> Enum.sum() |> div(1000)} ms")
for {us, sz, m} <- per |> Enum.sort(:desc) |> Enum.take(10), do: IO.puts("  #{div(us, 1000)} ms #{div(sz, 1024)} KB #{m}")
