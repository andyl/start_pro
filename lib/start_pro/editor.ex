defmodule StartPro.Editor do
  @moduledoc """
  Opens a file in the user's editor.

  The editor runs through a `Port` with `:nouse_stdio`, so terminal editors
  (vim, nvim, nano) inherit the TTY. GUI editors must be told to wait, for
  example `EDITOR="code --wait"`.
  """

  @doc """
  Returns the editor command from `$EDITOR`, then `$VISUAL`, or `nil`.
  """
  @spec command() :: String.t() | nil
  def command do
    Enum.find_value(["EDITOR", "VISUAL"], fn var ->
      case System.get_env(var) do
        nil -> nil
        value -> if String.trim(value) == "", do: nil, else: value
      end
    end)
  end

  @doc """
  Opens `file` with `editor` and waits for it to exit.

  The launcher can be replaced (for tests) with the `:editor_launcher`
  application env: a function `(editor, file) -> exit_status`.
  """
  @spec open(String.t(), Path.t()) :: :ok | {:error, {:editor_failed, String.t(), integer()}}
  def open(editor, file) do
    launcher = Application.get_env(:start_pro, :editor_launcher, &launch/2)

    case launcher.(editor, file) do
      0 -> :ok
      status -> {:error, {:editor_failed, editor, status}}
    end
  end

  @doc false
  def launch(editor, file) do
    sh = System.find_executable("sh") || "/bin/sh"

    port =
      Port.open({:spawn_executable, sh}, [
        :nouse_stdio,
        :exit_status,
        args: ["-c", ~s(#{editor} "$1"), "--", file]
      ])

    receive do
      {^port, {:exit_status, status}} -> status
    end
  end
end
