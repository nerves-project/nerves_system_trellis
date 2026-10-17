defmodule BootTools.MixProject do
  use Mix.Project

  def project do
    [
      app: :boot_tools,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: [{:vintage_net, "~> 0.13", optional: true}, {:ring_logger, "~> 0.11", optional: true}]
    ]
  end

  def application do
    [mod: {BootTools.Application, []}, extra_applications: [:logger]]
  end
end
