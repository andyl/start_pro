[
  base: [{:remove, :daisy_ui}, {:gen, :gitignore}],
  app: [{:use, :base}, {:add, :oban, if: :oban}, {:use, :deploy, if: :gigalixir}],
  deploy: [{:gen, :gigalixir}]
]
