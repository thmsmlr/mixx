# MIXX

MIXX brings `mix x` to any Elixir workspace: run Mix tasks from Hex packages on demand, without adding them to your project or installing them globally.

## Getting Started (Users)

1. **Install the archive**

   ```bash
   mix archive.install hex mixx
   ```

   Until MIXX is published on Hex you can build from source instead:

   ```bash
   mix archive.build
   mix archive.install ./mixx-0.1.0.ez --force
   ```

   MIXX targets Elixir ≥ 1.14 (tested on 1.18). The archive installs into `~/.mix/archives`, making `mix x` globally available.

2. **Run remote Mix tasks**

   ```bash
   mix x sobelow --version
   mix x phx_new new /tmp/demo_app --no-install
   mix x some_pkg.custom.task arg1 arg2
   ```

   The general shape is `mix x <package> [task] [args...]`. If you omit the task, MIXX will call the package’s default Mix task (derived from its name).

3. **Useful switches**

   - `--task some.task` — override the inferred Mix task
   - `--force` — force `Mix.install/2` to rebuild the package
   - `--git URL` / `--path PATH` — execute against a Git repo or local path instead of Hex

If you encounter packages that require project context (e.g., Phoenix generators), run `mix x` from the directory you want those files written to.

## How It Works

MIXX is delivered as a Mix archive (similar to `phx.new`). The `mix x` task:

- Parses CLI arguments with `OptionParser` to normalise package specs and switches.
- Resolves the package into a `Mix.install/2` dependency tuple (Hex by default, or Git/Path when requested).
- Invokes `Mix.install/2` inside a clean project stack, ensuring required runtime applications start and the dependency is compiled.
- Reruns the target Mix task with `Mix.Task.rerun/2`, so any `mix` aliases or environment configuration behave as expected.

Stretch goals (caching manifests, offline reuse, escript execution) are outlined in `proposal.md` and not part of the initial release yet.

## Contributing & Development Setup

1. **Clone the repo and install Elixir ≥ 1.14.** No extra dependencies are required.
2. **Run the test suite**

   ```bash
   mix test             # unit tests only
   mix test --include integration  # exercises real Mix.install flows
   ```

3. **Experiment locally**

   ```bash
   mix run -e 'Mixx.run(["sobelow", "--version"])'
   ```

4. **Build and try the archive**

   ```bash
   mix archive.build
   mix archive.install ./mixx-0.1.0.ez --force
   mix x sobelow --version
   ```

5. **Follow the roadmap in `proposal.md`** for upcoming tasks (caching manifest, `mix x.help`, documentation). Please coordinate in issues or PRs before tackling stretch goals.

We welcome bug reports and contributions—open an issue describing the problem or proposed enhancement, and include reproduction steps where possible.
