defmodule StartPro.Resolver do
  @moduledoc """
  Expands a profile's includes into one flat, acyclic, de-duplicated step
  list.

  Two kinds of step are expanded in place:

    * `{:use, :name}` / `{:use, :name, if: :flag}` - another profile
    * `{:starter, Module}` / `{:starter, Module, if: :flag}` - a `Starter`
      module's `steps/0`

  Every other step is a leaf and is emitted as an entry:

      %{step: {:add, :credo}, origin: :tooling, gates: [:dev_tools]}

  `origin` is the profile (or starter module) the step came from, and `gates`
  lists the `if:` flags of the includes it was reached through.

  ## Rules

    * **Include-once.** A profile or starter module is expanded at most once
      per resolution; later includes of it are no-ops. A diamond is not a
      cycle.
    * **No cycles.** Re-entering an include that is still being expanded
      returns `{:error, {:cycle, path}}`.
    * **De-duplication.** After flattening, a step equal to an earlier step is
      dropped (first occurrence wins) and reported in `duplicates`. Steps that
      differ only in their `if:` are distinct.
    * **Unloadable starters.** `{:starter, M}` where `M` cannot be loaded is
      passed through unexpanded, for `Starter.Runner` to expand at run time.

  ## Flags

  The `:flags` option decides how gated includes are treated:

    * `flags: :all` (the default) follows every gated include. Use it for
      validation, listing, and computing the flag schema.
    * `flags: keyword` follows a gated include only when its flag is true. A
      skipped include is *not* marked as expanded, so a later ungated include
      of the same profile still expands it.

  Leaf steps keep their own `if:` options either way; `Starter.Runner`
  evaluates those.
  """

  alias StartPro.Error

  @type entry :: %{step: term(), origin: atom(), gates: [atom()]}
  @type result :: %{steps: [entry()], duplicates: [entry()], gates: [atom()]}
  @type include :: {:profile | :starter, atom(), atom() | nil}

  @doc """
  Resolves profile `name` from `profiles` (a list of `{name, steps}`).

  Returns `{:ok, %{steps: entries, duplicates: entries, gates: flags}}`, where
  `gates` lists every include flag encountered.
  """
  @spec resolve(StartPro.Config.profiles(), atom(), keyword()) ::
          {:ok, result()} | {:error, Error.reason()}
  def resolve(profiles, name, opts \\ []) do
    state = %{
      profiles: Map.new(profiles),
      names: Enum.map(profiles, &elem(&1, 0)),
      flags: Keyword.get(opts, :flags, :all),
      stack: [],
      done: MapSet.new(),
      entries: [],
      gates: []
    }

    if Map.has_key?(state.profiles, name) do
      with {:ok, state} <- visit({:profile, name}, [], state) do
        {steps, duplicates} = dedupe(Enum.reverse(state.entries))

        {:ok,
         %{steps: steps, duplicates: duplicates, gates: Enum.uniq(Enum.reverse(state.gates))}}
      end
    else
      {:error, {:unknown_profile, Error.name(name), state.names}}
    end
  end

  @doc """
  Resolves every profile with `flags: :all`, returning the first error.
  Used to validate a whole config file.
  """
  @spec validate_all(StartPro.Config.profiles()) :: :ok | {:error, Error.reason()}
  def validate_all(profiles) do
    Enum.reduce_while(profiles, :ok, fn {name, _steps}, :ok ->
      case resolve(profiles, name, flags: :all) do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @doc """
  Returns the direct includes of profile `name`, in order, as
  `{:profile | :starter, target, flag_or_nil}`.
  """
  @spec uses(StartPro.Config.profiles(), atom()) :: [include()]
  def uses(profiles, name) do
    profiles
    |> Keyword.get(name, [])
    |> Enum.flat_map(fn
      {:use, target} -> [{:profile, target, nil}]
      {:use, target, opts} when is_list(opts) -> [{:profile, target, opts[:if]}]
      {:starter, module} -> [{:starter, module, nil}]
      {:starter, module, opts} when is_list(opts) -> [{:starter, module, opts[:if]}]
      _step -> []
    end)
  end

  @doc """
  Returns every flag a resolved profile understands: the include gates plus
  the `if:` flags of the leaf steps (via `Starter.flags/1`).
  """
  @spec flags(result()) :: [atom()]
  def flags(%{steps: entries, gates: gates}) do
    leaf_flags =
      Enum.flat_map(entries, fn
        # Unexpanded (unloadable) starters: only the include's own flag is
        # knowable, and Starter.flags/1 would call steps/0 on them.
        %{step: {:starter, _module} = step} -> List.wrap(own_flag(step))
        %{step: {:starter, _module, _opts} = step} -> List.wrap(own_flag(step))
        %{step: step} -> Starter.flags([step])
      end)

    Enum.uniq(gates ++ leaf_flags)
  end

  @doc "Strips entry metadata, returning the plain step list."
  @spec steps_only(result() | [entry()]) :: [term()]
  def steps_only(%{steps: entries}), do: steps_only(entries)
  def steps_only(entries) when is_list(entries), do: Enum.map(entries, & &1.step)

  @doc """
  Drops entries whose own `if:` flag is off in `opts`, leaving the steps that
  will actually run.
  """
  @spec active([entry()], keyword()) :: [entry()]
  def active(entries, opts) do
    Enum.filter(entries, fn %{step: step} ->
      case own_flag(step) do
        nil -> true
        flag -> Keyword.get(opts, flag, false) == true
      end
    end)
  end

  @doc """
  Formats a step as it is written in a config file, e.g.
  `{:add, :oban, if: :oban}` rather than `inspect/1`'s `[if: :oban]`.
  """
  @spec format_step(term()) :: String.t()
  def format_step(step), do: step |> Macro.escape() |> Macro.to_string()

  @doc "Returns a step's own `if:` flag, or `nil`."
  @spec own_flag(term()) :: atom() | nil
  def own_flag(step) when is_tuple(step) and tuple_size(step) >= 2 do
    case elem(step, tuple_size(step) - 1) do
      [{_, _} | _] = opts -> if Keyword.keyword?(opts), do: opts[:if]
      _ -> nil
    end
  end

  def own_flag(_step), do: nil

  # -- walk -------------------------------------------------------------

  defp visit(node, gates, state) do
    if node in state.stack do
      path = state.stack |> Enum.reverse() |> Enum.drop_while(&(&1 != node))
      {:error, {:cycle, Enum.map(path ++ [node], &elem(&1, 1))}}
    else
      with {:ok, steps} <- children(node, state) do
        origin = elem(node, 1)
        state = %{state | stack: [node | state.stack]}

        steps
        |> Enum.reduce_while({:ok, state}, fn step, {:ok, state} ->
          case step(step, origin, gates, state) do
            {:ok, state} -> {:cont, {:ok, state}}
            error -> {:halt, error}
          end
        end)
        |> case do
          {:ok, state} ->
            {:ok, %{state | stack: tl(state.stack), done: MapSet.put(state.done, node)}}

          error ->
            error
        end
      end
    end
  end

  defp children({:profile, name}, state), do: {:ok, Map.fetch!(state.profiles, name)}

  defp children({:starter, module}, _state) do
    case module.steps() do
      steps when is_list(steps) -> {:ok, steps}
      _other -> {:error, {:not_a_starter, module}}
    end
  end

  defp step({:use, target} = step, origin, gates, state) do
    if StartPro.Config.invalid_use?(step),
      do: {:error, {:invalid_use, origin, step}},
      else: include({:profile, target}, nil, step, origin, gates, state)
  end

  defp step({:use, target, opts} = step, origin, gates, state) do
    if StartPro.Config.invalid_use?(step),
      do: {:error, {:invalid_use, origin, step}},
      else: include({:profile, target}, opts[:if], step, origin, gates, state)
  end

  defp step({:starter, module} = step, origin, gates, state) when is_atom(module) do
    include({:starter, module}, nil, step, origin, gates, state)
  end

  defp step({:starter, module, opts} = step, origin, gates, state)
       when is_atom(module) and is_list(opts) do
    include({:starter, module}, opts[:if], step, origin, gates, state)
  end

  defp step(step, origin, gates, state) do
    cond do
      StartPro.Config.invalid_use?(step) -> {:error, {:invalid_use, origin, step}}
      StartPro.Registry.invalid?(step) -> {:error, {:invalid_from, origin, step}}
      true -> {:ok, emit(state, step, origin, gates)}
    end
  end

  defp include(node, flag, step, origin, gates, state) do
    cond do
      flag && state.flags != :all && Keyword.get(state.flags, flag, false) != true ->
        {:ok, state}

      MapSet.member?(state.done, node) ->
        {:ok, state}

      true ->
        expand(node, flag, step, origin, gates, state)
    end
  end

  defp expand({:profile, target} = node, flag, _step, origin, gates, state) do
    if Map.has_key?(state.profiles, target) do
      visit(node, gates ++ List.wrap(flag), record_gate(state, flag))
    else
      {:error, {:missing_use, origin, target, state.names}}
    end
  end

  defp expand({:starter, module} = node, flag, step, origin, gates, state) do
    cond do
      not Code.ensure_loaded?(module) ->
        {:ok, emit(state, step, origin, gates)}

      not function_exported?(module, :steps, 0) ->
        {:error, {:not_a_starter, module}}

      true ->
        visit(node, gates ++ List.wrap(flag), record_gate(state, flag))
    end
  end

  defp record_gate(state, nil), do: state
  defp record_gate(state, flag), do: %{state | gates: [flag | state.gates]}

  defp emit(state, step, origin, gates) do
    %{state | entries: [%{step: step, origin: origin, gates: gates} | state.entries]}
  end

  defp dedupe(entries) do
    {kept, dropped, _seen} =
      Enum.reduce(entries, {[], [], MapSet.new()}, fn entry, {kept, dropped, seen} ->
        if MapSet.member?(seen, entry.step) do
          {kept, [entry | dropped], seen}
        else
          {[entry | kept], dropped, MapSet.put(seen, entry.step)}
        end
      end)

    {Enum.reverse(kept), Enum.reverse(dropped)}
  end
end
