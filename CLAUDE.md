# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

`startpro` is a companion Mix package to [`starter`](https://github.com/jamilabreu/starter)
(v0.5.x). The repo is currently a `mix new` skeleton (`Startpro.hello/0` stub,
no deps); the design is fully specified but not yet implemented. The README
describes the *intended* behavior. Before writing code, read:

- `_spec/features/260926_starter-profiles.md` — feature spec
- `_spec/plans/260926_starter-profiles.md` — implementation plan (numbered
  design decisions, step-by-step file list, edge cases, testing strategy)
- `_spec/designs/260926_Intro.md` — background discussion and rationale

The plan's decisions are confirmed by the user; don't re-litigate them.
Spec files follow a `YYMMDD_name.md` naming convention under `_spec/{designs,features,plans}/`.

## Commands

```sh
mix deps.get
mix compile
mix test                                   # all tests
mix test test/startpro/resolver_test.exs   # one file
mix test test/startpro/resolver_test.exs:42  # one test by line
mix format
```

Planned (per the plan, step 1): `elixir: "~> 1.17"` in `mix.exs` (currently
`~> 1.20` from the generator), deps `{:starter, "~> 0.5"}` (brings in Igniter)
and `ex_doc`, and `import_deps: [:igniter]` in `.formatter.exs`. No Hex
`package/0` — distributed only as a `path:`/`git:` dependency.

## Architecture (planned)

What it does: loads named step-list **profiles** from one external `.exs`
config file, expands `{:use, :name}` / `{:use, :name, if: :flag}` includes
into a flat, acyclic, de-duplicated step list, runs it through `starter`'s
existing engine, and records the run as one git commit in the target app.
Upstream `starter` must not be modified, and `mix starter.new` / in-app starter
modules are not used.

Data flow for `mix startpro.run <PROFILE>`:

1. `Startpro.Config` resolves the path (`-c/--config` → `STARTPRO_CONFIG` →
   `$XDG_CONFIG_HOME/startpro/profiles.exs` → `~/.config/startpro/profiles.exs`),
   `Code.eval_file`s it, and validates shape (keyword list or atom-keyed map of
   `name => [step]`). Only `:use` tuples are validated here; other step shapes
   are left for the upstream runner.
2. `Startpro.Resolver` does a DFS over nodes `{:profile, name}` and
   `{:starter, module}` with separate "on-stack" and "done" sets (diamonds are
   not cycles). Returns entries `%{step:, origin:, gates:}` plus dropped
   `duplicates`. `flags: :all` walks every gated include (used for validation,
   `list.steps`, and the flag schema); `flags: opts` is used for the real run —
   a gated-off include is **not** marked done, so a later ungated `use` still
   expands it. `run` always does a `:all` pass first. `{:starter, M}` includes
   are expanded via `M.steps()` when loadable, else passed through.
   De-dup: first occurrence wins; steps differing only in `if:` are distinct.
3. `Startpro.Starter` is the engine adapter: a fixed module implementing the
   `Starter` behaviour whose `steps/0` reads the resolved list from
   `:persistent_term` (set before `Starter.Runner.run/3`, erased in `after`).
   Chosen over `Module.create/3` to avoid runtime compilation.
4. `mix startpro.run` is an `Igniter.Mix.Task` (single diff, confirm once,
   `--yes`/`--dry-run`). Its `info/2` resolves the profile from argv to publish
   a boolean option per flag. Unless `--no-commit`, it refuses to start if the
   target isn't a git repo or the tree is dirty (checked before the runner's
   dep pre-fetch writes anything), then queues the internal
   `mix startpro.git.commit --message-file <tmp>` via `Igniter.add_task/3` so
   it runs last, only if the diff is applied.

Conventions from the plan:

- Library functions return `{:ok, _} | {:error, reason}`; all reasons are
  formatted by `Startpro.Error.message/1`; Mix tasks call `Mix.raise/1`.
- Never create atoms from user input — match profile names against
  `Atom.to_string/1` of config keys, treating `-` and `_` as equal.
- The editor (`config.edit`) is launched via a `Port` with `:nouse_stdio`,
  behind a replaceable function for tests.
- Commit message: subject `startpro: apply profile <name>` (<72 chars), plain
  numbered lines (no bullets) listing config path, flags, and steps with origin.
- Default config template lives in `priv/templates/profiles.exs`.

## Testing notes

- Tests touching env vars (`STARTPRO_CONFIG`, `XDG_CONFIG_HOME`) must restore
  them and use `async: false`.
- Git tests use `@tag :tmp_dir` with a real `git init`.
- The `run` integration test uses `Igniter.Test.test_project/0` with only
  built-in `:gen`/`:remove` steps (installs are inert in test mode), and must
  not depend on this repo's own working-tree state.
