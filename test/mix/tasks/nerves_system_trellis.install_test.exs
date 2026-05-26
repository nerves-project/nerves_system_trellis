defmodule Mix.Tasks.NervesSystemTrellis.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  @nerves_mix_exs """
  defmodule MyApp.MixProject do
    use Mix.Project

    @app :my_app
    @version "0.1.0"
    @all_targets [:rpi, :rpi0, :bbb]

    def project do
      [app: @app, version: @version, deps: deps()]
    end

    def application, do: [extra_applications: [:logger]]

    defp deps do
      [
        {:nerves, "~> 1.10", runtime: false},
        {:nerves_runtime, "~> 0.13"},
        {:nerves_pack, "~> 0.7", targets: @all_targets},
        {:nerves_system_rpi, "~> 1.24", runtime: false, targets: :rpi},
        {:nerves_system_bbb, "~> 2.19", runtime: false, targets: :bbb}
      ]
    end
  end
  """

  @host_only_mix_exs """
  defmodule MyApp.MixProject do
    use Mix.Project

    @app :my_app
    @version "0.1.0"

    def project do
      [app: @app, version: @version, deps: deps()]
    end

    def application, do: [extra_applications: [:logger]]

    defp deps do
      [
        {:nerves, "~> 1.10", runtime: false},
        {:nerves_runtime, "~> 0.13"}
      ]
    end
  end
  """

  test "adds the trellis dependency and registers the target in @all_targets" do
    content =
      test_project(files: %{"mix.exs" => @nerves_mix_exs})
      |> Igniter.compose_task("nerves_system_trellis.install", [])
      |> apply_igniter!()
      |> mix_exs_content()

    assert content =~ ~r/@all_targets \[:rpi, :rpi0, :bbb, :trellis\]/

    assert content =~
             ~s|{:nerves_system_trellis, "~> 0.3", runtime: false, targets: :trellis}|
  end

  test "warns and only adds the dependency when there is no @all_targets" do
    igniter =
      test_project(files: %{"mix.exs" => @host_only_mix_exs})
      |> Igniter.compose_task("nerves_system_trellis.install", [])

    assert_has_warning(igniter, &(&1 =~ "@all_targets"))

    content =
      igniter
      |> apply_igniter!()
      |> mix_exs_content()

    assert content =~
             ~s|{:nerves_system_trellis, "~> 0.3", runtime: false, targets: :trellis}|

    refute content =~ "@all_targets"
  end

  defp mix_exs_content(igniter) do
    igniter.rewrite
    |> Rewrite.source!("mix.exs")
    |> Rewrite.Source.get(:content)
  end
end
