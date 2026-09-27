defmodule Mix.Tasks.StartPro.Git.Commit do
  @moduledoc false
  # Internal: queued by mix start_pro.run to run after its changes are applied.
  #
  #     mix start_pro.git.commit --message-file PATH
  #
  # Stages everything, commits with the message in PATH, then deletes PATH.
  # A run that changed nothing is reported, not treated as a failure.

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {opts, _args} = OptionParser.parse!(argv, strict: [message_file: :string, yes: :boolean])

    file = opts[:message_file] || Mix.raise("Usage: mix start_pro.git.commit --message-file PATH")

    try do
      case StartPro.Git.commit(File.cwd!(), file) do
        {:ok, _output} ->
          subject = file |> File.read!() |> String.split("\n", parts: 2) |> hd()
          Mix.shell().info("start_pro: committed \"#{subject}\"")

        :nothing_to_commit ->
          Mix.shell().info("start_pro: nothing to commit, the profile made no changes")

        {:error, output} ->
          Mix.raise("start_pro: git commit failed:\n\n" <> output)
      end
    after
      File.rm(file)
    end
  end
end
