defmodule BootTools.Report do
  @moduledoc """
  Collects boot timing data on the device, all on the kernel uptime clock.

  Run `BootTools.Report.json()` over ssh after boot.
  """

  @doc "Offset (us) to add to Erlang monotonic microseconds to get kernel uptime microseconds."
  def mono_to_uptime_offset() do
    # /proc/uptime has 10 ms resolution; wait for a tick edge for ~1 ms accuracy.
    u0 = read_uptime()
    wait_tick(u0)
  end

  defp wait_tick(u0) do
    m = System.monotonic_time(:microsecond)
    u = read_uptime()
    if u != u0, do: round(u * 1_000_000) - m, else: wait_tick(u0)
  end

  defp read_uptime() do
    "/proc/uptime" |> File.read!() |> String.split() |> hd() |> String.to_float()
  end

  def collect() do
    off = mono_to_uptime_offset()
    to_up = fn us -> Float.round((us + off) / 1_000_000, 4) end

    marks =
      case Code.ensure_loaded?(:boot_trace) and :boot_trace.marks() do
        list when is_list(list) -> Enum.map(list, fn
          {t, l, n} -> %{t: to_up.(t), label: inspect(l), loaded: n}
          {t, l} -> %{t: to_up.(t), label: inspect(l)}
        end)
        _ -> []
      end

    vm_start = to_up.(System.convert_time_unit(:erlang.system_info(:start_time), :native, :microsecond))

    vintage =
      if Code.ensure_loaded?(PropertyTable) and Process.whereis(VintageNet) do
        for {prop, value, ts} <- PropertyTable.get_all_with_timestamps(VintageNet),
            match?(["interface", _, k] when k in ["connection", "addresses", "lower_up", "state"], prop) do
          %{t: to_up.(System.convert_time_unit(ts, :native, :microsecond)), prop: Enum.join(prop, "."), value: inspect(value, limit: 3)}
        end
        |> Enum.sort_by(& &1.t)
      else
        []
      end

    %{
      uptime_now: read_uptime(),
      vm_start: vm_start,
      beam_proc_start: proc_start(System.pid()),
      procs: procs(),
      marks: marks,
      vintage_net: vintage,
      dmesg: dmesg(),
      fw: (Code.ensure_loaded?(Nerves.Runtime.KV) && apply(Nerves.Runtime.KV, :get_active, ["nerves_fw_version"])) || "",
      loaded_modules: length(:code.all_loaded()),
      samples:
        if(Code.ensure_loaded?(:boot_trace) and function_exported?(:boot_trace, :samples, 0),
          do:
            for {t, busy} <- List.wrap(:boot_trace.samples()) do
              %{
                t: to_up.(t),
                busy:
                  for {who, frames} <- busy do
                    %{who: inspect(who), frames: Enum.map(frames, fn {m, f, a} -> "#{inspect(m)}.#{f}/#{a}" end)}
                  end
              }
            end,
          else: []
        ),
      cpu:
        if(Code.ensure_loaded?(:boot_trace) and function_exported?(:boot_trace, :cpu, 0),
          do: for({label, snap} <- List.wrap(:boot_trace.cpu()), do: cpu_entry(label, snap, to_up)),
          else: []
        ),
      net_events:
        if(Process.whereis(BootTools.NetEvents),
          do: for({t, ifn, v} <- BootTools.NetEvents.events(), do: %{t: to_up.(t), ifname: ifn, value: inspect(v)}),
          else: []
        ),
      proc_snapshot: proc_snapshot(to_up),
      uevent: uevent_info(),
      boot_modules:
        if(Code.ensure_loaded?(:boot_trace) and function_exported?(:boot_trace, :snapshot, 0),
          do: :boot_trace.snapshot() |> Enum.reject(&(:code.which(&1) == :preloaded)) |> Enum.map(&Atom.to_string/1) |> Enum.sort(),
          else: []
        ),
      # erlang:loaded/0 lists modules newest first, so reversed it's the
      # order of first load.
      boot_load_order:
        if(Code.ensure_loaded?(:boot_trace) and function_exported?(:boot_trace, :snapshot, 0),
          do: :boot_trace.snapshot() |> Enum.reverse() |> Enum.reject(&(:code.which(&1) == :preloaded)) |> Enum.map(&Atom.to_string/1),
          else: []
        ),
      apps: length(Application.started_applications()),
      started_apps: Application.started_applications() |> Enum.map(&Atom.to_string(elem(&1, 0))) |> Enum.sort(),
      ring_logger: Process.whereis(RingLogger.Server) != nil
    }
  end

  defp cpu_entry(label, {t, {runtime_ms, _}, proc_stat, self_stat, msacc}, to_up) do
    [cpu | _] = String.split(proc_stat, "\n")
    # user nice system idle iowait irq softirq (jiffies, 100 Hz)
    jiffies = cpu |> String.split() |> tl() |> Enum.take(7) |> Enum.map(&String.to_integer/1)
    [_, rest] = String.split(self_stat, ") ", parts: 2)
    fields = String.split(rest)
    utime = String.to_integer(Enum.at(fields, 11))
    stime = String.to_integer(Enum.at(fields, 12))

    %{
      label: inspect(label),
      t: to_up.(t),
      vm_runtime_ms: runtime_ms,
      beam_utime: utime,
      beam_stime: stime,
      system_jiffies: Enum.zip([:user, :nice, :system, :idle, :iowait, :irq, :softirq], jiffies) |> Map.new(),
      msacc: msacc_totals(msacc)
    }
  end

  defp msacc_totals(list) when is_list(list) do
    # Sum each state's time (microseconds) per thread type
    for %{type: type, counters: c} <- list, reduce: %{} do
      acc ->
        Map.update(acc, type, to_us(c), fn old -> Map.merge(old, to_us(c), fn _, a, b -> a + b end) end)
    end
  end

  defp msacc_totals(_), do: nil

  defp to_us(c), do: Map.new(c, fn {k, v} -> {k, :erlang.convert_time_unit(v, :perf_counter, :microsecond)} end)

  defp proc_snapshot(to_up) do
    case Code.ensure_loaded?(:boot_trace) and function_exported?(:boot_trace, :procs, 0) and :boot_trace.procs() do
      {t, procs} when is_list(procs) ->
        total = procs |> Enum.map(&elem(&1, 1)) |> Enum.sum()
        top =
          procs
          |> Enum.group_by(fn {who, _} -> inspect(who) end, &elem(&1, 1))
          |> Enum.map(fn {who, rs} -> %{who: who, reductions: Enum.sum(rs), count: length(rs)} end)
          |> Enum.sort_by(&(-&1.reductions))
          |> Enum.take(25)

        %{t: to_up.(t), total_reductions: total, top: top}

      _ ->
        nil
    end
  end

  defp uevent_info() do
    stats = if Process.whereis(NervesUEvent.UEvent), do: inspect(apply(NervesUEvent.UEvent, :stats, []), limit: :infinity), else: nil
    props = if Code.ensure_loaded?(PropertyTable) and Process.whereis(NervesUEvent), do: length(PropertyTable.get_all(NervesUEvent)), else: nil

    # CPU time (jiffies) of the uevent port program, including reaped modprobe children
    cpu =
      for pid <- File.ls!("/proc"), pid =~ ~r/^\d+$/,
          {:ok, cmd} <- [File.read("/proc/#{pid}/cmdline")],
          String.contains?(cmd, "nerves_uevent"),
          {:ok, stat} <- [File.read("/proc/#{pid}/stat")] do
        [_, rest] = String.split(stat, ") ", parts: 2)
        f = String.split(rest)
        %{pid: pid, utime: Enum.at(f, 11), stime: Enum.at(f, 12), cutime: Enum.at(f, 13), cstime: Enum.at(f, 14)}
      end

    %{stats: stats, properties: props, port_cpu_jiffies: cpu}
  end

  def json(), do: collect() |> JSON.encode!() |> IO.puts()

  defp proc_start(pid) do
    with {:ok, s} <- File.read("/proc/#{pid}/stat"),
         [_, rest] <- String.split(s, ") ", parts: 2) do
      rest |> String.split() |> Enum.at(19) |> String.to_integer() |> Kernel./(100)
    else
      _ -> nil
    end
  end

  defp procs() do
    File.ls!("/proc")
    |> Enum.filter(&(&1 =~ ~r/^\d+$/))
    |> Enum.flat_map(fn pid ->
      cmd = case File.read("/proc/#{pid}/cmdline") do
        {:ok, c} -> c |> String.replace(<<0>>, " ") |> String.slice(0, 80)
        _ -> ""
      end
      t = proc_start(pid)
      if cmd != "" and t, do: [%{t: t, pid: String.to_integer(pid), cmd: cmd}], else: []
    end)
    |> Enum.sort_by(& &1.t)
  end

  defp dmesg() do
    {out, _} = System.cmd("dmesg", [])
    for line <- String.split(out, "\n"),
        [_, t, msg] <- [Regex.run(~r/^\[\s*(\d+\.\d+)\]\s?(.*)$/, line)],
        do: %{t: String.to_float(t), msg: msg}
  end
end
