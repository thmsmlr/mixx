defmodule Mixx do
  @moduledoc """
  Core mixx functionality: argument parsing, usage banners, and execution plumbing
  for the `mix x` family of tasks. Runtime execution is currently stubbed while the
  rest of the proposal roadmap is implemented.
  """

  defmodule Spec do
    @moduledoc false
    @enforce_keys [:name, :app, :dependency, :default_task]
    defstruct [:name, :app, :dependency, :default_task]
  end

  @typedoc "Represents the normalized command produced from CLI arguments."
  @enforce_keys [:package]
  defstruct [:package, task: nil, args: [], options: []]

  @type t :: %__MODULE__{
          package: String.t(),
          task: String.t() | nil,
          args: [String.t()],
          options: Keyword.t()
        }

  @option_spec [
    force: :boolean,
    help: :boolean,
    task: :string
  ]

  @aliases [h: :help, t: :task]

  @string_options @option_spec
                  |> Enum.filter(fn {_key, type} -> type == :string end)
                  |> Enum.map(&elem(&1, 0))
                  |> MapSet.new()

  @long_option_map @option_spec
                   |> Enum.into(%{}, fn {key, _type} -> {"--" <> Atom.to_string(key), key} end)

  @alias_option_map @aliases
                    |> Enum.into(%{}, fn {alias, key} -> {"-" <> Atom.to_string(alias), key} end)

  @doc """
  Primary entrypoint invoked by `mix x`.

  Returns `:ok` when the command completes successfully. Invalid input raises a
  `Mix.Error` to provide consistent CLI behaviour.
  """
  @spec run([String.t()]) :: :ok | no_return
  def run(argv) do
    case parse(argv) do
      {:help, banner} ->
        info(banner)
        :ok

      {:error, message} ->
        Mix.raise("mix x: #{message}")

      {:ok, command} ->
        execute(command)
    end
  end

  @doc """
  Parses CLI arguments into a `Mixx` command structure.

  Recognised switches are documented in `usage/0`.
  """
  @spec parse([String.t()]) :: {:ok, t()} | {:error, String.t()} | {:help, String.t()}
  def parse(argv) do
    {opts, rest, invalid} = OptionParser.parse_head(argv, strict: @option_spec, aliases: @aliases)

    cond do
      opts[:help] ->
        {:help, usage()}

      error_from(invalid) ->
        {:error, error_from(invalid)}

      rest == [] ->
        {:error, "expected a package name, e.g. `mix x sobelow --version`"}

      true ->
        {:ok, build_command(rest, opts)}
    end
  end

  @doc "Returns the CLI usage banner."
  @spec usage() :: String.t()
  def usage do
    """
    Usage: mix x <package> [task] [args...]

      mix x sobelow --version
      mix x phx_new new demo_app
      mix x ./tooling/my_app setup

    Options:
      --task          Explicit task name when package defaults are unknown
      --force         Refresh cached install before executing remote task
      -h, --help      Show this usage information

    Notes:
      mixx infers Git repositories and local paths from the first argument when present.
    """
  end

  defp build_command(rest, opts) do
    [package | tail] = rest

    {task, args} =
      case {opts[:task], tail} do
        {nil, []} ->
          {nil, []}

        {nil, [candidate | more]} ->
          if option_token?(candidate) do
            {nil, [candidate | more]}
          else
            {candidate, more}
          end

        {task_override, list} ->
          {task_override, list}
      end

    %__MODULE__{package: package, task: task, args: args, options: opts}
  end

  defp execute(%__MODULE__{} = command) do
    with {:ok, spec} <- resolve_spec(command) do
      install_dependency(spec, command.options)
      task = resolve_task_name(command, spec)
      info("Running mix #{task}#{format_args(command.args)}")
      run_task(task, command.args)
    else
      {:error, message} -> Mix.raise("mix x: #{message}")
    end
  end

  defp error_from([]), do: nil

  defp error_from(invalid) do
    {missing, others} = Enum.split_with(invalid, &missing_value?/1)

    cond do
      missing != [] ->
        missing
        |> Enum.map(&missing_value_message/1)
        |> Enum.join("; ")

      others != [] ->
        others
        |> Enum.map(&invalid_option_label/1)
        |> Enum.join(", ")
        |> then(&"invalid option(s): #{&1}")

      true ->
        nil
    end
  end

  defp missing_value?({switch, nil}) when is_binary(switch) do
    case normalize_option(switch) do
      nil -> false
      option -> MapSet.member?(@string_options, option)
    end
  end

  defp missing_value?(_), do: false

  defp missing_value_message({switch, _value}) do
    canonical = canonical_switch(switch)
    "option #{canonical} expects a value"
  end

  defp invalid_option_label({switch, value}) when is_binary(switch) do
    case value do
      nil -> switch
      _ -> "#{switch}=#{value}"
    end
  end

  defp invalid_option_label(other), do: to_string(other)

  defp canonical_switch(switch) when is_binary(switch) do
    case normalize_option(switch) do
      nil -> switch
      option -> "--" <> Atom.to_string(option)
    end
  end

  defp normalize_option("--" <> _ = switch), do: Map.get(@long_option_map, switch)

  defp normalize_option("-" <> _ = switch), do: Map.get(@alias_option_map, switch)

  defp normalize_option(_), do: nil

  defp resolve_spec(%__MODULE__{} = command) do
    with {:ok, source} <- detect_source(command),
         app <- package_to_app(source.name),
         {:ok, dependency} <- dependency_tuple(source, app) do
      {:ok,
       %Spec{
         name: source.name,
         app: app,
         dependency: dependency,
         default_task: default_task(source.name)
       }}
    end
  end

  defp parse_package(package) do
    case String.split(package, "@", parts: 2) do
      [name] -> normalize_package_name(name, package, nil)
      [name, version] -> normalize_package_name(name, package, String.trim(version))
      _ -> {:error, "invalid package specification #{inspect(package)}"}
    end
  end

  defp normalize_package_name(name, original, version) do
    trimmed = String.trim(name)

    cond do
      trimmed == "" -> {:error, "invalid package specification #{inspect(original)}"}
      version == nil -> {:ok, trimmed, nil}
      version == "" -> {:error, "invalid package specification #{inspect(original)}"}
      true -> {:ok, trimmed, version}
    end
  end

  defp detect_source(%__MODULE__{} = command) do
    cond do
      path_candidate?(command.package) ->
        parse_path_source(command.package)

      git_candidate?(command.package) ->
        parse_git_source(command.package)

      true ->
        parse_hex_source(command.package)
    end
  end

  defp path_candidate?(package) do
    Path.type(package) == :absolute ||
      String.starts_with?(package, "./") ||
      String.starts_with?(package, "../") ||
      String.contains?(package, "/") ||
      File.dir?(Path.expand(package))
  end

  defp git_candidate?(package) do
    downcased = String.downcase(package)

    cond do
      String.starts_with?(downcased, "git@") ->
        true

      String.starts_with?(downcased, "git://") ->
        true

      String.starts_with?(downcased, "ssh://") ->
        true

      String.starts_with?(downcased, "git+https://") ->
        true

      String.starts_with?(downcased, "git+ssh://") ->
        true

      String.starts_with?(downcased, "https://") or String.starts_with?(downcased, "http://") ->
        String.contains?(downcased, ".git") ||
          String.contains?(downcased, "github.com") ||
          String.contains?(downcased, "gitlab.com") ||
          String.contains?(downcased, "bitbucket.org")

      true ->
        false
    end
  end

  defp dependency_tuple(%{type: :path, path: path}, app) do
    {:ok, {app, path: Path.expand(path)}}
  end

  defp dependency_tuple(%{type: :git, url: url, ref: ref}, app) do
    opts =
      [git: url]
      |> maybe_put_option(:ref, ref)

    {:ok, {app, opts}}
  end

  defp dependency_tuple(%{type: :hex, version: version}, app) do
    dependency = if version, do: {app, version}, else: app
    {:ok, dependency}
  end

  defp maybe_put_option(opts, _key, nil), do: opts
  defp maybe_put_option(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_hex_source(package) do
    with {:ok, name, version} <- parse_package(package) do
      {:ok, %{type: :hex, name: name, version: version}}
    end
  end

  defp parse_path_source(package) do
    expanded = Path.expand(package)

    if File.dir?(expanded) do
      name = expanded |> Path.basename() |> String.trim_trailing(".git")
      {:ok, %{type: :path, name: name, path: expanded}}
    else
      {:error, "local path #{inspect(package)} does not exist"}
    end
  end

  defp parse_git_source(package) do
    {url, ref} = split_git_ref(package)

    if String.trim(url) == "" do
      {:error, "invalid git URL #{inspect(package)}"}
    else
      name =
        url
        |> package_basename()
        |> String.trim_trailing(".git")

      {:ok, %{type: :git, name: name, url: url, ref: ref}}
    end
  end

  defp split_git_ref(package) do
    case String.split(package, "#", parts: 2) do
      [url, ref] -> {url, String.trim(ref)}
      [url] -> {url, nil}
    end
  end

  defp install_dependency(%Spec{} = spec, options) do
    maybe_ensure_hex!(spec)
    info("Installing #{spec.name}")

    Mix.ProjectStack.on_clean_slate(fn ->
      Mix.install([spec.dependency], install_options(options))
    end)

    :ok
  end

  defp install_options(options) do
    []
    |> put_option(:force, options[:force])
  end

  defp put_option(opts, _key, nil), do: opts
  defp put_option(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_ensure_hex!(%Spec{dependency: dependency}) do
    case dependency do
      {_, opts} when is_list(opts) ->
        if Keyword.has_key?(opts, :git) || Keyword.has_key?(opts, :path) do
          :ok
        else
          ensure_hex_installed()
        end

      _ ->
        ensure_hex_installed()
    end
  end

  defp ensure_hex_installed do
    Mix.ProjectStack.on_clean_slate(fn ->
      unless Mix.Hex.ensure_installed?(true) do
        Mix.raise("mix x: Hex is required to install packages; run `mix local.hex --force`")
      end

      Mix.Local.append_archives()
      Code.ensure_loaded?(Hex.Solver.Constraints.Union)
      Code.ensure_loaded?(Hex.Solver.Constraints.Range)
      Code.ensure_loaded?(String.Chars.Hex.Solver.Constraints.Union)
      Code.ensure_loaded?(String.Chars.Hex.Solver.Constraints.Range)
      Mix.ensure_application!(:ssl)
      Mix.ensure_application!(:inets)
      Mix.Hex.start()
    end)
  end

  defp resolve_task_name(%__MODULE__{task: nil}, %Spec{default_task: task}), do: task

  defp resolve_task_name(%__MODULE__{task: task}, %Spec{default_task: default}) do
    cond do
      String.contains?(task, ".") -> task
      default -> prefix_task(default, task)
    end
  end

  defp prefix_task(default, task) do
    base = default |> String.split(".") |> List.first()

    case base do
      nil -> task
      prefix -> prefix <> "." <> task
    end
  end

  defp run_task(task, args) do
    ensure_task_available!(task)
    Mix.Task.rerun(task, args)
    :ok
  end

  defp ensure_task_available!(task) do
    case Mix.Task.get(task) do
      nil ->
        Mix.Task.load_all()

        case Mix.Task.get(task) do
          nil -> Mix.raise("could not find mix task #{task} after installing dependency")
          _module -> :ok
        end

      _module ->
        :ok
    end
  end

  defp option_token?("--" <> _), do: true
  defp option_token?("-" <> _), do: true
  defp option_token?(_), do: false

  defp package_to_app(name) do
    name
    |> package_basename()
    |> String.replace("-", "_")
    |> String.to_atom()
  end

  defp default_task(nil), do: nil

  defp default_task(name) do
    name
    |> package_basename()
    |> String.replace("-", "_")
    |> String.replace("/", ".")
    |> String.replace("_", ".")
  end

  defp package_basename(name) do
    name
    |> String.trim()
    |> String.trim_trailing("/")
    |> String.split("/", trim: true)
    |> List.last()
    |> maybe_trim_git_suffix()
  end

  defp maybe_trim_git_suffix(nil), do: nil
  defp maybe_trim_git_suffix(segment), do: String.trim_trailing(segment, ".git")

  defp format_args([]), do: ""
  defp format_args(args), do: " " <> Enum.join(args, " ")

  defp info(message) do
    shell().info(message)
  end

  defp shell do
    Mix.shell()
  end
end
