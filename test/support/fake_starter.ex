defmodule StartPro.Test.FakeStarter do
  @moduledoc false
  @behaviour Starter

  @impl Starter
  def steps, do: [{:remove, :topbar}, {:gen, :gitignore}]
end

defmodule StartPro.Test.NestedStarter do
  @moduledoc false
  @behaviour Starter

  @impl Starter
  def steps, do: [{:starter, StartPro.Test.FakeStarter}, {:add, :credo}]
end

defmodule StartPro.Test.CyclicStarter do
  @moduledoc false
  @behaviour Starter

  # Includes the :loop profile, which includes this starter again.
  @impl Starter
  def steps, do: [{:use, :loop}]
end

defmodule StartPro.Test.NotAStarter do
  @moduledoc false
end
