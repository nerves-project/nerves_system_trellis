defmodule BootTools.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # Record network events only when VintageNet is part of the release
    children = if Code.ensure_loaded?(VintageNet), do: [BootTools.NetEvents], else: []
    Supervisor.start_link(children, strategy: :one_for_one, name: BootTools.Supervisor)
  end
end
