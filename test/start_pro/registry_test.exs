defmodule StartPro.RegistryTest do
  use ExUnit.Case, async: true

  alias StartPro.Registry

  describe "translate/1" do
    test "maps a registry step to its task module" do
      assert Registry.translate({:add, :ash, from: StartReg}) == Mix.Tasks.StartReg.Add.Ash

      assert Registry.translate({:gen, :xp_mix_completions, from: StartReg}) ==
               Mix.Tasks.StartReg.Gen.XpMixCompletions

      assert Registry.translate({:remove, :topbar, from: My.Reg}) ==
               Mix.Tasks.My.Reg.Remove.Topbar
    end

    test "keeps the if: flag" do
      assert Registry.translate({:add, :ash_phoenix, if: :web, from: StartReg}) ==
               {Mix.Tasks.StartReg.Add.AshPhoenix, [if: :web]}
    end

    test "leaves other steps alone" do
      for step <- [{:add, :credo}, {:add, :oban, if: :oban}, My.Step, {:queue, "x", []}] do
        assert Registry.translate(step) == step
      end
    end
  end

  describe "invalid?/1" do
    test "accepts well-formed registry steps and ignores other steps" do
      refute Registry.invalid?({:add, :ash, from: StartReg})
      refute Registry.invalid?({:gen, :ash, from: StartReg, if: :ash})
      refute Registry.invalid?({:add, :oban, if: :oban})
      refute Registry.invalid?({:weird, 1, 2})
    end

    test "rejects malformed registry steps" do
      assert Registry.invalid?({:install, :ash, from: StartReg})
      assert Registry.invalid?({:starter, :ash, from: StartReg})
      assert Registry.invalid?({:add, "ash", from: StartReg})
      assert Registry.invalid?({:add, :ash, from: :start_reg})
      assert Registry.invalid?({:add, :ash, from: nil})
      assert Registry.invalid?({:add, :ash, from: StartReg, unless: :x})
      assert Registry.invalid?({:add, :ash, from: StartReg, if: true})
    end
  end
end
