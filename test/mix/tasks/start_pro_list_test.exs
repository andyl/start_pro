defmodule Mix.Tasks.StartPro.ListTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.StartPro.List

  @moduletag :tmp_dir

  @config """
  [
    base: [{:remove, :daisy_ui}, {:gen, :sort_deps}],
    deploy: [{:gen, :gigalixir}],
    finish: [{:gen, :sort_deps}],
    standard_app: [
      {:use, :base},
      {:add, :oban_pro, if: :oban_pro},
      {:use, :deploy, if: :gigalixir},
      {:starter, Not.Loaded.Starter},
      {:use, :finish}
    ],
    loop_a: [{:use, :loop_b}],
    loop_b: [{:use, :loop_a}]
  ]
  """

  setup %{tmp_dir: dir} do
    path = Path.join(dir, "profiles.exs")
    File.write!(path, @config)
    %{path: path}
  end

  describe "list.profiles" do
    test "lists profiles in config order with their includes", %{path: path} do
      output = capture_io(fn -> List.Profiles.run(["-c", path]) end)

      assert output =~ "Profiles in #{path}:"

      assert output =~
               "standard_app  (uses: base, deploy if :gigalixir, Not.Loaded.Starter, finish)"

      names = Regex.scan(~r/^  (\w+)/m, output, capture: :all_but_first) |> Enum.concat()
      assert names == ~w(base deploy finish standard_app loop_a loop_b)
    end
  end

  describe "list.steps" do
    test "prints numbered entries with origin, gates, flags and duplicates", %{path: path} do
      output = capture_io(fn -> List.Steps.run(["--config", path, "standard-app"]) end)

      assert output =~ "Profile standard_app (#{path}):"
      assert output =~ "1. {:remove, :daisy_ui}  [base]"
      assert output =~ "2. {:gen, :sort_deps}  [base]"
      assert output =~ "3. {:add, :oban_pro, if: :oban_pro}  [standard_app]"
      assert output =~ "4. {:gen, :gigalixir}  [deploy] if :gigalixir"

      assert output =~
               "5. {:starter, Not.Loaded.Starter}  [standard_app]  (Not.Loaded.Starter is not loaded"

      assert output =~ "Flags: --gigalixir --oban-pro"

      assert output =~
               "Duplicates dropped (first occurrence wins):\n  {:gen, :sort_deps}  [finish]"
    end

    test "unknown profiles raise, listing the available ones", %{path: path} do
      assert_raise Mix.Error, ~r/Unknown profile: nope.*Available profiles: base, deploy/s, fn ->
        List.Steps.run(["-c", path, "nope"])
      end
    end

    test "cycles raise with the path", %{path: path} do
      assert_raise Mix.Error, "Include cycle: loop_a -> loop_b -> loop_a", fn ->
        List.Steps.run(["-c", path, "loop_a"])
      end
    end

    test "requires exactly one profile", %{path: path} do
      assert_raise Mix.Error, ~r/Usage/, fn -> List.Steps.run(["-c", path]) end
      assert_raise Mix.Error, ~r/Usage/, fn -> List.Steps.run(["-c", path, "a", "b"]) end
    end

    test "a missing config file raises", %{tmp_dir: dir} do
      assert_raise Mix.Error, ~r/Config file not found/, fn ->
        List.Steps.run(["-c", Path.join(dir, "nope.exs"), "base"])
      end
    end
  end
end
