#!/usr/bin/env python3
"""One suspend-to-idle cycle with an on-device recorder of VintageNet
events (ms after the suspend write returned). RESUME_EXPR (Elixir) runs right
after waking; PRE_EXPR right before suspending."""
import os, sys, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import serial, bootcap
setup = '''File.write!("/sys/class/tty/ttyS4/power/wakeup", "enabled"); File.write!("/sys/module/printk/parameters/console_suspend", "N"); Process.whereis(:netrec) && Process.exit(Process.whereis(:netrec), :kill); spawn(fn -> Process.register(self(), :netrec); for p <- [["interface", :_, "connection"], ["interface", :_, "addresses"], ["interface", "wlan0", "wifi", "current_ap"], ["interface", :_, "lower_up"]], do: VintageNet.subscribe(p); loop = fn loop, acc -> receive do {VintageNet, prop, _old, new, _} -> loop.(loop, [{:os.system_time(:millisecond), prop, (case new do %{ssid: s} -> s; l when is_list(l) -> Enum.map(l, & &1.address) |> Enum.filter(&(tuple_size(&1) == 4)); x -> x end)} | acc]); {:get, from} -> send(from, {:net, Enum.reverse(acc)}); loop.(loop, acc) end end; loop.(loop, []) end); IO.puts("rec")'''
bootcap.serial_eval(setup, timeout=20)
pre = os.environ.get("PRE_EXPR", ":ok"); post = os.environ.get("RESUME_EXPR", ":ok")
s = serial.Serial(bootcap.DEV, 115200, timeout=0.02); s.write(b"\r"); time.sleep(0.3); s.reset_input_buffer()
s.write(f'{pre}; r = File.write("/sys/power/state", "mem"); Process.put(:woke, :os.system_time(:millisecond)); post = ({post}); Process.put(:post, post); IO.puts("WOKE" <> "UP")\r'.encode())
time.sleep(3); s.write(b"\r"); time.sleep(12); s.close()
print(bootcap.serial_eval('''w = Process.get(:woke); IO.inspect(Process.get(:post), label: "post"); send(:netrec, {:get, self()}); receive do {:net, l} -> for {t, p, v} <- l, t > w - 100, do: IO.puts("#{t - w} ms #{Enum.join(p, ".")} #{inspect(v)}") end''', timeout=20))
