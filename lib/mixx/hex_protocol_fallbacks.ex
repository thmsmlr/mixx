unless Code.ensure_loaded?(String.Chars.Hex.Solver.Constraints.Union) do
  defimpl String.Chars, for: Hex.Solver.Constraints.Union do
    def to_string(union), do: inspect(union)
  end
end

unless Code.ensure_loaded?(String.Chars.Hex.Solver.Constraints.Range) do
  defimpl String.Chars, for: Hex.Solver.Constraints.Range do
    def to_string(range), do: inspect(range)
  end
end
