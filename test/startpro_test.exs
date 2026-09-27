defmodule StartproTest do
  use ExUnit.Case
  doctest Startpro

  test "greets the world" do
    assert Startpro.hello() == :world
  end
end
