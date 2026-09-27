defmodule Mix.Tasks.StartPro.RunTest do
  # Changes the VM's working directory (the git checks read File.cwd!/0) and
  # the adapter's :persistent_term.
  use ExUnit.Case, async: false

  import Igniter.Test
  import StartPro.Test.GitHelpers

  @moduletag :tmp_dir

  @config """
  [
    base: [{:gen, :gitignore}],
    deploy: [{:gen, :ecto_force_drop}],
    app: [{:use, :base}, {:gen, :ecto_force_drop, if: :force_drop}, {:queue, "foo.bar"}],
    gated: [{:use, :base}, {:use, :deploy, if: :deploy}],
    custom: [{:gen, :gitignore}, Not.A.Loaded.Step],
    reserved: [{:gen, :gitignore, if: :yes}]
  ]
  """

  @mix_exs """
  defmodule Test.MixProject do
    use Mix.Project

    def project do
      [app: :test, version: "0.1.0", deps: [], aliases: aliases()]
    end

    defp aliases do
      ["ecto.reset": ["ecto.drop", "ecto.setup"]]
    end
  end
  """

  setup %{tmp_dir: dir} do
    config = Path.join(dir, "profiles.exs")
    File.write!(config, @config)

    app = Path.join(dir, "app")
    File.mkdir_p!(app)
    init_repo!(app)

    cwd = File.cwd!()
    File.cd!(app)

    on_exit(fn ->
      File.cd!(cwd)
      clean_message_files()
    end)

    %{config: config, app: app}
  end

  defp run(argv) do
    test_project(files: %{"mix.exs" => @mix_exs})
    |> Igniter.compose_task("start_pro.run", argv)
  end

  defp assert_changed(igniter, path) do
    source = Rewrite.source!(igniter.rewrite, path)
    assert Rewrite.Source.updated?(source), "expected #{path} to be changed"
    igniter
  end

  defp commit_tasks(igniter) do
    for {"start_pro.git.commit", argv} <- igniter.tasks, do: argv
  end

  defp clean_message_files do
    System.tmp_dir!()
    |> Path.join("start_pro-commit-*.txt")
    |> Path.wildcard()
    |> Enum.each(&File.rm/1)
  end

  test "applies the resolved profile", %{config: config} do
    run(["app", "-c", config])
    |> assert_changed(".gitignore")
    |> assert_unchanged("mix.exs")
  end

  test "a flagged step is skipped without its flag and applied with it", %{config: config} do
    assert_unchanged(run(["app", "-c", config]), "mix.exs")

    run(["app", "-c", config, "--force-drop"])
    |> assert_has_patch(
      "mix.exs",
      ~S(+ |    ["ecto.reset": ["ecto.drop --force-drop", "ecto.setup"]])
    )
  end

  test "a gated use is skipped without its flag and applied with it", %{config: config} do
    run(["gated", "-c", config])
    |> assert_changed(".gitignore")
    |> assert_unchanged("mix.exs")

    run(["gated", "--config", config, "--deploy"])
    |> assert_has_patch(
      "mix.exs",
      ~S(+ |    ["ecto.reset": ["ecto.drop --force-drop", "ecto.setup"]])
    )
  end

  test "queues the commit last, with the message", %{config: config} do
    igniter = run(["app", "-c", config, "--force-drop"])

    assert [{"foo.bar", ["--yes"]}, {"start_pro.git.commit", ["--message-file", file]}] =
             igniter.tasks

    assert File.read!(file) == """
           start_pro: apply profile app

           Config: #{config}
           Flags: --force-drop

           Steps:
           1. {:gen, :gitignore} [base]
           2. {:gen, :ecto_force_drop, if: :force_drop} [app]
           3. {:queue, "foo.bar"} [app]
           """
  end

  test "the message lists only steps that ran", %{config: config} do
    [["--message-file", file]] = run(["app", "-c", config]) |> commit_tasks()
    refute File.read!(file) =~ "ecto_force_drop"
    assert File.read!(file) =~ "Flags: (none)"
  end

  test "a dry run queues the commit but writes no message file", %{config: config} do
    [["--message-file", file]] = run(["app", "-c", config, "--dry-run"]) |> commit_tasks()
    refute File.exists?(file)
  end

  test "stale message files are swept", %{config: config} do
    stale = Path.join(System.tmp_dir!(), "start_pro-commit-stale.txt")
    File.write!(stale, "x")
    File.touch!(stale, System.os_time(:second) - 7200)

    run(["app", "-c", config])
    refute File.exists?(stale)
  end

  test "--no-commit queues no commit", %{config: config} do
    igniter = run(["app", "-c", config, "--no-commit"])
    assert commit_tasks(igniter) == []
    assert_changed(igniter, ".gitignore")
  end

  test "refuses a dirty tree, unless --no-commit", %{config: config, app: app} do
    File.write!(Path.join(app, "untracked.txt"), "x")

    assert_raise Mix.Error, ~r/uncommitted changes/, fn -> run(["app", "-c", config]) end
    assert_changed(run(["app", "-c", config, "--no-commit"]), ".gitignore")
  end

  test "refuses outside a git repo, unless --no-commit", %{config: config} do
    outside = Path.join(System.tmp_dir!(), "start_pro-run-#{System.unique_integer([:positive])}")
    File.mkdir_p!(outside)
    File.cd!(outside)
    on_exit(fn -> File.rm_rf!(outside) end)

    assert_raise Mix.Error, ~r/git init/, fn -> run(["app", "-c", config]) end
    assert_changed(run(["app", "-c", config, "--no-commit"]), ".gitignore")
  end

  test "a custom step missing from the app is reported with its profile", %{config: config} do
    assert_raise Mix.Error, ~r/Profile custom names Not.A.Loaded.Step/, fn ->
      run(["custom", "-c", config])
    end
  end

  test "info/2 publishes a boolean per flag", %{config: config} do
    info = Mix.Tasks.StartPro.Run.info(["--force-drop", "app", "-c", config], nil)
    assert info.positional == [:profile]
    assert info.schema[:force_drop] == :boolean
    assert info.schema[:no_commit] == :boolean
    assert info.aliases == [c: :config]

    gated = Mix.Tasks.StartPro.Run.info(["gated", "-c", config], nil)
    assert gated.schema[:deploy] == :boolean

    assert Mix.Tasks.StartPro.Run.info([], nil).schema == [config: :string, no_commit: :boolean]
  end

  test "flags that collide with task options are rejected", %{config: config} do
    assert_raise Mix.Error, ~r/Flag :yes is reserved/, fn ->
      Mix.Tasks.StartPro.Run.info(["reserved", "-c", config], nil)
    end
  end

  test "an unknown profile raises", %{config: config} do
    assert_raise Mix.Error, ~r/Unknown profile: nope/, fn -> run(["nope", "-c", config]) end
  end

  test "the adapter's step list is cleared after a run", %{config: config} do
    run(["app", "-c", config])
    assert StartPro.Starter.steps() == []
  end
end
