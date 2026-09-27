# Used by "mix format"
[
  import_deps: [:igniter],
  # test/support/fixtures holds deliberately broken configs, so it's excluded.
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib}/**/*.{ex,exs}",
    "test/*.exs",
    "test/{startpro,mix}/**/*.exs",
    "test/support/*.ex"
  ]
]
