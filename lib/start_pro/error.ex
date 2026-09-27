defmodule StartPro.Error do
  @moduledoc """
  Formats the `{:error, reason}` values returned by `start_pro`'s modules.

  Library functions return errors as data; Mix tasks pass the reason to
  `message/1` and raise with `Mix.raise/1`.
  """

  @type reason ::
          {:config_not_found, Path.t()}
          | {:config_eval, Path.t(), Exception.t()}
          | {:invalid_shape, term()}
          | {:invalid_profile, atom(), term()}
          | {:duplicate_profile, atom()}
          | {:unknown_profile, String.t(), [atom()]}
          | {:missing_use, atom(), atom(), [atom()]}
          | {:invalid_use, atom(), term()}
          | {:cycle, [atom()]}
          | {:not_a_starter, module()}
          | {:missing_module, atom(), module()}
          | {:reserved_flag, atom()}
          | {:editor_failed, String.t(), integer()}

  @doc "Returns a human-readable message for an error reason."
  @spec message(reason() | term()) :: String.t()
  def message({:config_not_found, path}) do
    """
    Config file not found: #{path}

    Create it with:

        mix start_pro.config.init
    """
  end

  def message({:config_eval, path, exception}) do
    "Could not evaluate config file #{path}:\n\n" <> Exception.message(exception)
  end

  def message({:invalid_shape, term}) do
    """
    The config file must evaluate to a keyword list (or an atom-keyed map) of
    profile_name => [step], got:

        #{inspect(term, pretty: true, limit: 10)}
    """
  end

  def message({:invalid_profile, name, term}) do
    "Profile #{name(name)} must be a list of steps, got: #{inspect(term, limit: 10)}"
  end

  def message({:duplicate_profile, name}) do
    "Profile #{name(name)} is defined more than once in the config file"
  end

  def message({:unknown_profile, name, available}) do
    "Unknown profile: #{name}\n\n" <> available(available)
  end

  def message({:missing_use, from, target, available}) do
    "Profile #{name(from)} uses #{name(target)}, which is not defined\n\n" <>
      available(available)
  end

  def message({:invalid_use, from, term}) do
    """
    Invalid include in #{name(from)}: #{inspect(term)}

    Expected {:use, :profile_name} or {:use, :profile_name, if: :flag}.
    """
  end

  def message({:cycle, path}) do
    "Include cycle: " <> Enum.map_join(path, " -> ", &name/1)
  end

  def message({:not_a_starter, module}) do
    "#{inspect(module)} is included with {:starter, #{inspect(module)}} but has no steps/0"
  end

  def message({:missing_module, from, module}) do
    """
    Profile #{name(from)} names #{inspect(module)}, which is not available in this app.

    Custom steps and starter modules must be dependencies of the target app.
    """
  end

  def message({:reserved_flag, flag}) do
    "Flag :#{flag} is reserved by mix start_pro.run; rename the if: :#{flag} in your profiles"
  end

  def message({:editor_failed, editor, status}) do
    "Editor #{inspect(editor)} exited with status #{status}"
  end

  def message(other), do: "start_pro error: #{inspect(other)}"

  @doc """
  Formats a profile name or module for display: profiles print bare
  (`base`), modules print as modules (`MyTeam.Baseline`).
  """
  @spec name(atom() | String.t()) :: String.t()
  def name(name) when is_binary(name), do: name

  def name(name) when is_atom(name) do
    case Atom.to_string(name) do
      "Elixir." <> _ -> inspect(name)
      string -> string
    end
  end

  defp available([]), do: "No profiles are defined."
  defp available(names), do: "Available profiles: " <> Enum.map_join(names, ", ", &name/1)
end
