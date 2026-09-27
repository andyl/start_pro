defmodule Startpro.Test.FakeStarter do
  @moduledoc false
  @behaviour Starter

  @impl Starter
  def steps, do: [{:remove, :topbar}, {:gen, :gitignore}]
end

defmodule Startpro.Test.NestedStarter do
  @moduledoc false
  @behaviour Starter

  @impl Starter
  def steps, do: [{:starter, Startpro.Test.FakeStarter}, {:add, :credo}]
end

defmodule Startpro.Test.CyclicStarter do
  @moduledoc false
  @behaviour Starter

  # Includes the :loop profile, which includes this starter again.
  @impl Starter
  def steps, do: [{:use, :loop}]
end

defmodule Startpro.Test.NotAStarter do
  @moduledoc false
end
