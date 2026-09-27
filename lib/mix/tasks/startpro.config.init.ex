defmodule Mix.Tasks.Startpro.Config.Init do
  @shortdoc "Creates the startpro profiles config file"

  @moduledoc """
  Creates the profiles config file from a commented template.

      mix startpro.config.init
      mix startpro.config.init -c ~/dotfiles/startpro.exs
      mix startpro.config.init --force

  The file is written to the path resolved as described in
  `Startpro.Config`. An existing file is never overwritten unless `--force`
  is given.

  ## Options

    * `-c`, `--config` - the config file path
    * `--force` - overwrite an existing file
  """

  use Mix.Task

  alias Startpro.{CLI, Config}

  @impl Mix.Task
  def run(argv) do
    {opts, _args} = CLI.parse!(argv, force: :boolean)
    path = Config.path(opts[:config])

    if File.exists?(path) and not Keyword.get(opts, :force, false) do
      Mix.raise("Config file already exists: #{path}\n\nPass --force to overwrite it.")
    end

    File.mkdir_p!(Path.dirname(path))
    File.cp!(Config.template_path(), path)

    Mix.shell().info("""
    Created #{path}

    Edit it with:

        mix startpro.config.edit
    """)
  end
end
