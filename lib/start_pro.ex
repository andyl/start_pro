defmodule StartPro do
  @moduledoc """
  Named step-list profiles for [`starter`](https://hexdocs.pm/starter).

  `start_pro` keeps your starter step lists as named **profiles** in one
  config file outside your projects (by default
  `~/.config/start_pro/profiles.exs`). Profiles compose with `{:use, :name}`
  and `{:use, :name, if: :flag}`, and are resolved into one flat, acyclic,
  de-duplicated step list that is run through `starter`'s own engine. Each run
  is recorded as a single git commit in the target app.

  > #### Warning {: .warning}
  >
  > The config file is Elixir code, and `start_pro` evaluates it with
  > `Code.eval_file/1`. Only use a config file you wrote or trust.

  ## Tasks

    * `mix start_pro.config.init` - create the config file from a template
    * `mix start_pro.config.edit` - open the config file in `$EDITOR`
    * `mix start_pro.list.profiles` - list profiles and their includes
    * `mix start_pro.list.steps PROFILE` - show a profile's resolved steps
    * `mix start_pro.run PROFILE` - apply a profile and commit the result

  ## Modules

    * `StartPro.Config` - locates, loads and validates the config file
    * `StartPro.Resolver` - expands includes into a flat step list
    * `StartPro.Starter` - feeds a resolved list to `Starter.Runner`
    * `StartPro.Git` - pre-flight checks and the commit message
  """
end
