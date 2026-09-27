defmodule Mix.Tasks.StartPro.List.Steps do
  @shortdoc "Shows a profile's fully resolved step list"

  @moduledoc """
  Shows the fully expanded, numbered step list of a profile, with the
  profile each step came from and the include flags that gate it.

      $ mix start_pro.list.steps standard_app
      Profile standard_app (/home/you/.config/start_pro/profiles.exs):

         1. {:remove, :daisy_ui}  [phoenix_cleanup]
         2. {:add, :credo}  [tooling]
         3. {:add, :exsync, if: :exsync}  [tooling]
         4. {:gen, :gigalixir}  [deploy_gigalixir] if :gigalixir
         5. {:gen, :sort_deps}  [finish]

      Flags: --gigalixir --exsync

  Every gated include is followed, so the list shows everything the profile
  can run. Steps dropped as duplicates are listed at the end.

  ## Options

    * `-c`, `--config` - the config file path
  """

  use Mix.Task

  alias StartPro.{CLI, Error, Resolver}

  @impl Mix.Task
  def run(argv) do
    {opts, args} = CLI.parse!(argv)

    name =
      case args do
        [name] -> name
        _ -> Mix.raise("Usage: mix start_pro.list.steps PROFILE")
      end

    %{path: path, name: name, result: result} = CLI.load_profile!(opts[:config], name, :all)

    Mix.shell().info("Profile #{Error.name(name)} (#{path}):\n")

    case result.steps do
      [] -> Mix.shell().info("  (no steps)")
      entries -> Mix.shell().info(CLI.render_entries(entries))
    end

    case Resolver.flags(result) do
      [] -> :ok
      flags -> Mix.shell().info("\nFlags: " <> CLI.switches(flags))
    end

    case result.duplicates do
      [] ->
        :ok

      duplicates ->
        Mix.shell().info("\nDuplicates dropped (first occurrence wins):")
        Enum.each(duplicates, &Mix.shell().info("  " <> CLI.render_entry(&1)))
    end
  end
end
