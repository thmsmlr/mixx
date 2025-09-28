defmodule Mixx.ProtocolReconsolidationTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @fixture Path.expand("fixtures/protocol_dep", __DIR__)
  @install_key {Mixx, :install_paths}

  test "reconsolidates protocols for path dependencies" do
    tmp_root =
      Path.join(System.tmp_dir!(), "mixx_proto_dep-#{System.unique_integer([:positive])}")

    dep_path = Path.join(tmp_root, "protocol_dep")

    File.rm_rf!(tmp_root)
    File.mkdir_p!(tmp_root)
    File.cp_r!(@fixture, dep_path)

    on_exit(fn ->
      File.rm_rf!(tmp_root)
      :persistent_term.erase(@install_key)
      Mix.Task.clear()
    end)

    :persistent_term.erase(@install_key)

    consolidate_enumerable()

    capture_io(fn ->
      assert :ok = Mixx.run(["--task", "protocol_dep.run", dep_path])
    end)

    assert Protocol.consolidated?(Enumerable)
    assert Code.ensure_loaded?(ProtocolDep.Stream)

    stream = struct!(ProtocolDep.Stream)
    assert stream |> Enumerable.impl_for() |> is_atom()
    assert Enum.to_list(stream) == [1, 2, 3]
  end

  defp consolidate_enumerable do
    impls = Protocol.extract_impls(Enumerable, :code.get_path())

    case Protocol.consolidate(Enumerable, impls) do
      {:ok, beam} ->
        :code.purge(Enumerable)
        :code.delete(Enumerable)
        :code.load_binary(Enumerable, ~c"nofile", beam)
        :ok

      other ->
        flunk("failed to consolidate Enumerable before test: #{inspect(other)}")
    end
  end
end
