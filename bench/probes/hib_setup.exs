# One-time setup for hibernation experiments: a swap file on /root, its
# page offset on the partition (found by scanning the raw partition for a
# random marker, since there's no filefrag), swapon, and resume= on the
# kernel command line via U-Boot's console_args.
# Run via: ssh nerves@host < hib_setup.exs
swap = "/root/swapfile"
dev = "/dev/mmcblk0p4"
mb = 96
System.cmd("swapoff", [swap], stderr_to_stdout: true)
File.rm(swap)
marker = :crypto.strong_rand_bytes(32)
{:ok, f} = :file.open(swap, [:write, :raw, :binary])
:ok = :file.write(f, marker <> :binary.copy(<<0>>, 1024 * 1024 - 32))
zeros = :binary.copy(<<0>>, 1024 * 1024)
for _ <- 2..mb, do: :ok = :file.write(f, zeros)
:ok = :file.sync(f)
:ok = :file.close(f)
File.chmod!(swap, 0o600)

{:ok, d} = :file.open(dev, [:read, :raw, :binary])
find = fn find, pos ->
  case :file.pread(d, pos, 4 * 1024 * 1024) do
    {:ok, chunk} ->
      case :binary.match(chunk, marker) do
        {i, _} -> pos + i
        :nomatch -> find.(find, pos + byte_size(chunk))
      end
    _ -> nil
  end
end
byte_off = find.(find, 0)
:file.close(d)
IO.puts("marker at byte #{inspect(byte_off)} (page aligned: #{rem(byte_off || 1, 4096) == 0})")
page = div(byte_off, 4096)

IO.puts(elem(System.cmd("mkswap", [swap], stderr_to_stdout: true), 0))
IO.puts(elem(System.cmd("swapon", [swap], stderr_to_stdout: true), 0))
IO.puts(File.read!("/proc/swaps"))
[maj, min] = File.read!("/sys/class/block/mmcblk0p4/dev") |> String.trim() |> String.split(":")
File.write!("/sys/power/resume_offset", Integer.to_string(page))
File.write!("/sys/power/resume", "#{maj}:#{min}")
IO.puts("resume=#{File.read!("/sys/power/resume") |> String.trim()} offset=#{File.read!("/sys/power/resume_offset") |> String.trim()}")

args = Nerves.Runtime.KV.get("console_args")
base = args |> String.split() |> Enum.reject(&String.starts_with?(&1, ["resume", "hibernate"])) |> Enum.join(" ")
new = base <> " resume=#{dev} resume_offset=#{page} resumewait hibernate.compressor=lz4"
Nerves.Runtime.KV.put("console_args", new)
IO.puts("console_args: #{Nerves.Runtime.KV.get("console_args")}")
IO.puts("disk modes: #{File.read!("/sys/power/disk") |> String.trim()}")
