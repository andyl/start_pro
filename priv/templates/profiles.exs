# start_pro profiles
#
# WARNING: this file is Elixir code and is evaluated by start_pro. Only use a
# config file you wrote or trust.
#
# The file evaluates to a keyword list of `profile_name: [steps]`. Apply a
# profile to the current app with:
#
#     mix start_pro.list.steps standard_app     # preview the resolved steps
#     mix start_pro.run standard_app            # apply them and commit
#
# ## Step forms
#
# Steps use starter's syntax (https://hexdocs.pm/starter):
#
#   * `{:remove, :topbar}`      - undo a phx.new default
#   * `{:gen, :gitignore}`      - generate configuration or code
#   * `{:add, :credo}`          - get a package into the app: starter's own
#                                 step when it has one, else the package's
#                                 installer
#   * `{:task, "some.task"}`    - compose any Igniter-aware Mix task
#   * `{:queue, "some.task"}`   - run a Mix task after the changes apply
#   * `{:starter, MyTeam.Base}` - include a starter module's steps
#   * `MyTeam.Steps.Custom`     - a custom step module. It must be a
#                                 dependency of the target app; step code
#                                 cannot live in this file.
#
# start_pro adds one more form, a step from a registry package such as
# start_reg (https://github.com/andyl/start_reg):
#
#   * `{:add, :ash, from: StartReg}` - runs Mix.Tasks.StartReg.Add.Ash.
#                                 The kind is :add, :gen or :remove; the
#                                 registry must be a dependency of the app.
#
# Browse the built-in steps with `mix starter.add --list`,
# `mix starter.remove --list` and `mix starter.gen --list`.
#
# ## Flags
#
# Tag a step with `if: :flag` to make it optional. It runs only when the flag
# is passed, e.g. `mix start_pro.run standard_app --oban-pro`.
#
# ## Including profiles
#
#   * `{:use, :name}` includes another profile's steps in place.
#   * `{:use, :name, if: :flag}` includes them only when `--flag` is passed.
#
# Includes nest to any depth. Cycles are an error. A profile included twice
# expands only at its first position, and exact duplicate steps are dropped
# (first occurrence wins), so keep finishing steps like `{:gen, :sort_deps}`
# in a profile that is used last.
#
# ## Git
#
# `mix start_pro.run` refuses to start outside a git repository or in a dirty
# work tree, and records each run as one commit listing every step. Pass
# `--no-commit` to skip both.

[
  # Undo phx.new defaults you don't want
  phoenix_cleanup: [
    {:remove, :agents_md},
    {:remove, :daisy_ui},
    {:remove, :live_title_suffix},
    {:remove, :theme_toggle},
    {:remove, :topbar}
  ],

  # Generate configuration and code
  phoenix_defaults: [
    {:gen, :minimal_app_layout},
    {:gen, :minimal_home_page},
    {:gen, :tailwind_formatter},
    {:gen, :gitignore},
    {:gen, :pg_extensions},
    {:gen, :generator_defaults},
    {:gen, :base_schema},
    {:gen, :mix_env_config}
  ],

  # Development tooling
  tooling: [
    {:add, :credo},
    {:add, :quokka},
    {:add, :dotenv_parser},
    {:add, :exsync, if: :exsync},
    {:add, :mix_test_watch, if: :mix_test_watch}
  ],

  # Background jobs
  jobs: [
    {:add, :oban},
    {:add, :oban_web},
    # Patches what oban's installer wrote, so it follows it in the list.
    {:add, :oban_pro, if: :oban_pro}
  ],

  # Deployment
  deploy_gigalixir: [
    {:gen, :gigalixir},
    {:gen, :gigalixir_libcluster}
  ],

  # Tidy mix.exs
  finish: [
    {:gen, :ecto_force_drop},
    # Last, so it also sorts the deps the steps above added
    {:gen, :sort_deps}
  ],

  # A complete setup, composed from the profiles above
  standard_app: [
    {:use, :phoenix_cleanup},
    {:use, :phoenix_defaults},
    {:use, :tooling},
    {:use, :jobs},
    {:use, :deploy_gigalixir, if: :gigalixir},
    {:use, :finish}
  ]
]
