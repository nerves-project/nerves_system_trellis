defmodule BootBenchTest do
  use ExUnit.Case
  doctest BootBench

  test "greets the world" do
    assert BootBench.hello() == :world
  end
end
