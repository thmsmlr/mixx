# mixx Implementation Proposal

## Background & Motivation
- The Mix core team discussed extending `Mix.install/2` to support ephemeral package execution via `mix x`, providing an npx-like experience for running one-off Mix tasks from Hex packages without globally installing them.
- mixx delivers these capabilities today as a globally installed Mix archive, similar to Phoenix's archive-based generators, so users can run `mix x <package> [args]` and let mixx resolve, download, and dispatch tasks on demand.

## High-Level Goals
1. Provide a frictionless CLI for executing Mix tasks exposed by remote packages (Hex by default, Git/path overrides allowed) via the single entrypoint `mix x`.
2. Ensure executions are ephemeral and predictable: each run assembles a clean Mix environment via `Mix.install/2` without requiring global dependencies.
3. Offer discoverability and help ergonomics (e.g., `mix x phoenix.new --help` mirrors the proposed UX).
4. Remain self-contained: mixx ships as a Mix archive that can be installed with `mix archive.install hex mixx` (once published) or directly from source.

## Status & TODOs

**Completed**
- OptionParser-based CLI (`mix x`) with support for Hex/Git/Path sources, custom task overrides, and helpful usage messaging.
- Core execution flow that resolves package specs, invokes `Mix.install/2`, and reruns remote Mix tasks; validated against Sobelow (`mix x sobelow --version`).
- Initial test suite covering argument parsing plus an integration spec that exercises remote task execution.
- Archive build and global installation confirmed (`mix archive.build` + `mix archive.install`), enabling `mix x` usage outside the repo.
- Phoenix generator smoke test via mixx (`mix x phx_new new <path> --no-install`) to verify more complex tasks execute correctly.

**Outstanding**
- Implement caching manifest management (`mix x.cache` family) and reusable install heuristics.
- Add Hex registry querying to auto-resolve latest versions and improve error messages when requirements are missing.
- Expand CLI surface (e.g., `mix x.help`, cache subcommands) once supporting infrastructure exists.
- Harden error handling around Mix task discovery, including clearer messaging for tasks requiring project context.
- Author end-user documentation and distribution notes ahead of publishing the archive.
- Stretch goals: escript/arbitrary entrypoint execution, caching-based offline re-use, shell completion helpers.

## Design Overview

### Distribution Strategy
- Package mixx as a Mix archive using `Mix.Tasks.Archive.Build`. Archives contain compiled BEAM files under `ebin/` and can be installed globally via `mix archive.install` into `MIX_HOME/archives` (defaults to `~/.mix`).
- Limitations: archives cannot bundle dependencies; therefore mixx must depend only on the standard library and ship its runtime logic without extra deps. Runtime packages are fetched at execution time via `Mix.install/2`.

### CLI & UX Surface
- Primary task: `Mix.Tasks.X` exposed as `mix x` with subcommands accessed through the dot operator:
  - `mix x <package> [task] [args...]` – default command that resolves the package and executes `<app>.run` when no task is provided.
  - `mix x.help <package> [task]` – print remote package task help (downloads if needed).
- Shortcut aliases inspired by the original proposal:
  - Support `package@version` syntax, `owner/package`, or explicit source options (`--hex`, `--git`, `--path`).
  - `--force` refreshes installs if the dependency is already present in the Mix install cache.

### Package Specification & Resolution
- Parse CLI arguments into a `Mix.Dep` compatible tuple passed to `Mix.install/2`, supporting:
  - Hex packages with optional version constraints.
  - Git repositories with ref options.
  - Local filesystem paths (useful for testing).
- Leverage Hex API (via `Hex.Registry.Server`) for latest version resolution when no version provided; fall back to package metadata caching to minimize API calls.

### Ephemeral Environment via `Mix.install/2`
- Call `Mix.install/2` with the resolved dependency list and options:
  - `config_path` pointing to a mixx-managed config file for per-package runtime configuration.
  - `app` option to ensure required applications start.
  - `force: true` when `--force` is provided to refresh the install.
- `Mix.install/2` stores builds under `MIX_HOME/installs`, so mixx can check if an install already exists and skip reinstall unless invalidated.
- Use distinct install identifiers (e.g., hash of dependency spec) to allow multiple versions of the same package to coexist.

### Task Dispatch
- After installation, mixx loads the remote project's code path (handled by `Mix.install/2`) and executes:
- `Mix.Task.rerun/2` with the remote task name resolved from CLI input (`<app>.run` when no explicit task is given, or an override via `--task`).
- Provide structured logging around download, compilation, and execution phases to match user expectations.

### Stretch Goal: Caching & State Management
- Maintain a mixx manifest under `MIX_HOME/mixx/manifest.json` capturing resolved versions, install hashes, timestamps, and observed task entries.
- Offer commands to list (`mix x.cache ls`) and clean (`mix x.cache prune [package]`) cached installs once the manifest exists.
- Investigate Hex API integrations and heuristics to reuse previously fetched packages without rerunning compiles.

### Stretch Goal: eScript & Arbitrary Entrypoint Support
- Long-term, mixx can detect if a package exposes an escript in its metadata and optionally delegate execution.
- For packages shipping only escripts, mixx would:
  - Download via `Hex.SCM` APIs or Git.
  - Build/install the escript into a temp dir using `Mix.Tasks.Escript.Build` and run it directly.
- Additional stretch: `mix x.exec <package> <module> <function> [args...]` to run arbitrary function entrypoints for flexible scripts.
- These capabilities are out of scope for the initial release but are documented here for future expansion.

### Safety & Sandboxing Considerations
- Highlight in docs that executing arbitrary packages carries risk; recommend pinning versions and reviewing package source.
- Support `--path` installs for audited local clones.

### Developer Experience Enhancements
- Autocomplete integration: generate shell completion scripts for common shells (bash, zsh, fish) to aid discoverability.
- Help output includes examples mirroring the original proposal (`mix x phx.new my_app` etc.).
- Provide a `mix x.new` generator to scaffold wrapper scripts for frequently used packages (post-MVP).

## Implementation Roadmap
1. **Scaffolding (Week 1)**
   - Define archive entry modules (`Mix.Tasks.X`, `Mixx` helpers).
   - Implement package spec parser and baseline configuration handling.
2. **Core Execution (Weeks 2-3)**
   - Integrate `Mix.install/2` invocation and environment setup.
   - Implement Mix task dispatch and default task resolution.
   - Add logging, error handling, and exit codes.
3. **Polish & Distribution (Week 4)**
   - Author documentation (`README`, usage guide).
   - Build and verify archive via `mix archive.build`.
   - Publish archive artifact and provide install instructions.
4. **Stretch (Post v1)**
   - Implement caching manifest management plus cache listing/prune commands for reusing previously fetched installs.
   - Extend to escript and arbitrary entrypoint execution once core infrastructure is stable.
   - Evaluate concurrency and advanced caching strategies after caching primitives land.

## Verification Strategy
1. **CLI smoke test** – After scaffolding, validate `mix x --help` outputs the expected usage banner and subcommand listings.
2. **Remote task execution** – Call `mix x sobelow --version` to install the community security scanner from Hex and confirm mixx can fetch and execute a third-party Mix task end-to-end.

*Stretch follow-ups*: once caching or escript support ships, add targeted regression suites (e.g., `mix x.cache ls`, cached reuse scenarios) to cover those new pathways.

## Open Questions & Next Steps
- Should mixx support remote mix tasks that expect project context (e.g., Phoenix generators)? Investigate isolating current working directory vs. user project directory to avoid side effects.
- Determine how to surface package-defined aliases (mapping package names to custom tasks) without a central registry—consider shipping a curated overrides map or reading Hex package metadata (e.g., package docs).
- Explore concurrency: allow parallel installs for multiple packages in a single command? Possibly defer to future work.

## Appendices
- Archive installation: `mix archive.install path/to/mixx-<version>.ez` adds mixx to `MIX_HOME/archives`.
- `Mix.install/2` options such as `:force`, `:apps`, and `:config_path` will be the primary integration points for controlling runtime behavior.
- escript installs land in `MIX_HOME/escripts`, with optional symlink to `PATH` (stretch goal).
