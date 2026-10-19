# Re-arm the hibernation swap file made by hib_setup.exs (run after every
# boot). /root has 1 KB ext4 blocks, so the swap file starts 1 KB into a
# 4 KB page and the kernel's first swap page (where it looks for the swap
# signature and writes its hibernation header) is the next aligned page.
# mkswap puts the signature in the file's first page instead, so write it
# into the aligned page too. Hibernation overwrites the file's own header,
# hence mkswap every time.
swap = "/root/swapfile"
page = 9729
System.cmd("swapoff", [swap], stderr_to_stdout: true)
{_, 0} = System.cmd("mkswap", [swap], stderr_to_stdout: true)
{:ok, d} = :file.open("/dev/mmcblk0p4", [:read, :write, :raw, :binary])
:ok = :file.pwrite(d, page * 4096 + 4086, "SWAPSPACE2")
:ok = :file.sync(d)
:file.close(d)
{_, 0} = System.cmd("swapon", [swap], stderr_to_stdout: true)
File.write!("/sys/power/resume_offset", Integer.to_string(page))
# HIB_IMAGE_SIZE: target image size in bytes (0 = as small as possible:
# the kernel drops page cache before saving). Default: the kernel's 2/5 of RAM.
if size = System.get_env("HIB_IMAGE_SIZE"), do: File.write!("/sys/power/image_size", size)
File.write!("/sys/power/resume", File.read!("/sys/class/block/mmcblk0p4/dev") |> String.trim())
# Keep the console on through suspend/resume so the serial log shows progress.
File.write!("/sys/module/printk/parameters/console_suspend", "N")
if File.exists?("/sys/power/pm_debug_messages"), do: File.write!("/sys/power/pm_debug_messages", "1")
args = Nerves.Runtime.KV.get("console_args")
base = args |> String.split() |> Enum.reject(&String.starts_with?(&1, ["resume", "hibernate", "no_console_suspend", "loglevel", "pm_debug_messages", "initcall_debug"])) |> Enum.join(" ")
Nerves.Runtime.KV.put("console_args", base <> " resume=/dev/mmcblk0p4 resume_offset=#{page} resumewait hibernate.compressor=lz4 no_console_suspend" <> System.get_env("HIB_EXTRA_ARGS", ""))
IO.puts("armed: #{File.read!("/proc/swaps") |> String.split("\n") |> Enum.at(1)}")
