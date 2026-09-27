defmodule Startpro.ConfigTest do
  # Changes STARTPRO_CONFIG / XDG_CONFIG_HOME.
  use ExUnit.Case, async: false

  alias Startpro.Config

  @fixtures Path.expand("../support/fixtures", __DIR__)

  defp fixture(name), do: Path.join(@fixtures, name)

  describe "load/1" do
    test "loads a keyword list, keeping order" do
      assert {:ok, profiles} = Config.load(fixture("keyword.exs"))
      assert Keyword.keys(profiles) == [:base, :app, :deploy]
      assert profiles[:base] == [{:remove, :daisy_ui}, {:gen, :gitignore}]
    end

    test "loads an atom-keyed map" do
      assert {:ok, profiles} = Config.load(fixture("map.exs"))
      assert Enum.sort(Keyword.keys(profiles)) == [:app, :base]
    end

    test "missing path and directory are not found" do
      missing = fixture("nope.exs")
      assert {:error, {:config_not_found, ^missing}} = Config.load(missing)
      assert {:error, {:config_not_found, _}} = Config.load(@fixtures)
    end

    test "syntax and runtime errors are rescued" do
      assert {:error, {:config_eval, _, %TokenMissingError{}}} =
               Config.load(fixture("syntax_error.exs"))

      assert {:error, {:config_eval, _, %SyntaxError{}}} =
               Config.load(fixture("syntax_error2.exs"))

      assert {:error, {:config_eval, _, %RuntimeError{}}} = Config.load(fixture("raises.exs"))
    end

    test "rejects wrong shapes" do
      assert {:error, {:invalid_shape, nil}} = Config.load(fixture("empty.exs"))
      assert {:error, {:invalid_profile, :base, _}} = Config.load(fixture("non_list.exs"))
      assert {:error, {:invalid_shape, _}} = Config.load(fixture("string_key.exs"))
      assert {:error, {:duplicate_profile, :base}} = Config.load(fixture("duplicate.exs"))
    end

    test "rejects malformed :use tuples" do
      assert {:error, {:invalid_use, :base, {:use, "other"}}} =
               Config.load(fixture("bad_use.exs"))

      assert {:error, {:invalid_use, :base, _}} = Config.load(fixture("bad_use_if.exs"))
    end
  end

  describe "validate/1" do
    test "leaves non-:use steps to the runner" do
      assert {:ok, [a: [{:weird, 1, 2, 3}]]} = Config.validate(a: [{:weird, 1, 2, 3}])
    end

    test "rejects :use with unknown options or a boolean flag" do
      assert {:error, {:invalid_use, :a, _}} = Config.validate(a: [{:use, :b, unless: :x}])
      assert {:error, {:invalid_use, :a, _}} = Config.validate(a: [{:use, :b, if: true}])
      assert {:error, {:invalid_use, :a, _}} = Config.validate(a: [{:use, :b, :c, :d}])
    end
  end

  describe "find_profile/2" do
    @profiles [standard_app: [], base: []]

    test "matches names, treating - and _ as equal" do
      assert {:ok, :standard_app} = Config.find_profile(@profiles, "standard_app")
      assert {:ok, :standard_app} = Config.find_profile(@profiles, "standard-app")
    end

    test "unknown names list the available profiles" do
      assert {:error, {:unknown_profile, "nope", [:standard_app, :base]}} =
               Config.find_profile(@profiles, "nope")
    end
  end

  describe "path/1" do
    setup do
      saved =
        for var <- ~w(STARTPRO_CONFIG XDG_CONFIG_HOME), into: %{}, do: {var, System.get_env(var)}

      on_exit(fn ->
        Enum.each(saved, fn
          {var, nil} -> System.delete_env(var)
          {var, value} -> System.put_env(var, value)
        end)
      end)

      System.delete_env("STARTPRO_CONFIG")
      System.delete_env("XDG_CONFIG_HOME")
      :ok
    end

    test "applies the precedence order" do
      assert Config.path(nil) == Path.expand("~/.config/startpro/profiles.exs")

      System.put_env("XDG_CONFIG_HOME", "/xdg")
      assert Config.path(nil) == "/xdg/startpro/profiles.exs"

      System.put_env("STARTPRO_CONFIG", "/env/p.exs")
      assert Config.path(nil) == "/env/p.exs"

      assert Config.path("/flag/p.exs") == "/flag/p.exs"
    end

    test "empty environment variables are ignored" do
      System.put_env("STARTPRO_CONFIG", "")
      System.put_env("XDG_CONFIG_HOME", "")
      assert Config.path(nil) == Path.expand("~/.config/startpro/profiles.exs")
    end
  end
end
