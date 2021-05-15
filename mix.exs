defmodule Events.MixProject do
  use Mix.Project

  @name "events"
  @version "0.1.0"

  def project do
    [
      app: :events,
      version: @version,
      elixir: "~> 1.11",
      name: @name,
      start_permanent: Mix.env() == :prod,
      docs: docs(),
      deps: deps(),
      aliases: aliases(),

      # testing
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.github": :test
      ],

      # type checking
      dialyzer: [plt_add_deps: :transitive]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:erlang_psq, "~> 1.0"},

      # dev/test dependencies
      {:credo, "~> 0.8.8", only: [:dev], runtime: false},
      {:dialyxir, "~> 0.5", only: [:dev], runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      {:ex_doc, "~> 0.20", only: :dev, runtime: false}
    ]
  end

  defp docs(),
    do: [
      source_ref: "v#{@version}",
      main: "readme",
      extras: ["README.md"]
    ]

  defp aliases do
    [
      check: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        # "coveralls ",
        "dialyzer"
      ]
    ]
  end
end
