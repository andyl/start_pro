defmodule Mix.Tasks.StartPro.Run do
  @shortdoc "Applies a start_pro profile to the current app and commits it"

  @moduledoc """
  Resolves a profile and applies it to the current app with `starter`'s
  engine, then records the run as one git commit.

      mix start_pro.run standard_app
      mix start_pro.run standard_app --gigalixir --oban-pro
      mix start_pro.run standard_app --dry-run
      mix start_pro.run standard_app --no-commit

  Every `if:` flag in the profile, whether on a step or on an include,
  becomes a `--flag` option. `mix start_pro.list.steps PROFILE` shows them.

  ## Requirements

  Both `start_pro` and `starter` must be dependencies of the target app:
  `starter` provides the runner and the built-in steps. No `mix starter.new`
  file or in-app starter module is needed. If an app has one anyway, the two
  don't interact, but running both would apply the steps twice.

  ## Git commit

  Unless `--no-commit` is given, the run:

    1. refuses to start if the app is not inside a git work tree, or if the
       tree has uncommitted, unstaged or untracked changes. This is checked
       before anything is written, including the dependency fetch;
    2. applies the steps as one diff, confirmed once;
    3. commits everything with `git add -A` and a message listing the config
       path, the flags, and every step with the profile it came from.

  The commit is a queued task, so it runs last, after any `{:queue, ...}`
  steps, and only if the diff is applied. `--dry-run` or declining the diff
  commits nothing.

  ## Options

    * `-c`, `--config` - the config file path
    * `--no-commit` - skip the git checks and the commit
    * `--dry-run`, `--yes` - as for any Igniter task
  """

  use Igniter.Mix.Task

  alias StartPro.{CLI, Error, Git, Registry, Resolver}

  @base_schema [config: :string, no_commit: :boolean]

  @reserved Keyword.keys(@base_schema) ++
              Keyword.keys(Igniter.Mix.Task.Info.global_options()[:switches])

  @impl Igniter.Mix.Task
  def info(argv, _composing_task) do
    flag_schema =
      case CLI.prescan(argv) do
        {config, [profile | _]} ->
          %{result: result} = CLI.load_profile!(config, profile, :all)
          flags = Resolver.flags(result)

          if flag = Enum.find(flags, &(&1 in @reserved)) do
            Mix.raise(Error.message({:reserved_flag, flag}))
          end

          Enum.map(flags, &{&1, :boolean})

        {_config, []} ->
          []
      end

    %Igniter.Mix.Task.Info{
      positional: [:profile],
      schema: @base_schema ++ flag_schema,
      aliases: [c: :config],
      example: "mix start_pro.run standard_app --gigalixir"
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    opts = igniter.args.options
    commit? = not Keyword.get(opts, :no_commit, false)

    # Validate every include, gated or not, before anything runs.
    %{path: path, profiles: profiles, name: name, result: all} =
      CLI.load_profile!(opts[:config], igniter.args.positional.profile, :all)

    result = CLI.ok!(Resolver.resolve(profiles, name, flags: opts))
    active = Resolver.active(result.steps, opts)

    check_modules!(active)
    if commit?, do: check_git!()

    steps = result |> Resolver.steps_only() |> Enum.map(&Registry.translate/1)
    igniter = StartPro.Starter.run(igniter, steps, opts)

    if commit? do
      flags = Enum.filter(Resolver.flags(all), &(Keyword.get(opts, &1) == true))
      message = Git.message(name, %{config: path, flags: flags}, active)

      file = write_message!(message, Keyword.get(opts, :dry_run, false))
      Igniter.add_task(igniter, "start_pro.git.commit", ["--message-file", file])
    else
      igniter
    end
  end

  defp check_git! do
    case Git.status(File.cwd!()) do
      :clean ->
        :ok

      :not_a_repo ->
        Mix.raise("""
        This app is not inside a git repository, so the run can't be committed.

        Create one first:

            git init && git add -A && git commit -m "Initial commit"

        or pass --no-commit to run without committing.
        """)

      :dirty ->
        Mix.raise("""
        The git work tree has uncommitted changes, which would be mixed into
        the run's commit.

        Commit or stash them first (see `git status`), or pass --no-commit to
        run without committing.
        """)
    end
  end

  # Custom step modules, registry steps and unexpanded starters must be
  # compiled into the target app; fail early, naming the profile, rather
  # than mid-run.
  defp check_modules!(entries) do
    Enum.each(entries, fn %{step: step, origin: origin} ->
      module = step |> Registry.translate() |> step_module()

      cond do
        is_nil(module) or Code.ensure_loaded?(module) ->
          :ok

        Registry.registry_step?(step) ->
          Mix.raise(Error.message({:missing_registry_step, origin, step, module}))

        true ->
          Mix.raise(Error.message({:missing_module, origin, module}))
      end
    end)
  end

  @kinds [:add, :remove, :gen, :install, :queue, :task, :starter]

  defp step_module({:starter, module}), do: module
  defp step_module({:starter, module, _opts}), do: module
  defp step_module({kind, _opts}) when kind in @kinds, do: nil
  defp step_module({module, opts}) when is_atom(module) and is_list(opts), do: module
  defp step_module(module) when is_atom(module), do: module
  defp step_module(_step), do: nil

  # The commit task deletes the file, but it never runs on a dry run, a
  # declined diff, or after a failed queued task. Dry runs don't write the
  # file at all, and files left behind by earlier runs are swept here.
  @message_glob "start_pro-commit-*.txt"
  @stale_after_seconds 3600

  defp write_message!(message, dry_run?) do
    tmp = System.tmp_dir!()
    sweep_stale_messages(tmp)

    name =
      String.replace(
        @message_glob,
        "*",
        "#{System.os_time(:millisecond)}-#{System.unique_integer([:positive])}"
      )

    path = Path.join(tmp, name)
    unless dry_run?, do: File.write!(path, message)
    shell_arg(path)
  end

  defp sweep_stale_messages(tmp) do
    cutoff = System.os_time(:second) - @stale_after_seconds

    tmp
    |> Path.join(@message_glob)
    |> Path.wildcard()
    |> Enum.each(fn file ->
      case File.stat(file, time: :posix) do
        {:ok, %{mtime: mtime}} when mtime < cutoff -> File.rm(file)
        _ -> :ok
      end
    end)
  end

  # Igniter runs queued tasks through the shell with args joined by spaces.
  defp shell_arg(path) do
    if path =~ ~r{\A[\w/.\-]+\z},
      do: path,
      else: "'" <> String.replace(path, "'", ~S('\'')) <> "'"
  end
end
