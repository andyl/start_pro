defmodule Mix.Tasks.StartPro.Config.Edit do
  @shortdoc "Opens the start_pro profiles config file in $EDITOR"

  @moduledoc """
  Opens the profiles config file in `$EDITOR` (or `$VISUAL`), then checks
  that every profile still loads and resolves.

      mix start_pro.config.edit
      mix start_pro.config.edit -c ~/dotfiles/start_pro.exs

  Terminal editors inherit the terminal. GUI editors must be told to wait
  for the file to close, for example `EDITOR="code --wait"`.

  A config that fails validation after editing is reported as a warning; the
  file is left as you saved it.

  ## Options

    * `-c`, `--config` - the config file path
  """

  use Mix.Task

  alias StartPro.{CLI, Config, Editor, Error, Resolver}

  @impl Mix.Task
  def run(argv) do
    {opts, _args} = CLI.parse!(argv)
    path = Config.path(opts[:config])

    unless File.regular?(path) do
      Mix.raise(
        "Config file not found: #{path}\n\nCreate it with:\n\n    mix start_pro.config.init"
      )
    end

    editor =
      Editor.command() ||
        Mix.raise("Neither $EDITOR nor $VISUAL is set. Set one, e.g. EDITOR=vim")

    CLI.ok!(Editor.open(editor, path))

    with {:ok, profiles} <- Config.load(path),
         :ok <- Resolver.validate_all(profiles) do
      Mix.shell().info("#{path} is valid (#{length(profiles)} profiles)")
    else
      {:error, reason} ->
        Mix.shell().error("Warning: #{path} is not valid:\n\n" <> Error.message(reason))
    end
  end
end
