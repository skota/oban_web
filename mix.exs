defmodule ObanWeb.MixProject do
  use Mix.Project

  @version "1.5.0"

  def project do
    [
      app: :oban_web,
      version: @version,
      elixir: "~> 1.8",
      compilers: [:phoenix] ++ Mix.compilers(),
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      package: package(),
      description: "Oban Web Component",
      preferred_cli_env: [
        "test.ci": :test,
        "test.reset": :test,
        "test.setup": :test
      ],

      # Docs
      name: "ObanWeb",
      docs: [
        main: "Readme",
        source_ref: "v#{@version}",
        source_url: "https://github.com/sorentwo/oban_web",
        extras: ["README.md", "CHANGELOG.md"]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def package do
    [
      organization: "oban",
      files: ~w(lib .formatter.exs mix.exs README* CHANGELOG*),
      licenses: ["Commercial"],
      links: []
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.2"},
      {:oban, "~> 2.0.0-rc.0"},
      {:oban_pro, "~> 0.1", organization: "oban"},
      {:phoenix, "~> 1.5"},
      {:phoenix_html, "~> 2.14"},
      {:phoenix_pubsub, "~> 2.0"},
      {:phoenix_live_view, "~> 0.13"},
      {:credo, "~> 1.4", only: [:test, :dev], runtime: false},
      {:floki, "~> 0.26", only: :test},
      {:ex_doc, "~> 0.21", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      "test.reset": ["ecto.drop -r ObanWeb.Repo", "test.setup"],
      "test.setup": ["ecto.create -r ObanWeb.Repo --quiet", "ecto.migrate -r ObanWeb.Repo"],
      "test.ci": ["format --check-formatted", "credo --strict", "test --raise"]
    ]
  end
end
