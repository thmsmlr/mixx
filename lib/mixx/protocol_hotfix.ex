defmodule Mixx.ProtocolHotfix do
  @moduledoc """
  Emergency protocol reconsolidation helpers for `mixx`.

  ### Why this exists

  When a developer runs `mix x` from a Phoenix project that has already been
  compiled, the BEAM VM is running with *consolidated protocols*. Elixir’s
  consolidation step snapshots every protocol (for example `Enumerable`) and
  the implementations that were visible on the code path at compile time. The
  resulting BEAMs are loaded into the VM long before `mixx` enters the picture.

  `Mix.install/2` pulls our transient dependency stack (Igniter, Rewrite, etc.)
  *after* that snapshot was taken. The language currently offers no automatic
  hook to tell the VM “new code paths were added, please rebuild the dispatch
  tables”. As a result, fresh implementations—like Rewrite’s
  `%Rewrite{}` `Enumerable`—are invisible and every call into the protocol raises
  `Protocol.UndefinedError`.

  ### What we do

  This module provides the brute-force workaround:

    * snapshot the VM’s code path before calling `Mix.install/2`;
    * remember any directories that appear afterwards (those contain the newly
      compiled protocol implementations);
    * rehydrate those directories onto the code path before each task run; and
    * rebuild **every** protocol’s consolidated BEAM so the new implementations
      become part of the dispatch table.

  It is deliberately heavy-handed and exists as a hotfix until the tooling or
  the language grows a first-class mechanism for reconciling consolidated
  protocols with late-added code paths.
  """

  @paths_key {__MODULE__, :paths}

  @type path_snapshot :: [charlist()]

  @doc "Return the current code path so it can be diffed after Mix.install/2 runs."
  @spec before_install() :: path_snapshot()
  def before_install, do: :code.get_path()

  @doc "Remember any directories added by Mix.install/2 and reconsolidate protocols."
  @spec after_install(path_snapshot()) :: :ok
  def after_install(pre_paths) do
    pre_paths
    |> added_paths()
    |> remember_paths()

    force_rebuild()
  end

  @doc "Ensure the code path is hydrated and every protocol is reconsolidated."
  @spec before_task() :: :ok
  def before_task do
    force_rebuild()
  end

  defp added_paths(pre_paths) do
    :code.get_path() -- pre_paths
  end

  defp remember_paths([]), do: :ok

  defp remember_paths(paths) do
    existing = :persistent_term.get(@paths_key, [])
    :persistent_term.put(@paths_key, Enum.uniq(existing ++ paths))
  end

  defp force_rebuild do
    rehydrate_paths()

    all_paths = :code.get_path()

    all_paths
    |> Protocol.extract_protocols()
    |> Enum.each(fn proto ->
      impls = Protocol.extract_impls(proto, all_paths)

      if impls != [] do
        rebuild(proto, all_paths, impls)
      end
    end)

    :ok
  end

  defp rehydrate_paths do
    @paths_key
    |> :persistent_term.get([])
    |> Enum.each(&:code.add_patha/1)
  end

  defp rebuild(proto, all_paths, impls) do
    case Protocol.consolidate(proto, impls) do
      {:ok, bin} ->
        reload(proto, bin)

      {:error, :no_beam_info} ->
        with :ok <- load_unconsolidated(proto, all_paths),
             {:ok, bin} <- Protocol.consolidate(proto, impls) do
          reload(proto, bin)
        else
          _ -> :error
        end

      _other ->
        :error
    end
  end

  defp reload(proto, bin) do
    :code.purge(proto)
    :code.delete(proto)
    :code.load_binary(proto, ~c"nofile", bin)
    :ok
  end

  defp load_unconsolidated(proto, all_paths) do
    beam = Atom.to_string(proto) <> ".beam"

    all_paths
    |> Enum.map(&List.to_string/1)
    |> Enum.reject(&String.contains?(&1, "/consolidated"))
    |> Enum.find_value(fn dir ->
      path = Path.join(dir, beam)
      if File.exists?(path), do: path
    end)
    |> case do
      nil -> :error
      beam_path -> load_from_disk(proto, beam_path)
    end
  end

  defp load_from_disk(proto, path) do
    case File.read(path) do
      {:ok, beam} ->
        case :code.load_binary(proto, String.to_charlist(path), beam) do
          {:module, ^proto} -> :ok
          {:error, reason} -> {:error, reason}
          :error -> :error
        end

      error ->
        error
    end
  end
end
