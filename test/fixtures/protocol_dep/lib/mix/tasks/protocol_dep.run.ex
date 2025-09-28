defmodule Mix.Tasks.ProtocolDep.Run do
  @moduledoc false
  use Mix.Task

  @shortdoc "Verifies ProtocolDep.Stream is enumerable"

  @impl Mix.Task
  def run(_args) do
    case Enum.to_list(%ProtocolDep.Stream{}) do
      [1, 2, 3] -> :ok
      other -> Mix.raise("unexpected enumeration result: #{inspect(other)}")
    end
  end
end
