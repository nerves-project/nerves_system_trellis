defmodule BootTools.NetEvents do
  @moduledoc """
  Records every VintageNet connection/address change with a monotonic
  timestamp from boot, so the report can show the *first* time each
  interface reached :lan / :internet (PropertyTable only keeps the latest).
  """
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)
  def events(), do: GenServer.call(__MODULE__, :events)

  @impl true
  def init(_) do
    VintageNet.subscribe(["interface", :_, "connection"])
    VintageNet.subscribe(["interface", :_, "addresses"])
    {:ok, []}
  end

  @impl true
  def handle_info({VintageNet, ["interface", ifname, "connection"], _old, new, _meta}, acc) do
    {:noreply, [{System.monotonic_time(:microsecond), ifname, new} | acc]}
  end

  def handle_info({VintageNet, ["interface", ifname, "addresses"], _old, new, _meta}, acc) do
    ipv4? = Enum.any?(List.wrap(new), &match?(%{family: :inet}, &1))
    if ipv4?,
      do: {:noreply, [{System.monotonic_time(:microsecond), ifname, :ipv4} | acc]},
      else: {:noreply, acc}
  end

  def handle_info(_, acc), do: {:noreply, acc}

  @impl true
  def handle_call(:events, _from, acc), do: {:reply, Enum.reverse(acc), acc}
end
