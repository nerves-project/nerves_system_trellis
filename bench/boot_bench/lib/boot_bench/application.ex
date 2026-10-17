defmodule BootBench.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @target Mix.target()

  @impl true
  def start(_type, _args) do
    # Normally done in config/runtime.exs. Doing it here lets the release skip
    # the runtime config provider (BOOT_NO_RUNTIME_CONFIG=1), which costs ~0.6 s
    # on a T113 because it loads Elixir's evaluator. Adding twice is harmless.
    if @target != :host do
      {:ok, _} = Application.ensure_all_started(:logger_backends)
      {:ok, _} = LoggerBackends.add(RingLogger)
    end

    children =
      [
        # Children for all targets
        # Starts a worker by calling: BootBench.Worker.start_link(arg)
        # {BootBench.Worker, arg},
      ] ++ target_children()

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BootBench.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # List all child processes to be supervised
  if Mix.target() == :host do
    defp target_children() do
      [
        # Children that only run on the host during development or test.
        # In general, prefer using `config/host.exs` for differences.
        #
        # Starts a worker by calling: Host.Worker.start_link(arg)
        # {Host.Worker, arg},
      ]
    end
  else
    defp target_children() do
      [
        # Children for all targets except host
        # Starts a worker by calling: Target.Worker.start_link(arg)
        # {Target.Worker, arg},
      ]
    end
  end
end
