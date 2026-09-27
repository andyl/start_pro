# Implementation Plan: Starter Profiles

**Spec:** `_spec/features/260926_starter-profiles.md`
**Generated:** 2026-09-26
**Revised:** 2026-09-26. This revision includes the user's answers to two
rounds of open questions.

---

## Goal

Build `startpro`, a companion Mix package to `starter` (v0.5.x). It loads named
step-list *profiles* from one external `.exs` file and expands `use:`
inclusions, which can be flag-gated, into a flat, acyclic, de-duplicated step
list. It runs that list through `starter`'s existing engine and records what
ran as a git commit in the target app. A small family of `mix startpro.*`
tasks manages the file.

## Scope

### In scope
- Resolving the config path. The order is `-c`, then `STARTPRO_CONFIG`, then
  `$XDG_CONFIG_HOME/startpro/profiles.exs`, then
  `~/.config/startpro/profiles.exs`. The file is then loaded and its shape
  validated.
- A profile resolver. It handles inline `{:use, :name}` and flag-gated
  `{:use, :name, if: :flag}`, and it also expands `{:starter, Module}`
  includes. It detects cycles and missing references, removes duplicates
  (first occurrence wins), and tags each step with its source profile.
- An engine adapter that feeds a resolved list to `Starter.Runner.run/3`
  without any upstream changes.
- A git commit that records each `startpro.run`, made once the run's changes
  are applied.
- Five user-facing Mix tasks: `startpro.config.init`, `startpro.config.edit`,
  `startpro.list.profiles`, `startpro.list.steps` and `startpro.run`. There is
  also one internal task, `startpro.git.commit`.
- A self-documenting default config template, modeled on the starter file
  that `starter.new` generates.
- A README and moduledocs. They must warn clearly that the config is
  evaluated as Elixir, and they describe installing with `path:`/`git:` only.
- Unit and integration tests at the level the spec's testing guidelines ask
  for.

### Out of scope
- Multiple or merged config files, and YAML/TOML/JSON formats.
- Custom step code inside the profile file.
- A `startpro.bootstrap` one-command flow.
- Any change to upstream `starter`.
- Committing after *each step*. Decision 12 explains why. A possible
  `--commit-each` mode is listed as future work.
- Publishing to Hex. The package is used as a `path:`/`git:` dependency only.

## Architecture & Design Decisions

### What the upstream engine gives us (checked against the `starter` v0.5.0 source)
- `Starter.Runner.run(igniter, module, opts)` calls `module.steps()` and
  handles the rest. It flattens `{:starter, M}` includes depth-first,
  evaluates `if:` flags against `opts`, pre-fetches installs, prints the plan,
  and composes each step into **one** Igniter diff that is confirmed once.
- `Starter.flags/1` already accepts a **plain list** of steps.
- The runner owns step validation: it rejects unknown `:remove`/`:gen` names
  and catches likely typos in `:add` names. `startpro` does not duplicate that
  validation.
- The runner supports only a single atom for `if:`. Upstream has no
  AND/OR of flags.
- **Neither `starter` nor its runner makes any git commit.** The only "git"
  references in `lib/` are the `gitignore` and `gigalixir` steps.

### Decisions

1. **The `use:` syntax is an inline step tuple:** `{:use, :name}` or
   `{:use, :name, if: :flag}`. *(Confirmed by the user.)* The included steps
   land exactly where the tuple sits. This mirrors `{:starter, M}` and
   `{:starter, M, if: :flag}`, so the two forms feel the same. `:use` is not a
   valid kind in `Starter.Runner.expand/2`, so it cannot collide with an
   upstream step.

2. **The config is a keyword list, or a map with atom keys, mapping
   `profile_name => [step]`.**

   ```elixir
   [
     base: [{:remove, :daisy_ui}, {:gen, :gitignore}, {:add, :credo}],
     chat_app: [{:use, :base}, {:add, :oban, if: :oban}, MyTeam.Steps.Presence],
     voip_app: [{:use, :chat_app}, {:use, :deploy, if: :gigalixir}, {:add, :membrane}]
   ]
   ```

   The loader turns both forms into an ordered list of `{atom, [step]}`. It
   keeps the order the author wrote in a keyword list, which `list.profiles`
   uses. Duplicate profile keys are an error.

3. **The step list has no duplicates; the first occurrence wins.**
   *(Confirmed: "steps should only run once".)* This is enforced at two
   levels:
   - **Include-once:** within one resolution, a profile or starter module is
     expanded only once. A second `use` of an already-expanded include is a
     no-op, which handles diamonds.
   - **Step de-duplication:** after the list is flattened, a step term equal
     to an earlier step is dropped. Terms that differ only in their `if:`
     count as different steps. `list.steps` reports every dropped duplicate so
     that nothing disappears silently.

4. **Flag-gated includes are evaluated by the resolver, not by rewriting
   `if:`s.** Upstream `if:` takes a single flag. Pushing a gate down onto an
   included step that already has its own `if:` would need AND logic that the
   engine doesn't have. So the resolver takes a `flags` argument:
   - `flags: :all` is used for validation, the flag schema and `list.steps`.
     It follows every gated include, which catches cycles and missing targets
     hidden behind flags, and it records the gate on each included step.
   - `flags: opts` is used by `run`. A gated include whose flag is off is
     skipped **and is not marked done**, so a later ungated `use` of the same
     profile still expands it.

   `run` always does a `:all` pass first, so a bad config fails before anything
   runs, whatever flags were given.

5. **`{:starter, Module}` includes are allowed and expanded by `startpro`.**
   *(Confirmed.)* The resolver treats `{:starter, M}` and
   `{:starter, M, if: :f}` like `use`, getting the child steps from
   `M.steps()`. This extends de-duplication, cycle detection and origin tags
   to shared starter modules. Upstream expands them without any of these
   checks. If `M` can't be loaded (for example, `list.steps` is run where the
   step-pack dep isn't compiled), the step passes through unexpanded with a
   note, and upstream expands it at run time.

6. **Cycle detection is a DFS with an explicit path stack.** Profiles and
   starter modules share one node space, keyed as `{:profile, name}` and
   `{:starter, module}`. Re-entering a node that is on the stack returns
   `{:error, {:cycle, path}}`. The "on stack" and "done" sets are kept
   separate, so a diamond is never mistaken for a cycle.

7. **Every resolved step is tagged with where it came from.** The resolver
   returns entries of the form `%{step: step, origin: name,
   gates: [flag]}`. `list.steps` shows the origin and gates, and `run` strips
   them off.

8. **The engine adapter is a fixed module that reads from
   `:persistent_term`.** `Startpro.Starter` implements the `Starter`
   behaviour. Its `steps/0` reads the resolved list from `:persistent_term`,
   which the adapter sets before calling `Starter.Runner.run/3` and erases in
   an `after` block. This was chosen over generating a module with
   `Module.create/3`: it needs no runtime compilation and avoids "redefining
   module" warnings. `startpro` has already expanded every include, so the
   runner sees a flat list of leaf steps. The only exception is an unloadable
   `{:starter, M}` passed through under decision 5.

9. **`startpro.run` is an `Igniter.Mix.Task`.** This gives it Igniter's diff,
   confirmation and `--yes`/`--dry-run` handling. Its `info/2` receives
   `argv`, so it can resolve the profile early and publish a boolean schema
   entry for every flag. The flag set is the gate flags from decision 4
   combined with `Starter.flags/1` of the resolved steps. The profile is an
   Igniter positional argument.

10. **Config path precedence: `-c/--config`, then `STARTPRO_CONFIG`, then
    `$XDG_CONFIG_HOME/startpro/profiles.exs`, then
    `~/.config/startpro/profiles.exs`.** *(Confirmed.)*

11. **Profile names are matched without creating atoms.** A name typed on the
    command line is compared with each config key's `Atom.to_string/1` form,
    so no atoms are created from user input. Hyphens and underscores are
    treated as equal, the same as `Starter.Steps.resolve/2`.

12. **Git records each run as a single commit, made after the run's changes
    are applied.** The user's idea is that the git log should serve as the
    record of what was run, and it's a good one. The history stays with the
    app, can be reviewed and reverted, and needs no extra file in the repo.
    **However, committing after every step can't be done inside one run.**
    Igniter builds all steps into one in-memory diff and writes it to disk
    only after `igniter/1` returns and the user confirms. Between steps,
    nothing is on disk to commit.

    A per-step mode would need a separate Igniter run for every step, which
    has three costs:
    - N confirmation prompts, or a forced `--yes`.
    - N compile and dependency-fetch cycles. Upstream deliberately fetches
      all installs up front.
    - Losing upstream's single diff for the whole run.

    That trade isn't worth making in v1. What v1 does instead:
    - After `Starter.Runner.run/3` returns, `startpro.run` queues its own
      internal task with `Igniter.add_task/3`. Igniter runs queued tasks only
      after the diff is applied, in the order they were queued, so this one
      runs **last**, after any `{:queue, ...}` steps from the profile. If the
      run is a dry run or the user declines the diff, the task doesn't run.
    - That task is `mix startpro.git.commit --message-file <tmp>`. It runs
      `git add -A` and then `git commit -F <tmp>`. The message's subject is
      `startpro: apply profile <name>`. The body is plain lines (not bullets)
      giving the config path, the flags passed, and the numbered resolved
      steps with their origins. This keeps the documentation benefit that the
      spec's UX note wanted.
    - **Committing is on by default.** *(Confirmed.)* `--no-commit` turns it
      off.
    - **The run refuses to start unless it can make a clean commit.**
      *(Confirmed.)* Preconditions are checked in `igniter/1`, before
      `Starter.Runner.run/3` is called. That means before upstream's
      dependency pre-fetch writes anything to disk. When committing is on:
      - If the target is not inside a git work tree, the run raises and
        suggests `git init` plus an initial commit, or `--no-commit`.
      - If the tree has uncommitted, unstaged or untracked changes, the run
        raises and suggests committing or stashing, or `--no-commit`.

      With `--no-commit`, neither check runs, and the run behaves like plain
      upstream `starter`. No `--allow-dirty` escape hatch is provided. A
      commit that mixed the user's changes with the profile's changes would
      defeat the purpose of the log.
    - Because the tree is clean at the start, the commit contains exactly what
      the run changed. That includes the `mix.exs`/`mix.lock` changes from
      upstream's dependency pre-fetch, which reach disk before the main diff.
    - **Example commit message:**

      ```
      startpro: apply profile standard_app

      Config: /home/andy/.config/startpro/profiles.exs
      Flags: --oban-pro

      Steps:
      1. {:remove, :daisy_ui} [phoenix_cleanup]
      2. {:gen, :gitignore} [phoenix_defaults]
      3. {:add, :credo} [tooling]
      4. {:add, :oban_pro, if: :oban_pro} [jobs]
      5. {:gen, :sort_deps} [finish]
      ```

      This single commit is the app's record of how it was set up, taking the
      place of the in-app starter file used by upstream.

16. **No `mix starter.new` and no in-app starter module.** Upstream's
    `starter.new` only generates `lib/mix/tasks/<app>.starter.ex`, a
    `Starter` module that `mix starter.run` later discovers. `startpro`
    doesn't need either one:
    - The engine adapter (`Startpro.Starter`, decision 8) is the `Starter`
      module, and it lives in the `startpro` dep.
    - `startpro.run` calls `Starter.Runner.run/3` directly.
    - The target app needs `starter` only as a dependency, for the runner and
      its built-in steps.

    The profile in the config file is the source of truth, and the git commit
    is the in-app record. An app that also has a `starter.new` file keeps
    working. The two don't interact, although running both would apply steps
    twice. The README says this explicitly.

13. **Errors are data in the library and raised in the tasks.** Library
    functions return `{:ok, _} | {:error, reason}`. One function,
    `Startpro.Error.message/1`, formats every reason, and the tasks call
    `Mix.raise/1`.

14. **The editor is launched through a `Port` with `:nouse_stdio`.** This lets
    terminal editors such as vim and nvim inherit the TTY. The launcher sits
    behind a small function so tests can replace it.

15. **The package is distributed as a `path:`/`git:` dependency only, and
    requires Elixir `~> 1.17`.** *(Confirmed.)* It has no Hex `package/0`
    metadata. The README install section shows `path:` and `git:` forms.
    `priv/` is included automatically for path and git dependencies.

## Implementation Steps

1. **Project setup and dependencies**
   - Files: `mix.exs`, `.formatter.exs`, `lib/startpro.ex`,
     `test/startpro_test.exs`
   - Details:
     - Set `elixir: "~> 1.17"`.
     - Add `{:starter, "~> 0.5"}`, which brings in `igniter`, and
       `{:ex_doc, only: :dev, runtime: false}` for local docs. Don't add
       `package/0`.
     - Add `import_deps: [:igniter]` to `.formatter.exs`.
     - Replace the `hello/0` stub with a package moduledoc that includes the
       evaluated-code warning. Delete the stub test.
     - Run `mix deps.get` and confirm the project compiles.

2. **Error formatting**
   - Files: `lib/startpro/error.ex`
   - Details: A `message/1` function that formats each of these reasons:
     - `:config_not_found`
     - `{:config_eval, exception}`
     - `{:invalid_shape, term}`
     - `{:invalid_profile, name, term}`
     - `{:duplicate_profile, name}`
     - `{:unknown_profile, name, available}`
     - `{:missing_use, from, target}`
     - `{:invalid_use, from, term}`
     - `{:cycle, path}`
     - `{:not_a_starter, module}`

     Unknown-profile errors list the available names. Cycle errors print the
     path, e.g. `a -> b -> MyTeam.Baseline -> a`.

3. **Config path resolution and loading**
   - Files: `lib/startpro/config.ex`
   - Details:
     - `path/1` applies decision 10, reading `System.get_env/1` for the
       `STARTPRO_CONFIG` and `XDG_CONFIG_HOME` variables.
     - `load/1` checks `File.regular?/1` first. It then runs
       `Code.eval_file/1`, rescuing syntax, tokenizer, compile and runtime
       errors into `{:config_eval, e}`.
     - The result is normalized and validated:
       - it is a keyword list or map with atom keys and list values;
       - there are no duplicate keys;
       - every `{:use, x}` and `{:use, x, opts}` has an atom `x`, and any
         `if:` is a single atom.

       Other step shapes are left for the upstream runner to validate.
     - `find_profile/2` matches names as described in decision 11.

4. **Profile resolver**
   - Files: `lib/startpro/resolver.ex`
   - Details: `resolve(profiles, name, flags: :all | keyword)` returns either
     `{:ok, %{steps: [entry], duplicates: [entry], gates: [flag]}}` or
     `{:error, reason}`. It runs a DFS over nodes of the form
     `{:profile, name}` and `{:starter, module}`, carrying the stack, the
     `done` set and the current gates. Each step is handled in order:
     - `{:use, t}` / `{:use, t, if: f}`: skip it if it is gated and the flag
       is off. Skip it if `t` is already done. Otherwise raise an error on a
       cycle or a missing target, and recurse with `f` added to the gates.
     - `{:starter, m}` / `{:starter, m, if: f}`: the same, using `m.steps()`
         when `Code.ensure_loaded?(m)` and `function_exported?(m, :steps, 0)`
         are true. Otherwise pass the step through unexpanded.
     - Any other step is emitted as an entry.

     After the walk, the steps are de-duplicated by term, with the first
     occurrence winning, and the dropped entries go into `duplicates`.

     Helpers: `uses/2` returns a profile's direct includes for
     `list.profiles`. `flags/1` returns the gate flags combined with
     `Starter.flags/1` of the leaf steps. `steps_only/1` strips the entry
     metadata.

5. **Engine adapter**
   - Files: `lib/startpro/starter.ex`
   - Details: A module with `@behaviour Starter`. Its `steps/0` reads
     `:persistent_term.get({Startpro, :steps}, [])`, and its
     `run(igniter, steps, opts)` puts the list, calls `Starter.Runner.run/3`
     and erases the list in `try/after`. This is the only coupling to
     upstream runner internals.

6. **Shared CLI helpers**
   - Files: `lib/startpro/cli.ex`
   - Details:
     - Parse the `-c/--config` option.
     - `load_profile!/3` parses, loads, finds the profile, resolves it and
       raises on error. Every task uses it.
     - Render entries with `inspect/2` using `pretty: true`, adding the origin
       and gates, e.g. `4. {:add, :oban}   [chat_app] if :oban`.
     - Check whether `-c` or `--config` collides with an Igniter global
       option. If one does, use only `--config` for `startpro.run` and
       document it.

7. **Git helpers and internal commit task**
   - Files: `lib/startpro/git.ex`, `lib/mix/tasks/startpro.git.commit.ex`
   - Details:
     - `Startpro.Git.status/1` returns `:not_a_repo`, `:clean` or `:dirty`,
       using `git rev-parse --is-inside-work-tree` and
       `git status --porcelain`.
     - `Startpro.Git.message/3` takes the profile, flags and entries and
       builds the commit text: a subject under 72 characters, then plain-line
       body text with no bullets.
     - `mix startpro.git.commit --message-file PATH` runs `git add -A` and
       `git commit -F PATH`, then deletes the temp file. It reports but
       tolerates the "nothing to commit" case, which happens when the profile
       made no changes. Mark it `@moduledoc false`, with no `@shortdoc`, so
       that `mix help` hides it.

8. **Default config template**
   - Files: `priv/templates/profiles.exs`
   - Details: A commented, valid `.exs` file modeled on the groups that
     `starter.new` generates: removals, generators, adds, deployment and
     finishing. *(The user's answer: something similar to what `starter`
     itself uses.)*
     - The comments explain every step form, `{:use, :x}`,
       `{:use, :x, if: :f}`, `{:starter, M}`, `if:` flags, custom step
       modules (which must be deps of the target app), de-duplication, and
       the fact that each run is committed to git.
     - Suggested profiles:
       - `phoenix_cleanup`: the `:remove` steps.
       - `phoenix_defaults`: the `:gen` steps.
       - `tooling`: credo, quokka, dotenv_parser, `exsync` gated behind
         `if: :exsync`, and `mix_test_watch` gated behind
         `if: :mix_test_watch`.
       - `jobs`: oban, oban_web, and oban_pro gated behind `if: :oban_pro`.
       - `deploy_gigalixir`: the gigalixir gens.
       - `finish`: ecto_force_drop and sort_deps.
       - `standard_app`: uses cleanup, defaults, tooling and jobs, then
         `{:use, :deploy_gigalixir, if: :gigalixir}`, then
         `{:use, :finish}` last.
     - Use only built-in upstream step names, so the template resolves
       without extra deps.

9. **`mix startpro.config.init`**
   - Files: `lib/mix/tasks/startpro.config.init.ex`
   - Details: Resolves the path and refuses if the file exists, unless
     `--force` is given. It runs `File.mkdir_p!` on the parent directory, then
     copies the template from
     `Application.app_dir(:startpro, "priv/templates/profiles.exs")`. Finally
     it prints the path and suggests `config.edit`.

10. **`mix startpro.config.edit`**
    - Files: `lib/mix/tasks/startpro.config.edit.ex`, `lib/startpro/editor.ex`
    - Details: Resolves the path. If the file is missing, it raises with a
      hint to run `config.init`. It uses `$EDITOR`, then `$VISUAL`, and
      raises if neither is set. `Startpro.Editor.open/2` runs
      `sh -c '$EDITOR "$1"' -- file` through a `Port` with
      `[:nouse_stdio, :exit_status]`, and a non-zero exit raises. After the
      edit, it re-loads the file and resolves every profile with
      `flags: :all`. If validation fails, it prints a warning but does not
      fail.

11. **`mix startpro.list.profiles`**
    - Files: `lib/mix/tasks/startpro.list.profiles.ex`
    - Details: Prints a header with the config path, then one line per
      profile in config order, with its direct includes and gates, e.g.
      `standard_app  (uses: phoenix_cleanup, tooling, deploy_gigalixir if :gigalixir, finish)`.

12. **`mix startpro.list.steps <PROFILE>`**
    - Files: `lib/mix/tasks/startpro.list.steps.ex`
    - Details: Takes exactly one positional argument. It resolves with
      `flags: :all` and prints the numbered entries with their origin and
      gates. The footer lists the available flags and each de-duplicated step
      with the profile it was dropped from. It must not touch Igniter.

13. **`mix startpro.run <PROFILE>`**
    - Files: `lib/mix/tasks/startpro.run.ex`
    - Details: `use Igniter.Mix.Task`.
      - `info(argv, _)` pre-parses `argv` for the config and the profile. It
        resolves with `flags: :all`, raising on any error, and returns an
        `Info` whose schema is:
        - `positional: [:profile]`;
        - `config: :string` and `no_commit: :boolean`;
        - one boolean for each flag.

        If the profile is absent, it returns the base schema.
      - `igniter/1`:
        1. Re-resolve with `flags: :all` as a validation pass, then again with
           `flags: igniter.args.options`.
        2. Unless `--no-commit` was given, call `Startpro.Git.status/1` and
           `Mix.raise` on `:not_a_repo` or `:dirty`, as described in
           decision 12. This must happen before step 3, so that nothing
           reaches disk.
        3. Call `Startpro.Starter.run/3`.
        4. If committing, write the message to a temp file with
           `System.tmp_dir!/0` and a unique name, and run
           `Igniter.add_task(igniter, "startpro.git.commit",
           ["--message-file", path])`.
      - In the moduledoc, document three things: `startpro` and `starter`
        must both be deps of the target app, `starter.new` is not needed, and
        how the commit behavior works.

14. **Documentation**
    - Files: `README.md`, moduledocs on every public task
    - Details: A first draft of the README was written during planning. It
      describes the intended behavior, including the git commit workflow and
      why `starter.new` is not needed. Update it to match the final CLI
      output and option names. It should cover the following.
      - Installing with `path:`/`git:` as an `only: :dev` dep alongside
        `starter`.
      - Config location and precedence.
      - Config syntax.
      - `{:use, ...}` semantics: in place, include-once, gated, no cycles.
      - `{:starter, M}` support.
      - De-duplication.
      - The git commit behavior and its flags.
      - Each task with an example.
      - The evaluated-code warning.
      - How this relates to upstream step packs and issue #4.
      - That each run makes one commit, not one commit per step, and why.
      - That the run refuses to start in a dirty tree or outside a repo.
      - That no `starter.new` file or in-app starter module is needed.

      Each public task also needs `@shortdoc`.

15. **Tests** (see Testing Strategy)
    - Files: `test/startpro/config_test.exs`,
      `test/startpro/resolver_test.exs`, `test/startpro/git_test.exs`,
      `test/mix/tasks/startpro_config_test.exs`,
      `test/mix/tasks/startpro_list_test.exs`,
      `test/mix/tasks/startpro_run_test.exs`, `test/support/fixtures/*.exs`,
      and `test/support/fake_starter.ex` (a `Starter` module used to test
      `{:starter, M}` expansion)

## Dependencies & Ordering

- Step 1 comes first, because every later step needs `starter` and `igniter`
  compiled.
- Step 2 comes before steps 3, 4 and 7, which return the reasons it formats.
- Step 3 comes before step 4. Both come before step 6, and step 6 comes
  before every task.
- Step 4 is the core of the package, so give it thorough unit tests before
  building on it. Gated includes, include-once, de-duplication and cycle
  detection all interact there.
- Steps 5 and 7 depend only on step 1, but both matter only for step 13.
- Step 8 comes before step 9. The template must pass steps 3 and 4 for every
  profile, and a test enforces this.
- Steps 9 to 12 can be built in any order once step 6 exists.
- Step 13 is the riskiest, so build it last among the tasks. Verify the
  `Igniter.add_task/3` ordering and dry-run behavior early, as the first thing
  done in that step.
- Step 14 comes last. Write tests alongside each step.

## Edge Cases & Risks

- **Cycles, including through `{:starter, M}` or hidden behind a gate:** the
  `flags: :all` validation pass always runs first. The error shows the full
  path.
- **Diamond inclusion:** include-once handles it, and a test checks it is not
  reported as a cycle.
- **A gated include is skipped, then the same profile is used ungated
  later:** it must still expand, because a skipped include is not marked
  done. Test this case explicitly.
- **De-duplication moves "finishing" steps:** under first-wins,
  `{:gen, :sort_deps}` inside a baseline profile runs at the baseline's
  position, not at the end. The template avoids this by keeping finishing
  steps in a `finish` profile used last. The README explains the pattern,
  and `list.steps` shows the final positions.
- **Near-duplicates with different `if:`:** treated as distinct steps.
  Upstream still dedupes the package installs, so the risk is low.
- **Missing `use:` target or an unknown CLI profile:** each gets a distinct
  error that lists the available profiles.
- **Empty, broken or wrong-shape config:** rescued in `Config.load/1`.
- **An empty profile:** allowed. `run` makes no changes. The git commit task
  reports "nothing to commit" without failing.
- **`-c` is a directory or doesn't exist:** caught by `File.regular?/1`.
- **A custom step or starter module is missing from the target app:**
  `list.steps` passes it through with a note. In `run`, pre-check it with
  `Code.ensure_loaded?/1` and give an error that names the profile.
- **Evaluating arbitrary code:** accepted by design. Document it, and only
  evaluate the config inside tasks.
- **Upstream API drift:** `Starter.Runner.run/3` and `Starter.flags/1` could
  change. Pin `~> 0.5`, keep all coupling in `Startpro.Starter`, and cover it
  with the integration test.
- **Igniter queued-task semantics:** confirm that `add_task` runs only after a
  confirmed apply, is skipped on `--dry-run` or a declined diff, and runs as a
  subprocess in the target app. `startpro` is a dep there, so the task
  exists. If the task does run on a declined diff, the commit task finds
  nothing to commit, which is harmless.
- **A dirty tree would mix the user's changes into the commit:** the run
  refuses to start unless `--no-commit` is passed. The check happens before
  upstream's dependency pre-fetch, so nothing is written.
- **A fresh `mix phx.new` app is not a git repo:** the run refuses and the
  error gives the exact fix, `git init && git add -A && git commit -m
  "Initial commit"`, or suggests `--no-commit`. The README quick start
  includes this step.
- **The git binary is missing:** `Startpro.Git.status/1` treats this as
  `:not_a_repo`, so the run refuses unless `--no-commit` is passed.
- **Untracked files count as dirty:** this matches the `/gen-feat` workflow
  and `git status --porcelain`. Ignored files (those in `.gitignore`) do not
  count.
- **`starter.new` was also run in the same app:** the two don't interact, but
  running both would apply steps twice. This is documented in the README.
- **Commit message length:** the subject is kept under 72 characters, and the
  profile name is truncated if needed.
- **`:persistent_term` leaking between runs:** always cleared in `after`.
  Tests that touch it run with `async: false`.
- **Igniter option collisions** (`-c`, `--config`, `--no-commit`): check
  these against the installed Igniter.
- **The editor doesn't get a TTY:** needs a manual check with vim and nvim.
  GUI editors need their own `--wait` flag, and the docs should say so.

## Testing Strategy

- **Config unit tests** (fixtures under `test/support/fixtures/`):
  - a keyword-list config and a map config, both valid;
  - a missing path, a directory, and a syntax error;
  - an empty file, a non-list value, and a non-atom key;
  - duplicate profiles;
  - a malformed `{:use, "x"}` and a `{:use, :x, if: [:a, :b]}`;
  - path precedence across `-c`, `STARTPRO_CONFIG`, `XDG_CONFIG_HOME` and
    the default. Tests that change environment variables restore them and
    run with `async: false`.
- **Resolver unit tests** (in-memory profiles, plus `FakeStarter`):
  - a profile with no `use`, and one with a single in-place `use`;
  - nested includes three levels deep;
  - a diamond that expands once, at its first position;
  - exact-duplicate steps dropped and reported;
  - a gated include with the flag on and with it off;
  - a gated-off include that still expands through a later ungated `use`;
  - a cycle hidden behind a gate, caught by `flags: :all`;
  - direct cycles, three-node cycles, and cycles through `{:starter, M}`,
    each checked for the exact path;
  - a missing target;
  - `{:starter, M}` expansion, and pass-through when `M` can't be loaded;
  - origin and gate annotations;
  - `flags/1` combining gate flags with `if:` flags.
- **Git tests** use `@tag :tmp_dir` with a real `git init`:
  - `status/1` reports `:not_a_repo`, `:clean` and `:dirty` correctly;
  - `message/3` output has a subject under 72 characters and no bullet
    lines;
  - `startpro.git.commit` creates a commit with the expected message, and
    tolerates having nothing to commit.
- **Task tests** use `Mix.Tasks.*.run/1`, `CaptureIO` and tmp dirs:
  - `config.init` writes a file, every template profile resolves under
    `flags: :all`, and a second run is refused without `--force`;
  - the output of `list.profiles` and `list.steps`, including gates and
    duplicates;
  - unknown profiles and cycles raise `Mix.Error`;
  - `config.edit` with `EDITOR=true` and with no editor set.
- **Run integration test** uses `Igniter.Test.test_project/0` and
  `Igniter.compose_task("startpro.run", [...])`:
  - use only built-in `:gen`/`:remove` steps, because installs are inert in
    test mode;
  - assert file changes for a resolved profile;
  - a flagged step and a gated `use` are each skipped without their flag and
    applied with it;
  - a `startpro.git.commit` task is queued when committing is enabled, and
    none is queued with `--no-commit`. Use Igniter's test assertions for
    queued tasks if they exist, otherwise inspect `igniter.tasks`;
  - the run raises `Mix.Error` when the directory is not a repo or the tree
    is dirty, and runs when `--no-commit` is passed. Inject the git status
    check, or run inside a tmp-dir repo, so the test doesn't depend on the
    real working tree.
- **Manual checks** in a fresh `mix phx.new` app that is a git repo, with
  `startpro` as a `path:` dep:
  - run `config.init`, `config.edit` (in vim), `list.profiles`,
    `list.steps standard_app`, and `run standard_app --dry-run`;
  - then run `run standard_app`, check that exactly one commit is created,
    and inspect `git log -1`;
  - confirm that a dirty tree and a non-repo directory are both refused with
    nothing written, and that `--no-commit` runs in both cases.

## Open Questions

None blocking. Two items should be verified early in step 13: Igniter's
queued-task semantics and option name collisions (see Edge Cases & Risks).

### Resolved (second round)
- Git commits are on by default. `--no-commit` opts out.
- If committing is on and the tree is dirty or not a repo, the run refuses to
  start. There is no `--allow-dirty` flag.
- One commit per run is enough, and there's no `--commit-each` mode. The
  commit message lists every resolved step.
- De-duplication treats steps that differ only in `if:` as distinct.
- `mix starter.new` is not used. `startpro` needs `starter` only as a
  dependency (decision 16).

### Resolved (first round)
- The `use:` syntax is the inline `{:use, :name}` tuple.
- Diamond and duplicate steps run only once, with the first occurrence
  winning.
- Flag-gated `{:use, :name, if: :flag}` is in v1.
- `{:starter, Module}` includes are allowed.
- `STARTPRO_CONFIG` and `XDG_CONFIG_HOME` are both supported.
- The minimum Elixir version drops to `~> 1.17`.
- The package is distributed with `path:`/`git:` only, not Hex.
- The template is modeled on the file `starter.new` generates.
- Recording the resolved list uses the git log (one commit per run) instead
  of a file in the app.
