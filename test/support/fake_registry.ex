defmodule Mix.Tasks.FakeReg.Gen.Hello do
  @moduledoc false
  # A registry step: {:gen, :hello, from: FakeReg}.
  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def igniter(igniter), do: Igniter.create_new_file(igniter, "hello.txt", "hello\n")
end
