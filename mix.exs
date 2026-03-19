defmodule ExCortex.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_cortex,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      elixirc_options: [warnings_as_errors: Mix.env() in [:test, :dev]],
      releases: releases()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {ExCortex.Application, []},
      extra_applications: [:logger, :runtime_tools, :opentelemetry_api, :opentelemetry]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.3"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons", tag: "v2.2.0", sparse: "optimized", app: false, compile: false, depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      # Job processing
      {:oban, "~> 2.18"},
      {:crontab, "~> 1.1"},
      # UI
      {:salad_ui, "~> 1.0.0-beta.3"},
      {:mdex, "~> 0.11"},
      {:opentelemetry_api, "~> 1.4"},
      {:opentelemetry, "~> 1.5"},
      {:opentelemetry_exporter, "~> 1.8"},
      {:opentelemetry_phoenix, "~> 2.0"},
      {:opentelemetry_ecto, "~> 1.2"},
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      # Sources
      {:req, "~> 0.5"},
      {:req_llm, "~> 1.6"},
      {:file_system, "~> 1.0"},
      {:fresh, "~> 0.4"},
      # TUI
      {:owl, "~> 0.13"},
      # Packaging
      {:burrito, "~> 1.5", only: :prod},
      # Accessibility
      {:excessibility, "~> 0.10", only: [:dev, :test]},
      {:ex_compact, "~> 0.1", path: "../ex_compact"}
    ]
  end

  defp releases do
    [
      ex_cortex: [
        steps: if(Mix.env() == :prod, do: [:assemble, &Burrito.wrap/1], else: [:assemble]),
        burrito: [
          targets: [
            linux_x86: [os: :linux, cpu: :x86_64],
            linux_arm: [os: :linux, cpu: :aarch64],
            macos_arm: [os: :darwin, cpu: :aarch64]
          ]
        ]
      ]
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      # First-time setup
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "ecto.fresh": ["ecto.reset", "dev_team.install"],

      # Dev
      seed: ["run priv/repo/seeds.exs"],
      dev: ["phx.server"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      lint: ["compile --warnings-as-errors", "format --check-formatted", "credo"],

      # Assets
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind ex_cortex", "esbuild ex_cortex"],
      "assets.deploy": [
        "tailwind ex_cortex --minify",
        "esbuild ex_cortex --minify",
        "phx.digest"
      ],

      # Release
      "release.build": ["compile", "assets.deploy", "release"],

      # Quality
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"],
      ci: ["compile --warnings-as-errors", "format --check-formatted", "credo --all", "test"]
    ]
  end
end
