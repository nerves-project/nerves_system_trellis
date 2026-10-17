defmodule BootTools.LogFormat do
  @moduledoc "Diagnostic log formatter: monotonic microseconds instead of wall-clock time."
  def format(_level, message, _timestamp, _metadata) do
    [Integer.to_string(System.monotonic_time(:microsecond)), " ", message, "\n"]
  rescue
    _ -> "format error\n"
  end
end
