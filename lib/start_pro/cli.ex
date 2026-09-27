defmodule StartPro.CLI do
  @moduledoc false
  # Helpers shared by the mix start_pro.* tasks: option parsing, loading and
  # resolving a profile (raising on error), and rendering entries.

  alias StartPro.{Config, Error, Resolver}

  @config_switches [config: :string]
  @config_aliases [c: :config]

  # Options of mix start_pro.run and Igniter's global switches that take a
  # value; every other --switch is a boolean.
  @value_switches ["--config", "-c", "--scribe", "--only"]

  @doc "Parses argv strictly with `-c/--config` plus `extra` switches."
  def parse!(argv, extra \\ []) do
    OptionParser.parse!(argv, strict: @config_switches ++ extra, aliases: @config_aliases)
  end

  @doc """
  Pre-scans argv for `--config` and the positional arguments without knowing
  the profile's flags yet. `OptionParser` would take a positional following
  an unknown `--flag` as that flag's value.
  """
  def prescan(argv), do: prescan(argv, nil, [])

  defp prescan([], config, positional), do: {config, Enum.reverse(positional)}
  defp prescan(["--" | rest], config, positional), do: {config, Enum.reverse(positional, rest)}

  defp prescan([switch, value | rest], config, positional) when switch in @value_switches do
    config = if switch in ["--config", "-c"], do: value, else: config
    prescan(rest, config, positional)
  end

  defp prescan(["--config=" <> value | rest], _config, positional),
    do: prescan(rest, value, positional)

  defp prescan(["-" <> _ | rest], config, positional), do: prescan(rest, config, positional)
  defp prescan([arg | rest], config, positional), do: prescan(rest, config, [arg | positional])

  @doc "Resolves the config path and loads it, raising on error."
  def load!(config) do
    path = Config.path(config)
    {path, ok!(Config.load(path))}
  end

  @doc """
  Loads the config, finds profile `name` and resolves it with `flags`.

  Returns `%{path:, profiles:, name:, result:}`.
  """
  def load_profile!(config, name, flags \\ :all) do
    {path, profiles} = load!(config)
    name = ok!(Config.find_profile(profiles, name))
    result = ok!(Resolver.resolve(profiles, name, flags: flags))
    %{path: path, profiles: profiles, name: name, result: result}
  end

  @doc "Unwraps `{:ok, value}` or raises `Mix.Error` with the formatted reason."
  def ok!({:ok, value}), do: value
  def ok!(:ok), do: :ok
  def ok!({:error, reason}), do: Mix.raise(Error.message(reason))

  @doc "Renders numbered entries: `  4. {:add, :oban}  [chat_app] if :oban`."
  def render_entries(entries) do
    width = entries |> length() |> Integer.to_string() |> String.length()

    entries
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {entry, n} ->
      number = n |> Integer.to_string() |> String.pad_leading(width)
      "  #{number}. " <> render_entry(entry)
    end)
  end

  @doc "Renders one entry without a number."
  def render_entry(%{step: step, origin: origin, gates: gates}) do
    [
      Resolver.format_step(step),
      "  [#{Error.name(origin)}]",
      gates(gates),
      unexpanded(step)
    ]
    |> IO.iodata_to_binary()
  end

  @doc "Formats flags as `--flag-name` switches."
  def switches(flags), do: Enum.map_join(flags, " ", &switch/1)
  def switch(flag), do: "--" <> String.replace(Atom.to_string(flag), "_", "-")

  defp gates([]), do: ""
  defp gates(gates), do: " if " <> Enum.map_join(gates, " and ", &inspect/1)

  defp unexpanded({:starter, module}), do: unexpanded_note(module)
  defp unexpanded({:starter, module, _opts}), do: unexpanded_note(module)
  defp unexpanded(_step), do: ""

  defp unexpanded_note(module) do
    "  (#{inspect(module)} is not loaded here; expanded at run time)"
  end
end
