# Arm hibernation on a raw swap partition: the inactive firmware slot
# (mmcblk0p3 while running from p2). Destroys that slot's rootfs; the next
# firmware update rewrites it. mkswap every time, which also invalidates any
# image left from a boot that didn't resume (resuming a stale image after
# /root was mounted corrupts it). Run after every boot.
dev = "/dev/mmcblk0p3"
true = String.contains?(File.read!("/proc/cmdline"), "root=/dev/mmcblk0p2")
System.cmd("swapoff", [dev], stderr_to_stdout: true)
{_, 0} = System.cmd("mkswap", [dev], stderr_to_stdout: true)
{_, 0} = System.cmd("swapon", [dev], stderr_to_stdout: true)
File.write!("/sys/power/resume", File.read!("/sys/class/block/mmcblk0p3/dev") |> String.trim())
File.write!("/sys/power/resume_offset", "0")
if size = System.get_env("HIB_IMAGE_SIZE"), do: File.write!("/sys/power/image_size", size)
if System.get_env("HIB_CONSOLE"), do: File.write!("/sys/module/printk/parameters/console_suspend", "N")
if File.exists?("/sys/power/pm_debug_messages"), do: File.write!("/sys/power/pm_debug_messages", "1")
args = Nerves.Runtime.KV.get("console_args")
base = args |> String.split() |> Enum.reject(&String.starts_with?(&1, ["resume", "hibernate", "no_console_suspend", "loglevel", "pm_debug_messages", "initcall_debug"])) |> Enum.join(" ")
Nerves.Runtime.KV.put("console_args", base <> " resume=#{dev} resumewait hibernate.compressor=lz4" <> System.get_env("HIB_EXTRA_ARGS", ""))
IO.puts("armed: #{File.read!("/proc/swaps") |> String.split("\n") |> Enum.at(1)}")
