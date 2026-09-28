defmodule StartPro.Registry do
  @moduledoc """
  Registry steps: `{kind, :name, from: Registry}`.

  A registry is a package of Igniter step tasks laid out as
  `Mix.Tasks.<Registry>.<Kind>.<Name>`, such as
  [start_reg](https://github.com/andyl/start_reg). A registry step names one
  of them by kind and name instead of by module:

      {:add, :ash, from: StartReg}
      # => Mix.Tasks.StartReg.Add.Ash

      {:gen, :xp_mix_completions, from: StartReg, if: :completions}
      # => {Mix.Tasks.StartReg.Gen.XpMixCompletions, if: :completions}

  `kind` is `:add`, `:gen` or `:remove`, and `from:` is the registry's
  module prefix. Upstream `starter` doesn't know this form, so `start_pro`
  translates it to a module step (`translate/1`) just before handing the
  list to `Starter.Runner`. Everywhere else, such as listings, the commit
  message and de-duplication, the step keeps the form it was written in.
  """

  @kinds [:add, :gen, :remove]

  @doc "True for a step that carries a `from:` option."
  @spec registry_step?(term()) :: boolean()
  def registry_step?({_kind, _name, opts}) when is_list(opts) do
    Keyword.keyword?(opts) and Keyword.has_key?(opts, :from)
  end

  def registry_step?(_step), do: false

  @doc """
  True for a registry step that is malformed: an unsupported kind, a
  non-atom name, a `from:` that isn't a module, an option other than
  `from:`/`if:`, or a boolean `if:`. Steps without `from:` are never invalid
  here.
  """
  @spec invalid?(term()) :: boolean()
  def invalid?({kind, name, opts} = step) do
    registry_step?(step) and
      not (kind in @kinds and is_atom(name) and not is_nil(name) and
             module?(opts[:from]) and Keyword.keys(opts) -- [:from, :if] == [] and
             valid_if?(opts))
  end

  def invalid?(_step), do: false

  @doc """
  Returns the task module a registry step names, e.g.
  `Mix.Tasks.StartReg.Add.AshPhoenix` for `{:add, :ash_phoenix, from: StartReg}`.
  """
  @spec module(atom(), atom(), module()) :: module()
  def module(kind, name, registry) do
    Module.concat([Mix.Tasks, registry, camelize(kind), camelize(name)])
  end

  @doc """
  Translates a registry step to the module step `Starter.Runner` understands,
  keeping its `if:`. Any other step is returned unchanged.
  """
  @spec translate(term()) :: term()
  def translate({kind, name, opts} = step) do
    if registry_step?(step) do
      module = module(kind, name, opts[:from])

      case Keyword.delete(opts, :from) do
        [] -> module
        rest -> {module, rest}
      end
    else
      step
    end
  end

  def translate(step), do: step

  defp camelize(atom), do: atom |> Atom.to_string() |> Macro.camelize()

  defp module?(atom) when is_atom(atom), do: match?("Elixir." <> _, Atom.to_string(atom))
  defp module?(_other), do: false

  defp valid_if?(opts) do
    case Keyword.fetch(opts, :if) do
      :error -> true
      {:ok, flag} -> is_atom(flag) and not is_nil(flag) and not is_boolean(flag)
    end
  end
end
