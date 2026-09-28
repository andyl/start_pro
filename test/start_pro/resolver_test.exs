defmodule StartPro.ResolverTest do
  use ExUnit.Case, async: true

  alias StartPro.Resolver
  alias StartPro.Test.{CyclicStarter, FakeStarter, NestedStarter, NotAStarter}

  defp resolve(profiles, name, flags \\ :all) do
    Resolver.resolve(profiles, name, flags: flags)
  end

  defp steps(profiles, name, flags \\ :all) do
    {:ok, result} = resolve(profiles, name, flags)
    Resolver.steps_only(result)
  end

  describe "expansion" do
    test "a profile with no includes" do
      assert steps([a: [{:add, :credo}, {:gen, :gitignore}]], :a) ==
               [{:add, :credo}, {:gen, :gitignore}]
    end

    test "an empty profile" do
      assert {:ok, %{steps: [], duplicates: [], gates: []}} = resolve([a: []], :a)
    end

    test "{:use, ...} expands in place" do
      profiles = [
        base: [{:remove, :topbar}, {:gen, :gitignore}],
        app: [{:add, :credo}, {:use, :base}, {:add, :oban}]
      ]

      assert steps(profiles, :app) ==
               [{:add, :credo}, {:remove, :topbar}, {:gen, :gitignore}, {:add, :oban}]
    end

    test "nested includes three levels deep" do
      profiles = [
        a: [{:use, :b}, {:add, :a}],
        b: [{:use, :c}, {:add, :b}],
        c: [{:use, :d}, {:add, :c}],
        d: [{:add, :d}]
      ]

      assert steps(profiles, :a) == [{:add, :d}, {:add, :c}, {:add, :b}, {:add, :a}]
    end

    test "a diamond expands once, at its first position, and is not a cycle" do
      profiles = [
        base: [{:gen, :gitignore}],
        left: [{:use, :base}, {:add, :left}],
        right: [{:use, :base}, {:add, :right}],
        app: [{:use, :left}, {:use, :right}]
      ]

      assert {:ok, %{duplicates: []} = result} = resolve(profiles, :app)

      assert Resolver.steps_only(result) ==
               [{:gen, :gitignore}, {:add, :left}, {:add, :right}]
    end

    test "origin annotations" do
      profiles = [base: [{:gen, :gitignore}], app: [{:use, :base}, {:add, :credo}]]
      {:ok, %{steps: entries}} = resolve(profiles, :app)

      assert entries == [
               %{step: {:gen, :gitignore}, origin: :base, gates: []},
               %{step: {:add, :credo}, origin: :app, gates: []}
             ]
    end
  end

  describe "de-duplication" do
    test "exact duplicates are dropped, first wins, and reported" do
      profiles = [
        finish: [{:gen, :sort_deps}],
        app: [{:gen, :sort_deps}, {:add, :credo}, {:use, :finish}]
      ]

      {:ok, result} = resolve(profiles, :app)
      assert Resolver.steps_only(result) == [{:gen, :sort_deps}, {:add, :credo}]
      assert result.duplicates == [%{step: {:gen, :sort_deps}, origin: :finish, gates: []}]
    end

    test "steps that differ only in if: are distinct" do
      assert steps([a: [{:add, :oban}, {:add, :oban, if: :oban}]], :a) ==
               [{:add, :oban}, {:add, :oban, if: :oban}]
    end
  end

  describe "gated includes" do
    @profiles [
      deploy: [{:gen, :gigalixir}],
      app: [{:add, :credo}, {:use, :deploy, if: :gigalixir}]
    ]

    test "with the flag on" do
      assert steps(@profiles, :app, gigalixir: true) == [{:add, :credo}, {:gen, :gigalixir}]
    end

    test "with the flag off" do
      assert steps(@profiles, :app, []) == [{:add, :credo}]
      assert steps(@profiles, :app, gigalixir: false) == [{:add, :credo}]
    end

    test ":all follows the gate and records it" do
      {:ok, result} = resolve(@profiles, :app)

      assert result.steps == [
               %{step: {:add, :credo}, origin: :app, gates: []},
               %{step: {:gen, :gigalixir}, origin: :deploy, gates: [:gigalixir]}
             ]

      assert result.gates == [:gigalixir]
    end

    test "nested gates accumulate" do
      profiles = [
        c: [{:add, :c}],
        b: [{:use, :c, if: :inner}],
        a: [{:use, :b, if: :outer}]
      ]

      {:ok, result} = resolve(profiles, :a)
      assert [%{step: {:add, :c}, gates: [:outer, :inner]}] = result.steps
      assert steps(profiles, :a, outer: true) == []
      assert steps(profiles, :a, outer: true, inner: true) == [{:add, :c}]
    end

    test "a gated-off include still expands through a later ungated use" do
      profiles = [
        base: [{:gen, :gitignore}],
        app: [{:use, :base, if: :early}, {:add, :credo}, {:use, :base}]
      ]

      assert steps(profiles, :app, []) == [{:add, :credo}, {:gen, :gitignore}]
      assert steps(profiles, :app, early: true) == [{:gen, :gitignore}, {:add, :credo}]
    end

    test "a cycle hidden behind a gate is caught by flags: :all" do
      profiles = [a: [{:use, :b, if: :f}], b: [{:use, :a}]]
      assert {:ok, _} = resolve(profiles, :a, [])
      assert {:error, {:cycle, [:a, :b, :a]}} = resolve(profiles, :a)
    end
  end

  describe "errors" do
    test "a direct cycle" do
      assert {:error, {:cycle, [:a, :a]}} = resolve([a: [{:use, :a}]], :a)
    end

    test "a three-node cycle reports the exact path" do
      profiles = [a: [{:use, :b}], b: [{:use, :c}], c: [{:use, :a}]]
      assert {:error, {:cycle, [:a, :b, :c, :a]}} = resolve(profiles, :a)
      assert {:error, {:cycle, [:b, :c, :a, :b]}} = resolve(profiles, :b)
    end

    test "a cycle that starts below the root" do
      profiles = [root: [{:use, :a}], a: [{:use, :b}], b: [{:use, :a}]]
      assert {:error, {:cycle, [:a, :b, :a]}} = resolve(profiles, :root)
    end

    test "a cycle through {:starter, M}" do
      profiles = [loop: [{:starter, CyclicStarter}]]
      assert {:error, {:cycle, [:loop, CyclicStarter, :loop]}} = resolve(profiles, :loop)

      assert StartPro.Error.message({:cycle, [:loop, CyclicStarter, :loop]}) ==
               "Include cycle: loop -> StartPro.Test.CyclicStarter -> loop"
    end

    test "a missing include target" do
      assert {:error, {:missing_use, :a, :nope, [:a]}} = resolve([a: [{:use, :nope}]], :a)
    end

    test "a missing include target behind an off gate is still caught by :all" do
      profiles = [a: [{:use, :nope, if: :f}]]
      assert {:ok, _} = resolve(profiles, :a, [])
      assert {:error, {:missing_use, :a, :nope, _}} = resolve(profiles, :a)
    end

    test "an unknown root profile" do
      assert {:error, {:unknown_profile, "b", [:a]}} = resolve([a: []], :b)
    end

    test "a malformed :use" do
      assert {:error, {:invalid_use, :a, {:use, "b"}}} = resolve([a: [{:use, "b"}]], :a)
    end

    test "a loaded module without steps/0" do
      assert {:error, {:not_a_starter, NotAStarter}} =
               resolve([a: [{:starter, NotAStarter}]], :a)
    end
  end

  describe "{:starter, M}" do
    test "expands M.steps() in place with M as origin" do
      {:ok, result} = resolve([a: [{:add, :credo}, {:starter, FakeStarter}]], :a)

      assert result.steps == [
               %{step: {:add, :credo}, origin: :a, gates: []},
               %{step: {:remove, :topbar}, origin: FakeStarter, gates: []},
               %{step: {:gen, :gitignore}, origin: FakeStarter, gates: []}
             ]
    end

    test "nested starters expand once" do
      profiles = [a: [{:starter, FakeStarter}, {:starter, NestedStarter}]]

      assert {:ok, %{duplicates: []} = result} = resolve(profiles, :a)

      assert Resolver.steps_only(result) ==
               [{:remove, :topbar}, {:gen, :gitignore}, {:add, :credo}]
    end

    test "gated starter includes" do
      profiles = [a: [{:starter, FakeStarter, if: :fake}]]
      assert steps(profiles, :a, []) == []
      assert steps(profiles, :a, fake: true) == [{:remove, :topbar}, {:gen, :gitignore}]
      assert {:ok, %{gates: [:fake]}} = resolve(profiles, :a)
    end

    test "an unloadable module passes through unexpanded" do
      profiles = [a: [{:starter, Not.Loaded.Starter, if: :x}, {:add, :credo}]]

      {:ok, result} = resolve(profiles, :a)

      assert Resolver.steps_only(result) == [
               {:starter, Not.Loaded.Starter, if: :x},
               {:add, :credo}
             ]

      assert Resolver.flags(result) == [:x]
    end
  end

  describe "helpers" do
    test "flags/1 combines gate flags with leaf if: flags" do
      profiles = [
        deploy: [{:gen, :gigalixir, if: :libcluster}],
        app: [{:add, :oban, if: :oban}, {:use, :deploy, if: :gigalixir}, {:task, "x", [], if: :t}]
      ]

      {:ok, result} = resolve(profiles, :app)
      assert Enum.sort(Resolver.flags(result)) == [:gigalixir, :libcluster, :oban, :t]
    end

    test "uses/2 lists direct includes in order" do
      profiles = [
        app: [{:use, :base}, {:add, :credo}, {:use, :deploy, if: :g}, {:starter, FakeStarter}]
      ]

      assert Resolver.uses(profiles, :app) == [
               {:profile, :base, nil},
               {:profile, :deploy, :g},
               {:starter, FakeStarter, nil}
             ]
    end

    test "active/2 drops steps whose own if: flag is off" do
      entries =
        for step <- [{:add, :credo}, {:add, :oban, if: :oban}, {:task, "t", ["--a"]}],
            do: %{step: step, origin: :a, gates: []}

      assert Resolver.active(entries, []) |> Resolver.steps_only() ==
               [{:add, :credo}, {:task, "t", ["--a"]}]

      assert length(Resolver.active(entries, oban: true)) == 3
    end

    test "validate_all/1 checks every profile" do
      assert :ok = Resolver.validate_all(a: [], b: [{:use, :a}])
      assert {:error, {:missing_use, :b, :c, _}} = Resolver.validate_all(a: [], b: [{:use, :c}])
    end
  end

  describe "registry steps" do
    test "stay as written, count their if: as a flag, and de-duplicate" do
      profiles = [
        a: [{:add, :ash, from: StartReg}, {:gen, :x, from: StartReg, if: :x}],
        b: [{:use, :a}, {:add, :ash, from: StartReg}, {:add, :ash}]
      ]

      assert {:ok, result} = resolve(profiles, :b)

      assert Resolver.steps_only(result) ==
               [{:add, :ash, from: StartReg}, {:gen, :x, from: StartReg, if: :x}, {:add, :ash}]

      assert [%{step: {:add, :ash, from: StartReg}, origin: :b}] = result.duplicates
      assert Resolver.flags(result) == [:x]
    end

    test "malformed registry steps in starter modules are rejected" do
      assert {:error, {:invalid_from, :a, _}} =
               resolve([a: [{:gen, :x, from: :nope}]], :a)
    end
  end
end
