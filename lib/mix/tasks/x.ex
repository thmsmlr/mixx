defmodule Mix.Tasks.X do
  use Mix.Task

  @shortdoc "Executes remote Mix tasks via mixx"
  @moduledoc """
  Entry point for `mix x`. Delegates argument parsing and execution to `Mixx`.
  """

  @impl Mix.Task
  def run(args) do
    Mixx.run(args)
  end
end
