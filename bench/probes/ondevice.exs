# Collect on-device boot timing facts. Run via: ssh nerves@host < ondevice.exs
hz = 100
read = fn p -> File.read!(p) end
up = read.("/proc/uptime") |> String.split() |> hd() |> String.to_float()
starttime = fn pid ->
  case File.read("/proc/#{pid}/stat") do
    {:ok, s} -> [_, rest] = String.split(s, ") ", parts: 2); rest |> String.split() |> Enum.at(19) |> String.to_integer() |> Kernel./(hz)
    _ -> nil
  end
end
procs =
  File.ls!("/proc") |> Enum.filter(&(&1 =~ ~r/^\d+$/))
  |> Enum.map(fn pid -> {String.to_integer(pid), starttime.(pid), (File.read("/proc/#{pid}/cmdline") |> elem(1) |> to_string() |> String.replace(<<0>>, " ") |> String.slice(0, 100))} end)
  |> Enum.filter(fn {_, t, c} -> t && c != "" end) |> Enum.sort_by(&elem(&1, 1))
IO.puts("uptime #{up}")
for {pid, t, c} <- procs, do: IO.puts("proc #{t} #{pid} #{c}")
{dmesg, _} = System.cmd("dmesg", [])
IO.puts(dmesg)
