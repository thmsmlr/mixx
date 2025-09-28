defmodule ProtocolDep.Stream do
  @moduledoc false

  defstruct data: [1, 2, 3]
end

defimpl Enumerable, for: ProtocolDep.Stream do
  def count(%{data: data}), do: {:ok, length(data)}

  def member?(%{data: data}, value), do: {:ok, Enum.member?(data, value)}

  def slice(_stream), do: {:error, __MODULE__}

  def reduce(%{data: data}, acc, fun) do
    Enumerable.List.reduce(data, acc, fun)
  end
end
