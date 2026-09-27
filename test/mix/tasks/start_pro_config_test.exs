defmodule Mix.Tasks.StartPro.ConfigTest do
  # Changes EDITOR / VISUAL.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.StartPro.Config.{Edit, Init}
  alias StartPro.{Config, Resolver}

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    saved = for var <- ~w(EDITOR VISUAL), into: %{}, do: {var, System.get_env(var)}

    on_exit(fn ->
      Enum.each(saved, fn
        {var, nil} -> System.delete_env(var)
        {var, value} -> System.put_env(var, value)
      end)
    end)

    %{path: Path.join([dir, "nested", "profiles.exs"])}
  end

  describe "config.init" do
    test "writes the template, creating parent directories", %{path: path} do
      output = capture_io(fn -> Init.run(["-c", path]) end)

      assert output =~ "Created #{path}"
      assert File.read!(path) == File.read!(Config.template_path())
    end

    test "every template profile resolves under flags: :all", %{path: path} do
      capture_io(fn -> Init.run(["--config", path]) end)

      assert {:ok, profiles} = Config.load(path)
      assert :ok = Resolver.validate_all(profiles)
      assert :standard_app in Keyword.keys(profiles)
    end

    test "refuses to overwrite unless --force", %{path: path} do
      capture_io(fn -> Init.run(["-c", path]) end)
      File.write!(path, "[]")

      assert_raise Mix.Error, ~r/already exists/, fn -> Init.run(["-c", path]) end
      assert File.read!(path) == "[]"

      capture_io(fn -> Init.run(["-c", path, "--force"]) end)
      assert File.read!(path) == File.read!(Config.template_path())
    end
  end

  describe "config.edit" do
    setup %{path: path} do
      capture_io(fn -> Init.run(["-c", path]) end)
      System.delete_env("EDITOR")
      System.delete_env("VISUAL")
      :ok
    end

    test "runs $EDITOR and validates the file", %{path: path} do
      System.put_env("EDITOR", "true")
      assert capture_io(fn -> Edit.run(["-c", path]) end) =~ "is valid (7 profiles)"
    end

    test "falls back to $VISUAL", %{path: path} do
      System.put_env("VISUAL", "true")
      assert capture_io(fn -> Edit.run(["-c", path]) end) =~ "is valid"
    end

    test "passes the file to the editor", %{path: path} do
      System.put_env("EDITOR", ~s(sh -c 'echo "[a: [{:use, :b}]]" > "$0"'))

      output = capture_io(:stderr, fn -> Edit.run(["-c", path]) end)
      assert output =~ "Warning"
      assert output =~ "uses b, which is not defined"
    end

    test "raises when no editor is set", %{path: path} do
      assert_raise Mix.Error, ~r/Neither \$EDITOR nor \$VISUAL/, fn -> Edit.run(["-c", path]) end
    end

    test "raises when the editor fails", %{path: path} do
      System.put_env("EDITOR", "false")
      assert_raise Mix.Error, ~r/exited with status 1/, fn -> Edit.run(["-c", path]) end
    end

    test "raises with a hint when the file is missing", %{tmp_dir: dir} do
      System.put_env("EDITOR", "true")

      assert_raise Mix.Error, ~r/start_pro.config.init/, fn ->
        Edit.run(["-c", Path.join(dir, "missing.exs")])
      end
    end
  end
end
