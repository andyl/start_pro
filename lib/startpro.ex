defmodule Startpro do
  @moduledoc """
  Named step-list profiles for [`starter`](https://hexdocs.pm/starter).

  `startpro` keeps your starter step lists as named **profiles** in one
  config file outside your projects (by default
  `~/.config/startpro/profiles.exs`). Profiles compose with `{:use, :name}`
  and `{:use, :name, if: :flag}`, and are resolved into one flat, acyclic,
  de-duplicated step list that is run through `starter`'s own engine. Each run
  is recorded as a single git commit in the target app.

  > #### Warning {: .warning}
  >
  > The config file is Elixir code, and `startpro` evaluates it with
  > `Code.eval_file/1`. Only use a config file you wrote or trust.

  ## Tasks

    * `mix startpro.config.init` - create the config file from a template
    * `mix startpro.config.edit` - open the config file in `$EDITOR`
    * `mix startpro.list.profiles` - list profiles and their includes
    * `mix startpro.list.steps PROFILE` - show a profile's resolved steps
    * `mix startpro.run PROFILE` - apply a profile and commit the result

  ## Modules

    * `Startpro.Config` - locates, loads and validates the config file
    * `Startpro.Resolver` - expands includes into a flat step list
    * `Startpro.Starter` - feeds a resolved list to `Starter.Runner`
    * `Startpro.Git` - pre-flight checks and the commit message
  """
end
