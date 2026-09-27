# Feature Specification: Starter Profiles

## Overview

`start_pro` is a companion package to
[`starter`](https://github.com/jamilabreu/starter). It adds **starter
profiles**, which are named step lists kept in one external `.exs` config file
outside any project codebase. A developer defines profiles such as `chat_app`
or `voip_app` once. He can then apply any profile to a new Phoenix/Igniter
project with `mix start_pro.run <PROFILE>`. The developer no longer has to copy
a starter module into each project or keep a separate step-pack Mix project
just to hold a list.

The idea comes from `starter` issue #4
(https://github.com/jamilabreu/starter/issues/4), with these changes:

- The config format is `.exs`, not YAML.
- A step list is called a "profile", not an "app".
- A `use:` directive lets one profile include another.

The design intent is that **the profile is the source of truth**. `start_pro`
complements upstream `starter`'s "app owns its setup" model and does not
replace it.

## Goals

- Keep reusable starter step lists in one central, git-trackable config file
  outside any project.
- Let profiles build on each other through a `use:` directive, so shared
  baselines are defined only once.
- Use the same step tuple syntax as the `starter` README (e.g. `{:add, :credo}`,
  `{:remove, :topbar, if: :x}`), so examples can be pasted in directly.
- Provide a small set of Mix tasks to create, edit, inspect and run profiles.
- Ship as a separate package that depends on `starter`, with no upstream
  changes required.

Success criteria:

- A user can run `mix start_pro.config.init`, edit the file, and run
  `mix start_pro.run <PROFILE>` in a fresh project. The result is the same as
  running an equivalent hand-written starter module.
- Cyclic `use:` references are detected and reported before any step runs.

## Functional Requirements

### Config file

- The default location is `~/.config/start_pro/profiles.exs`.
- Every task accepts `-c <config_file_path>` to override the location.
- Only one config file is active for any command. Merging multiple config files
  is not supported.
- The file is an Elixir `.exs` file that evaluates to a keyword list (or map)
  of `profile_name => [steps]`.
- Steps use exactly the tuple syntax that `starter` accepts, including `if:`
  flags, `{:starter, Module}` includes, and references to custom step modules.
- Custom steps are *referenced* by module name only. Their code lives in
  standalone packages/modules that are available to the target project, never
  inside the profile file.

### Profile inclusion (`use:`)

- A profile may include one or more other profiles with a `use:` directive.
  The included profile's steps expand in place, at the position where `use:`
  appears.
- Inclusion may be nested to any depth.
- The fully expanded inclusion graph must be acyclic. A cycle, whether direct
  (`a` uses `a`) or indirect (`a → b → c → a`), is an error. The error names
  the profiles in the cycle.
- A `use:` pointing to a profile that does not exist is an error, and the error
  names the missing profile.

### Mix tasks

| Task                                | Behavior                                                                                                                                                                         |
|-------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `mix start_pro.config.init`          | Creates a default config file with pre-populated example profiles. Refuses to overwrite an existing file unless a force option is given. Creates parent directories as needed.   |
| `mix start_pro.config.edit`          | Opens the config file in `$EDITOR` (falling back to `$VISUAL`, then reporting an error if neither is set). If no config file exists, suggests running `config.init`.             |
| `mix start_pro.list.profiles`        | Lists all profile names in the config file, with any profiles each one uses.                                                                                                     |
| `mix start_pro.list.steps <PROFILE>` | Prints the fully expanded, ordered step list for the profile, after `use:` resolution.                                                                                           |
| `mix start_pro.run <PROFILE>`        | Resolves the profile and runs its expanded steps through `starter`'s engine inside the current project. Forwards `starter` flags (e.g. `--flag`-style `if:` toggles) to the run. |

- All tasks accept `-c <path>`.
- All tasks print a helpful message and exit non-zero when the config file is
  missing, cannot be evaluated, is malformed, or when the named profile is
  unknown.

## Non-Functional Requirements

- **No upstream changes.** `start_pro` must work against the published `starter`
  package as a dependency. It adapts to the engine's module-based API where
  needed.
- **Dev-only.** `start_pro` is intended as an `only: :dev` dependency, the same
  as `starter`.
- **Safety.** The config file is trusted user-authored Elixir code. The docs
  must say plainly that it is evaluated.
- **Clear errors.** Config and resolution errors must point at the profile
  and, where possible, the offending entry.
- **Fast resolution.** Loading and expanding profiles should feel instant for
  realistic config sizes (dozens of profiles).

## Design / UX Notes

- The CLI mirrors the naming in issue #4: `start_pro.config.*`,
  `start_pro.list.*`, `start_pro.run`.
- The generated default config should be self-documenting. It should include
  comments that explain the step syntax, `use:`, `if:` flags, and custom step
  references, plus at least two example profiles where one `use:`s the other.
- `list.steps` output should be readable and should show which profile each
  step came from, to help debug inheritance.
- Consider having `start_pro.run` optionally record the resolved step list into
  the target app (as a comment or file). That keeps upstream's "the app
  documents its own setup" benefit. See Open Questions.

## Technical Approach

- **Architecture:** a thin companion package that depends on `starter`. It
  handles config loading, profile resolution, and the Mix task surface, and it
  delegates actual step execution to `starter`'s engine.
- **Key components:**
  - Config loader: locates, evaluates and validates the `.exs` file.
  - Profile resolver: expands `use:` directives depth-first, detects cycles and
    missing references, and produces a flat ordered step list.
  - Engine adapter: presents a resolved step list to `starter`'s runner, which
    currently expects a module that exposes `steps/0`.
  - Mix tasks: the five tasks listed above, with shared `-c` option handling.
- **Dependencies:** `starter` (and transitively `igniter`). No YAML or other
  parsing dependency is needed.
- **Constraint:** `starter` (and `start_pro`) must be deps of the target app,
  because Igniter runs inside the project. This is documented, not solved.

## Possible Edge Cases

- A profile uses itself directly.
- An indirect cycle across three or more profiles.
- A diamond inclusion (`a` uses `b` and `c`, and both use `base`). This is not
  a cycle. The spec should define whether duplicate steps from `base` run once
  or twice (see Open Questions).
- `use:` names a nonexistent profile.
- The config file exists but is empty, has a syntax error, or evaluates to the
  wrong shape.
- A profile name is given as a string on the CLI but stored as an atom in
  config (or the reverse).
- A profile is defined with an empty step list.
- A custom step module is referenced but not available in the target project.
- `-c` points to a nonexistent path or a directory.
- `$EDITOR` is unset, or the editor command fails.
- `config.init` runs when a config already exists.
- `start_pro.run` runs outside a Mix project, or in a project without `starter`
  as a dep.

## Acceptance Criteria

- `mix start_pro.config.init` creates `~/.config/start_pro/profiles.exs` (or the
  `-c` path) with valid example profiles, and does not clobber an existing
  file without explicit force.
- `mix start_pro.config.edit` opens the active config in `$EDITOR`.
- `mix start_pro.list.profiles` lists every profile in the active config.
- `mix start_pro.list.steps <PROFILE>` shows the correctly ordered, fully
  expanded steps, including steps pulled in through nested `use:`.
- `mix start_pro.run <PROFILE>` applies the expanded steps to the current
  project through `starter`, and respects `if:` flags passed on the CLI.
- Any cycle in `use:` references is rejected before execution, with a message
  that names the cycle path.
- Unknown profiles and missing `use:` targets give clear errors and a non-zero
  exit.
- Every task honors `-c <path>`.

## Open Questions

- In diamond inclusions, should duplicate steps be de-duplicated (first
  occurrence wins) or kept as written?  ANSWER: de-duplicate
- What is the exact syntax of `use:` inside a profile? Options include a
  `{:use, :profile}` tuple placed inline in the step list, or a profile-level
  option (e.g. `chat_app: [use: [:base], steps: [...]]`). An inline tuple keeps
  ordering explicit. ANSWER: I like the inline tuple
- Should `start_pro.run` record the resolved step list into the target app for
  documentation? If so, where and in what form?  ANSWER: the git commit log should do this.  I think (hope) that the `starter` app does a git commit after each step.  Please check this.  If not: let's decide if we should let 'start_pro.run' task do a git commit after each step.
- Should profiles also be able to use `starter`'s `{:starter, Module}`
  includes, or should `use:` be the only inclusion mechanism?  ANSWER: yes, let's allow for {:starter, Module} 
- Should the `STARTER_CONFIG`-style env var from the earlier discussion be
  supported (e.g. `START_PRO_CONFIG`) in addition to `-c`?  ANSWER: yes great idea - let's use START_PRO_CONFIG environment variable
- What should the pre-populated profiles in `config.init` contain?  ANSWER: something similar to what `starter` itself uses 

## Out of Scope

- Support for multiple or merged config files.
- YAML, TOML or JSON config formats.
- Defining custom step *code* inside the profile file.
- A one-command bootstrap flow (e.g. `mix start_pro.bootstrap my_app chat_app`
  that runs `igniter.new`/`phx.new`, adds deps, and runs the profile).
- Changes to, or PRs against, the upstream `starter` package.
- Removing the need to add `starter`/`start_pro` as a dep of the target app.

## Testing Guidelines

Create meaningful tests for the following use cases, without going too heavy:

- Loading a valid config file from a custom `-c` path, and handling missing,
  malformed and wrong-shape files.
- Resolving a profile with no `use:`, with a single `use:`, with nested
  `use:`, and with a diamond inclusion.
- Detecting direct and indirect cycles, and reporting the cycle path.
- Reporting an unknown profile and a missing `use:` target.
- `config.init` writes a file that loads and resolves cleanly, and refuses to
  overwrite an existing file.
- `list.profiles` and `list.steps` produce the expected output for a fixture
  config.
- `start_pro.run` hands the correctly expanded step list to the `starter` engine
  (verified at the adapter boundary, without running real installers).
