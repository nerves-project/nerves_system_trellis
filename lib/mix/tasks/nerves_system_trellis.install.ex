if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.NervesSystemTrellis.Install do
    @shortdoc "Adds the Trellis Nerves system as a build target"

    @moduledoc """
    #{@shortdoc}

    Intended to be run in a freshly generated `mix nerves.new` project:

        $ mix igniter.install nerves_system_trellis

    It adds `:nerves_system_trellis` to your dependencies for the `:trellis`
    target and registers `:trellis` in the project's `@all_targets` list. Once
    installed, build firmware with `MIX_TARGET=trellis`.
    """

    use Igniter.Mix.Task

    @external_resource version_path = Path.expand("../../../VERSION", __DIR__)
    @version_requirement version_path
                         |> File.read!()
                         |> String.trim()
                         |> Version.parse!()
                         |> then(fn %Version{major: major, minor: minor} ->
                           "~> #{major}.#{minor}"
                         end)

    @impl Igniter.Mix.Task
    def info(_argv, _parent) do
      %Igniter.Mix.Task.Info{
        group: :nerves,
        example: "mix igniter.install nerves_system_trellis"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      igniter
      |> Igniter.Project.Deps.add_dep(
        {:nerves_system_trellis, @version_requirement, runtime: false, targets: :trellis},
        append?: true
      )
      |> add_trellis_target()
    end

    defp add_trellis_target(igniter) do
      Igniter.update_elixir_file(igniter, "mix.exs", fn zipper ->
        with {:ok, zipper} <-
               Igniter.Code.Module.move_to_attribute_definition(zipper, :all_targets),
             {:ok, zipper} <- Igniter.Code.Common.move_to(zipper, &Igniter.Code.List.list?/1) do
          Igniter.Code.List.append_new_to_list(zipper, :trellis)
        else
          _ ->
            {:warning,
             "Could not find an `@all_targets` attribute in mix.exs. If you use nerves_pack, add `:trellis` to it manually."}
        end
      end)
    end
  end
else
  defmodule Mix.Tasks.NervesSystemTrellis.Install do
    @shortdoc "Adds the Trellis Nerves system as a build target | Install `igniter` to use"

    @moduledoc @shortdoc

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'nerves_system_trellis.install' requires igniter.

      Install igniter and run again, or add the target manually:

          {:nerves_system_trellis, "~> 0.3", runtime: false, targets: :trellis}

      See https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
