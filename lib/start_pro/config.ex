defmodule StartPro.Config do
  @moduledoc """
  Locates, loads and validates the profiles config file.

  The path is resolved in this order, first match wins:

    1. the `-c`/`--config` option
    2. the `START_PRO_CONFIG` environment variable
    3. `$XDG_CONFIG_HOME/start_pro/profiles.exs`
    4. `~/.config/start_pro/profiles.exs`

  The file must evaluate to a keyword list, or a map with atom keys, of
  `profile_name => [step]`. Only `{:use, ...}` includes are validated here;
  every other step shape is left to `Starter.Runner`.

  > #### Warning {: .warning}
  >
  > The config file is evaluated as Elixir code.
  """

  @type profiles :: [{atom(), [Starter.step() | tuple()]}]

  @doc "Returns the config path, applying the precedence described above."
  @spec path(String.t() | nil) :: Path.t()
  def path(config \\ nil)
  def path(config) when is_binary(config) and config != "", do: Path.expand(config)

  def path(_config) do
    cond do
      env = present(System.get_env("START_PRO_CONFIG")) ->
        Path.expand(env)

      xdg = present(System.get_env("XDG_CONFIG_HOME")) ->
        Path.join([Path.expand(xdg), "start_pro", "profiles.exs"])

      true ->
        Path.expand("~/.config/start_pro/profiles.exs")
    end
  end

  @doc "Path of the default config template shipped in `priv/`."
  @spec template_path() :: Path.t()
  def template_path, do: Application.app_dir(:start_pro, "priv/templates/profiles.exs")

  @doc """
  Evaluates and validates the config file at `path`.

  Returns the profiles as an ordered list of `{name, steps}`.
  """
  @spec load(Path.t()) :: {:ok, profiles()} | {:error, StartPro.Error.reason()}
  def load(path) do
    if File.regular?(path) do
      with {:ok, term} <- eval(path), do: validate(term)
    else
      {:error, {:config_not_found, path}}
    end
  end

  @doc """
  Validates an evaluated config term and normalizes it to an ordered list of
  `{name, steps}`. Keyword lists keep their order.
  """
  @spec validate(term()) :: {:ok, profiles()} | {:error, StartPro.Error.reason()}
  def validate(term) when is_map(term), do: term |> Map.to_list() |> validate_list(term)
  def validate(term) when is_list(term), do: validate_list(term, term)
  def validate(term), do: {:error, {:invalid_shape, term}}

  @doc """
  Finds a profile by the name typed on the command line.

  Matches against `Atom.to_string/1` of each profile name, treating `-` and
  `_` as equal, so no atoms are created from user input.
  """
  @spec find_profile(profiles(), String.t() | atom()) ::
          {:ok, atom()} | {:error, StartPro.Error.reason()}
  def find_profile(profiles, name) when is_atom(name),
    do: find_profile(profiles, Atom.to_string(name))

  def find_profile(profiles, name) when is_binary(name) do
    wanted = normalize(name)

    case Enum.find(profiles, fn {key, _} -> normalize(Atom.to_string(key)) == wanted end) do
      {key, _steps} -> {:ok, key}
      nil -> {:error, {:unknown_profile, name, Keyword.keys(profiles)}}
    end
  end

  defp normalize(name), do: String.replace(name, "-", "_")

  defp present(nil), do: nil
  defp present(""), do: nil
  defp present(value), do: value

  defp eval(path) do
    {term, _binding} = Code.eval_file(path)
    {:ok, term}
  rescue
    exception -> {:error, {:config_eval, path, exception}}
  end

  defp validate_list(pairs, original) do
    if Enum.all?(pairs, &match?({key, _} when is_atom(key), &1)) do
      Enum.reduce_while(pairs, {:ok, [], MapSet.new()}, fn {name, steps}, {:ok, acc, seen} ->
        cond do
          MapSet.member?(seen, name) ->
            {:halt, {:error, {:duplicate_profile, name}}}

          not is_list(steps) ->
            {:halt, {:error, {:invalid_profile, name, steps}}}

          invalid = Enum.find(steps, &invalid_use?/1) ->
            {:halt, {:error, {:invalid_use, name, invalid}}}

          true ->
            {:cont, {:ok, [{name, steps} | acc], MapSet.put(seen, name)}}
        end
      end)
      |> case do
        {:ok, acc, _seen} -> {:ok, Enum.reverse(acc)}
        error -> error
      end
    else
      {:error, {:invalid_shape, original}}
    end
  end

  @doc false
  # True for a {:use, ...} tuple that is not {:use, atom} or
  # {:use, atom, if: atom}. Non-:use steps are never invalid here.
  def invalid_use?({:use, target}), do: not is_atom(target)

  def invalid_use?({:use, target, opts}) do
    not (is_atom(target) and valid_use_opts?(opts))
  end

  def invalid_use?(step) when is_tuple(step) and tuple_size(step) > 0, do: elem(step, 0) == :use
  def invalid_use?(_step), do: false

  defp valid_use_opts?(opts) do
    is_list(opts) and Keyword.keyword?(opts) and Keyword.keys(opts) -- [:if] == [] and
      is_atom(Keyword.get(opts, :if)) and not is_nil(Keyword.get(opts, :if)) and
      not is_boolean(Keyword.get(opts, :if))
  end
end
