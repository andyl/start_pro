# StartPro

Application profiles for Elixir [Starter](https://github.com/jamilabreu/starter).

`start_pro` is a companion package to `starter`. It lets you keep your starter
step lists as named **profiles** in one config file outside your projects,
such as `~/.config/start_pro/profiles.exs`. You can then apply any profile to a
new Phoenix app with a single command:

```sh
mix start_pro.run standard_app
```

With upstream `starter`, you generate a starter module inside each app and
copy it into the next project. With `start_pro`, **the profile is the source of
truth**, and **the app's git history is the record** of what was applied.

## How it relates to `starter`

`start_pro` uses `starter`'s engine and built-in steps. It does **not** use
`mix starter.new`, `mix starter.run`, or an in-app starter module:

- `mix starter.new` only generates `lib/mix/tasks/<app>.starter.ex`, a starter
  module that lives in your app. With `start_pro`, your profiles live in the
  config file, so you don't need that file.
- `mix start_pro.run` resolves your profile and hands the step list straight to
  `starter`'s runner. You get the same single diff, the same confirmation
  prompt, and the same built-in steps.
- `starter` still has to be a dependency of the target app, because it
  provides the runner and the built-in steps. Igniter runs inside the project,
  so there's no way around that.

If an app also has a `starter.new` file, the two don't interact. Running both
would apply the steps twice, so pick one.

## Installation

`start_pro` is not published on Hex. Add it next to `starter` as a dev-only
dependency, from a local path or from git:

```elixir
def deps do
  [
    {:starter, "~> 0.5", only: :dev},
    {:start_pro, path: "~/src/Tool/start_pro", only: :dev},
    # or: {:start_pro, git: "https://github.com/andyl/start_pro", only: :dev}
  ]
end
```

It requires Elixir 1.17 or later.

## Quick start

```sh
# once, anywhere: create your profiles file and edit it
mix start_pro.config.init
mix start_pro.config.edit

# in a new app
mix phx.new my_app && cd my_app
git init && git add -A && git commit -m "Initial commit"
# add :starter and :start_pro to deps (see Installation), then:
mix deps.get
mix start_pro.list.steps standard_app      # preview what will run
mix start_pro.run standard_app             # apply and commit
```

## The config file

`start_pro` looks for the config file in this order, using the first one it
finds:

1. `-c <path>` / `--config <path>` on the command line
2. the `START_PRO_CONFIG` environment variable
3. `$XDG_CONFIG_HOME/start_pro/profiles.exs`
4. `~/.config/start_pro/profiles.exs`

Only one config file is used for any command.

> **Warning:** the config file is Elixir code, and `start_pro` evaluates it.
> Only use a config file you wrote or trust.

The file evaluates to a keyword list of `profile_name => [steps]`. Steps use
exactly the syntax from `starter`'s docs, plus two additions: `{:use, ...}`
includes and `from:` registry steps:

```elixir
[
  phoenix_cleanup: [
    {:remove, :daisy_ui},
    {:remove, :topbar}
  ],
  tooling: [
    {:add, :credo},
    {:add, :exsync, if: :exsync}
  ],
  finish: [
    {:gen, :sort_deps}
  ],
  standard_app: [
    {:use, :phoenix_cleanup},
    {:use, :tooling},
    {:use, :deploy_gigalixir, if: :gigalixir},
    {:starter, MyTeam.Baseline},
    MyTeam.Steps.Presence,
    {:add, :ash, from: StartReg},
    {:use, :finish}
  ]
]
```

### Including other profiles with `{:use, ...}`

- `{:use, :name}` includes another profile's steps **in place**, at the
  position where the `use` appears.
- `{:use, :name, if: :flag}` includes it only when `--flag` is passed.
- Includes can be nested to any depth. `{:starter, Module}` includes from
  upstream `starter` work too.
- **No cycles.** If `a` uses `b` and `b` uses `a`, you get an error that shows
  the full path. `start_pro` checks every include, including gated ones,
  before anything runs.
- **Every step runs once.** If a profile is included twice (for example, two
  profiles both use `base`), its steps expand only at the first place it
  appears. Exact duplicate steps are dropped, and the first one wins.
  `mix start_pro.list.steps` shows what was dropped.

Because the first occurrence wins, put "finishing" steps like
`{:gen, :sort_deps}` in their own profile and `use` it last. Don't put them
inside a baseline profile.

### Registry steps with `from:`

A registry is a package of Igniter step tasks named
`Mix.Tasks.<Registry>.<Kind>.<Name>`, such as
[start_reg](https://github.com/andyl/start_reg). Instead of writing out the
full module name, name the step by kind and name and say which registry it
comes from:

```elixir
tooling: [
  {:add, :ash, from: StartReg},                            # Mix.Tasks.StartReg.Add.Ash
  {:add, :ash_phoenix, from: StartReg},                    # Mix.Tasks.StartReg.Add.AshPhoenix
  {:gen, :xp_mix_completions, from: StartReg, if: :completions},
  {:remove, :topbar, from: StartReg}                       # Mix.Tasks.StartReg.Remove.Topbar
]
```

- The kind is `:add`, `:gen` or `:remove`, and it becomes the module segment
  `Add`, `Gen` or `Remove`. The name is camelized, so `:ash_phoenix` becomes
  `AshPhoenix`.
- `from:` is the registry's module prefix, written as a module (`StartReg`),
  not an atom (`:start_reg`). It is required. Without it, `{:add, :ash}` is
  an ordinary `starter` step that goes to `starter`'s own step or the
  package's upstream installer.
- `if: :flag` works as on any other step and adds a `--flag` option.
- The registry package must be a dependency of the target app, like any
  custom step. `mix start_pro.run` checks that the task module exists before
  it starts, and names the profile and the step if it doesn't.
- Listings and the commit message show the step as you wrote it. Only
  `starter`'s runner sees the translated module.

This form is understood only by `start_pro`, not by upstream `starter`, so
don't use it in `starter.new` files or in `{:starter, Module}` modules that
`starter` might run on its own. Writing the module name out, e.g.
`Mix.Tasks.StartReg.Add.Ash`, works in both.

A malformed registry step fails when the config is loaded. That includes an
unsupported kind, a `from:` that isn't a module, and an option other than
`from:` or `if:`.

### Custom steps and starter modules

A profile can name a custom step module, such as `MyTeam.Steps.Presence`, but
the step's code can't live in the config file. Put custom steps in their own
package and add that package as a dev dependency of the target app.

`{:starter, Module}` includes are expanded by `start_pro` itself, so they get
the same include-once, de-duplication, cycle checks and origin tags as
`{:use, ...}`. Where the module isn't loaded (for example, `list.steps` run
outside the app that depends on it), the include is shown unexpanded and
`starter` expands it at run time. `mix start_pro.run` checks that every custom
step and starter module exists in the app before it starts, and names the
profile that refers to a missing one.

## Tasks

Every task accepts `-c <path>` / `--config <path>`.

| Task                                | What it does                                                                                                                          |
|-------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------|
| `mix start_pro.config.init`          | Creates the config file with example profiles. Refuses to overwrite an existing file unless you pass `--force`.                       |
| `mix start_pro.config.edit`          | Opens the config file in `$EDITOR` (or `$VISUAL`), then checks that every profile still loads and resolves.                          |
| `mix start_pro.list.profiles`        | Lists every profile and the profiles it uses.                                                                                         |
| `mix start_pro.list.steps <PROFILE>` | Shows the fully expanded, numbered step list, with the profile each step came from.                                                   |
| `mix start_pro.run <PROFILE>`        | Applies the profile to the current app and commits the result. Accepts a `--flag` for every `if:` in the profile, plus `--no-commit`. |

Profile names on the command line treat `-` and `_` as the same, so
`standard-app` finds `standard_app`.

### `mix start_pro.config.init`

```sh
$ mix start_pro.config.init
Created /home/you/.config/start_pro/profiles.exs
```

The template documents every step form and defines `phoenix_cleanup`,
`phoenix_defaults`, `tooling`, `jobs`, `deploy_gigalixir`, `finish`, and a
`standard_app` profile that composes them.

### `mix start_pro.config.edit`

Terminal editors (vim, nvim, nano) work as-is. GUI editors must be told to
wait for the file to close, e.g. `EDITOR="code --wait"`. If the saved file
doesn't validate, you get a warning and the file is left as you saved it.

### `mix start_pro.list.profiles`

```
$ mix start_pro.list.profiles
Profiles in /home/you/.config/start_pro/profiles.exs:

  phoenix_cleanup
  phoenix_defaults
  tooling
  jobs
  deploy_gigalixir
  finish
  standard_app      (uses: phoenix_cleanup, phoenix_defaults, tooling, jobs, deploy_gigalixir if :gigalixir, finish)
```

### `mix start_pro.list.steps <PROFILE>`

Follows every gated include, so it shows everything the profile *can* run.
Steps reached through a gated include are marked `if :flag`, and steps
dropped as duplicates are listed at the end.

```
$ mix start_pro.list.steps standard_app
Profile standard_app (/home/you/.config/start_pro/profiles.exs):

   1. {:remove, :agents_md}  [phoenix_cleanup]
   ...
  21. {:add, :oban_pro, if: :oban_pro}  [jobs]
  22. {:gen, :gigalixir}  [deploy_gigalixir] if :gigalixir
  23. {:gen, :gigalixir_libcluster}  [deploy_gigalixir] if :gigalixir
  24. {:gen, :ecto_force_drop}  [finish]
  25. {:gen, :sort_deps}  [finish]

Flags: --gigalixir --exsync --mix-test-watch --oban-pro
```

### `mix start_pro.run <PROFILE>`

```sh
mix start_pro.run standard_app --gigalixir --dry-run   # preview the diff
mix start_pro.run standard_app --gigalixir             # apply and commit
mix start_pro.run standard_app --no-commit             # no git checks, no commit
```

`--dry-run` and `--yes` work as for any Igniter task. Flags named after
`start_pro.run`'s own options (`config`, `no_commit`) or Igniter's global
options (`yes`, `dry_run`, `verbose`, ...) can't be used as profile flags.

## Git commits: how a run is recorded

`mix start_pro.run` records each run as **one git commit** in the target app.
That commit replaces the in-app starter file you'd get from `starter.new`: it
shows what was applied, from which profile, with which flags.

### What happens during a run

1. **Pre-flight check.** Before anything is written to disk, `start_pro`
   checks that the app is inside a git repository and that the working tree
   is clean: no uncommitted, unstaged or untracked changes. If either check
   fails, the run **refuses to start** and tells you how to fix it. Commit or
   stash your changes, run `git init`, or pass `--no-commit`.
2. **Apply.** `starter`'s runner applies the steps as usual. Dependencies are
   fetched first, then you review one diff for the whole run and confirm it.
3. **Commit.** After the changes are applied, `start_pro` runs
   `git add -A` and `git commit`. The commit runs last, after any queued
   tasks from the profile.

If you use `--dry-run` or decline the diff, nothing is applied and nothing is
committed. Because the tree was clean at the start, the commit contains only
what the run changed.

### The commit message

```
start_pro: apply profile standard_app

Config: /home/andy/.config/start_pro/profiles.exs
Flags: --gigalixir

Steps:
1. {:remove, :daisy_ui} [phoenix_cleanup]
2. {:remove, :topbar} [phoenix_cleanup]
3. {:add, :credo} [tooling]
4. {:gen, :gigalixir} [deploy_gigalixir]
5. {:gen, :sort_deps} [finish]
```

Each step shows the profile it came from, so `git log` or `git show` tells
you exactly how the app was set up.

### One commit per run, not per step

Igniter, which `starter` is built on, builds every step's changes in memory
as one diff and writes them only after you confirm. Between steps nothing is
on disk to commit. Committing after each step would need a separate Igniter
run per step, which means a confirmation prompt, a compile and a dependency
fetch every time. One commit per run, listing every step, gives the same
record without that cost.

### Opting out

```sh
mix start_pro.run standard_app --no-commit
```

With `--no-commit`, `start_pro` skips both the pre-flight git check and the
commit, and behaves like plain `starter`.

## Background

This package grew out of
[starter issue #4](https://github.com/jamilabreu/starter/issues/4). It differs
from that proposal in three ways: it uses `.exs` instead of YAML, it calls a
step list a "profile" instead of an "app", and it adds `{:use, ...}` for
composing profiles.
