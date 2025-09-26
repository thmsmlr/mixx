# mixx

Run any Mix task on demand without wiring dependencies into your project.

```bash
mix archive.install hex mixx
mix x sobelow --version
mix x phx_new new demo_app
mix x ./tooling/my_app setup
mix x git+https://github.com/acme/tooling.git#main lint
```

## Why mixx?

- **One-off productivity** – fetch a Hex package, Git repo, or local path and execute its Mix tasks instantly.
- **Zero project churn** – no need to edit `mix.exs`; mixx installs dependencies ephemerally via `Mix.install/2`.
- **Consistent defaults** – skip the task argument and mixx invokes `<app>.run` for you.

mixx targets Elixir ≥ 1.14 (validated on 1.18). Once installed, `mix x` is available globally through your `~/.mix/archives` directory.

## Usage

```
mix x <package> [task] [args...]
```

- `<package>` accepts Hex names (`sobelow`), full Git URLs (with optional `#ref`), or filesystem paths. mixx infers the source automatically.
- If `<task>` is omitted we call the package’s default Mix task (derived from the package name). Override with `--task some.other.task` when needed.
- Extra `[args...]` are forwarded untouched to the remote Mix task.

#### Default Task Convention

When you skip the task argument, mixx calls `<app>.run`, where `<app>` is the inferred OTP application name (package name with hyphens turned into underscores). For example:

```
sobelow      ➜ sobelow.run
phx_new      ➜ phx_new.run
mixx-tooling ➜ mixx_tooling.run
```

To plug in seamlessly, expose a Mix task at `Mix.Tasks.<App>.Run`. If your package prefers a different entrypoint, document it and have users pass `--task` explicitly.

### Options

- `--task some.task` – run a specific Mix task without relying on default inference.
- `--force` – force `Mix.install/2` to refresh the cached install.
- `-h`, `--help` – print the usage banner.

### Examples

```bash
mix x sobelow --task sobelow --version   # Hex package, explicit task override
mix x git@github.com:acme/tool.git       # Git SSH URL, runs acme_tool.run
mix x ../generators setup                # Local path for in-house tooling
mix x some_pkg --task foo.bar --dry-run
```

## Installation

```bash
mix archive.install hex mixx
# or, from a local checkout
mix archive.build
mix archive.install ./mixx-0.1.0.ez --force
```

## How It Works

1. **Argument parsing** – we interpret options with `OptionParser`, infer the dependency source, and normalise package specs.
2. **Temporary install** – `Mix.install/2` pulls the dependency into the Mix install cache inside a clean project stack.
3. **Task dispatch** – we rerun the target Mix task via `Mix.Task.rerun/2`, surfacing its output exactly as if it were part of your project.

Behind the scenes mixx primes Hex’s solver protocols to avoid first-run latency and keeps installs isolated so you can safely experiment.

## Contributing

```bash
mix test
mix test --include integration   # exercises remote installs
mix run -e 'Mixx.run(["sobelow", "--version"])'
```

Check `proposal.md` for the roadmap (cache management, `mix x.help`, offline reuse). Issues and pull requests are welcome—just describe the scenario and share repro steps when possible.
