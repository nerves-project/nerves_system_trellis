defmodule BootBench.BootAction do
  # Nerves 2 build action (defined here because build plans are made before
  # the project compiles). Applies the boot script experiments right after the
  # release is assembled and before the rootfs is created.
  def pre_download(plan, _opts), do: plan
  def post_extract(plan, _opts), do: plan
  def pre_assemble_steps(_plan, release, _opts), do: release
  def post_assemble_steps(_plan, release, _opts), do: apply(BootTools.Step, :run, [release])
  def rootfs_creation_steps(_plan, release, _opts), do: release
  def pre_image_creation(_plan, _opts), do: :ok
  def image_creation(_plan, _opts), do: :ok
  def post_image_creation(_plan, _opts), do: :ok
end

defmodule BootBench.MixProject do
  use Mix.Project

  @app :boot_bench
  @version "0.1.0"
  @all_targets [:trellis]

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.20",
      archives: [nerves_bootstrap: "~> 1.17"],
      listeners: listeners(Mix.target(), Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [{@app, release()}],
      nerves: [actions: [BootBench.BootAction]]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {BootBench.Application, []}
    ]
  end

  def cli do
    [preferred_targets: [run: :host, test: :host]]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Dependencies for all targets
      {:nerves, github: "nerves-project/nerves", branch: "v2", override: true, runtime: false},

      {:logger_backends, "~> 1.0"},
      {:ring_logger, "~> 0.11.0"},
      {:boot_tools, path: "../boot_tools"},
      {:toolshed, "~> 0.5.0", runtime: !String.contains?(System.get_env("BOOT_LOAD_ONLY", ""), "toolshed")},

      # Allow Nerves.Runtime on host to support development, testing and CI.
      # See config/host.exs for usage.
      {:nerves_runtime, "~> 0.13.12"},

      # Dependencies for all targets except :host
      {:nerves_pack, "~> 0.7.1", targets: @all_targets},

      # Dependencies for specific targets
      # NOTE: It's generally low risk and recommended to follow minor version
      # bumps to Nerves systems. Since these include Linux kernel and Erlang
      # version updates, please review their release notes in case
      # changes to your application are needed.
      {:nerves_system_trellis, path: "../..", runtime: false, targets: :trellis, nerves: [compile: true]}
    ]
  end

  def release do
    [
      overwrite: true,
      applications:
        if(System.get_env("BOOT_LOAD_ONLY"),
          do: System.get_env("BOOT_LOAD_ONLY") |> String.split(",") |> Enum.map(&{String.to_atom(&1), :load}),
          else: []
        ),
      runtime_config_path: System.get_env("BOOT_NO_RUNTIME_CONFIG") != "1" && "config/runtime.exs",
      # Erlang distribution is not started automatically.
      # See https://nerves-pack.hexdocs.pm/readme.html#erlang-distribution
      cookie: "#{@app}_cookie",
      include_erts: &Nerves.erts/0,
      steps: [&Nerves.init_release/1, :assemble],
      strip_beams: Mix.env() == :prod or [keep: ["Docs"]]
    ]
  end

  # Uncomment the following line if using Phoenix > 1.8.
  # defp listeners(:host, :dev), do: [Phoenix.CodeReloader]
  defp listeners(_, _), do: []
end
