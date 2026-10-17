import Config

# Use shoehorn to start the main application. See the shoehorn
# library documentation for more control in ordering how OTP
# applications are started and handling failures.

config :nerves, application_sort: [init: [:nerves_runtime, :nerves_pack]]

# Enable the system startup guard to check that all OTP applications
# started. If they didn't and you're on a Nerves system that supports
# test runs of new firmware, the firmware will automatically roll
# back to the previous version. Delete this if implementing your own
# way of validating that firmware is good.
config :nerves_runtime, startup_guard_enabled: true

# Erlinit can be configured without a rootfs_overlay. See
# https://github.com/nerves-project/erlinit/ for more information on
# configuring erlinit.

# Advance the system clock on devices without a real-time clock.
config :nerves, :erlinit, update_clock: true

# Default to not starting so that the console logger isn't started. See
# runtime.exs for logger configuration.
config :logger, :default_handler, false

# Configure the device for SSH IEx prompt access and firmware updates
#
# * See https://nerves-ssh.hexdocs.pm/readme.html for general SSH configuration
# * See https://ssh-subsystem-fwup.hexdocs.pm/readme.html for firmware updates

keys =
  System.user_home!()
  |> Path.join(".ssh/id_{rsa,ecdsa,ed25519,claude}.pub")
  |> Path.wildcard()

if keys == [],
  do:
    Mix.raise("""
    No SSH public keys found in ~/.ssh. An ssh authorized key is needed to
    log into the Nerves device and update firmware on it using ssh.
    See your project's config.exs for this error message.
    """)

config :nerves_ssh,
  authorized_keys: Enum.map(keys, &File.read!/1)

# Configure the network using vintage_net
#
# Update regulatory_domain to your 2-letter country code E.g., "US"
#
# See https://github.com/nerves-networking/vintage_net for more information
config :vintage_net,
  regulatory_domain: "00",
  config: [
    {"usb0", %{type: VintageNetDirect}},
  ] ++
    if(System.get_env("BOOT_NO_ETH0") == "1",
      do: [],
      else: [{"eth0", %{type: VintageNetEthernet, ipv4: %{method: :dhcp}}}]
    ) ++ [
    {"wlan0", %{type: VintageNetWiFi}}
  ]

config :mdns_lite,
  # The `hosts` key specifies what hostnames mdns_lite advertises.  `:hostname`
  # advertises the device's hostname.local. For the official Nerves systems, this
  # is "nerves-<4 digit serial#>.local".  The `"nerves"` host causes mdns_lite
  # to advertise "nerves.local" for convenience. If more than one Nerves device
  # is on the network, it is recommended to delete "nerves" from the list
  # because otherwise any of the devices may respond to nerves.local leading to
  # unpredictable behavior.

  hosts: [:hostname, "nerves"],
  ttl: 120,

  # Advertise the following services over mDNS.
  services: [
    %{
      protocol: "ssh",
      transport: "tcp",
      port: 22
    },
    %{
      protocol: "sftp-ssh",
      transport: "tcp",
      port: 22
    },
    %{
      protocol: "epmd",
      transport: "tcp",
      port: 4369
    }
  ]

# Import target specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
# Uncomment to use target specific configurations

# import_config "#{Mix.target()}.exs"

# Diagnostic builds: keep debug logs (RingLogger) to trace network bring-up.
if System.get_env("BOOT_DIAG") == "1" do
  config :logger, level: :debug

  config :logger, :default_handler,
    config: [file: ~c"/tmp/boot.log"],
    formatter: Logger.Formatter.new(format: {BootTools.LogFormat, :format})
end

# Diagnostic: erlinit prints timestamped steps on the console.
if System.get_env("BOOT_ERLINIT_VERBOSE") == "1" do
  config :nerves, :erlinit, verbose: true
end

# Experiment: rootfs format/compression override, e.g. BOOT_ROOTFS=erofs-none
case System.get_env("BOOT_ROOTFS") do
  "erofs-none" -> config :nerves, :firmware, rootfs_type: {:erofs, ["-b", "4096", "-T", "0", "-U", "clear"]}
  "erofs-lz4" -> config :nerves, :firmware, rootfs_type: {:erofs, ["-b", "4096", "-C", "16384", "-zlz4", "-Efragments,ztailpacking", "-T", "0", "-U", "clear"]}
  "squashfs" -> config :nerves, :firmware, rootfs_type: :squashfs
  _ -> :ok
end

# Experiment: background driver coldplug from erlinit before the BEAM starts
if System.get_env("BOOT_EARLY_COLDPLUG") == "1" do
  config :nerves, :erlinit, pre_run_exec: "/usr/sbin/early-coldplug"
end

# Experiment: MOTD mode (sync | async | off), see rootfs_overlay/etc/iex.exs
if motd = System.get_env("BOOT_MOTD") do
  config :boot_bench, motd: String.to_atom(motd)
end

if System.get_env("BOOT_TOOLSHED") == "0" do
  config :boot_bench, toolshed: false
end
