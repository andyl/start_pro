defmodule Mix.Tasks.StartPro.List.Profiles do
  @shortdoc "Lists the profiles in the start_pro config file"

  @moduledoc """
  Lists every profile in the config file, in config order, with the profiles
  and starter modules it includes directly.

      $ mix start_pro.list.profiles
      Profiles in /home/you/.config/start_pro/profiles.exs:

        phoenix_cleanup
        tooling
        standard_app      (uses: phoenix_cleanup, tooling, deploy_gigalixir if :gigalixir, finish)

  ## Options

    * `-c`, `--config` - the config file path
  """

  use Mix.Task

  alias StartPro.{CLI, Error, Resolver}

  @impl Mix.Task
  def run(argv) do
    {opts, _args} = CLI.parse!(argv)
    {path, profiles} = CLI.load!(opts[:config])

    Mix.shell().info("Profiles in #{path}:\n")

    if profiles == [] do
      Mix.shell().info("  (none)")
    else
      width = profiles |> Enum.map(&String.length(Error.name(elem(&1, 0)))) |> Enum.max()

      Enum.each(profiles, fn {name, _steps} ->
        line =
          case Resolver.uses(profiles, name) do
            [] -> Error.name(name)
            uses -> String.pad_trailing(Error.name(name), width) <> "  (uses: #{render(uses)})"
          end

        Mix.shell().info("  " <> line)
      end)
    end
  end

  defp render(uses) do
    Enum.map_join(uses, ", ", fn
      {_kind, target, nil} -> Error.name(target)
      {_kind, target, flag} -> "#{Error.name(target)} if #{inspect(flag)}"
    end)
  end
end
