defmodule Startpro.Starter do
  @moduledoc """
  The engine adapter: a fixed `Starter` module whose steps are whatever list
  `run/3` was given.

  `Starter.Runner.run/3` takes a *module* and calls its `steps/0`. Rather than
  compiling a module per run, this one reads the resolved list from
  `:persistent_term`, which `run/3` sets just before calling the runner and
  erases afterwards. This module is the only coupling to upstream runner
  internals.
  """

  @behaviour Starter

  @key {Startpro, :steps}

  @impl Starter
  def steps, do: :persistent_term.get(@key, [])

  @doc """
  Runs `steps` against `igniter` with `Starter.Runner`, evaluating leaf `if:`
  flags against `opts`.
  """
  @spec run(Igniter.t(), [Starter.step()], keyword()) :: Igniter.t()
  def run(igniter, steps, opts) when is_list(steps) do
    :persistent_term.put(@key, steps)

    try do
      Starter.Runner.run(igniter, __MODULE__, opts)
    after
      :persistent_term.erase(@key)
    end
  end
end
