defmodule Jido.MixProject do
  use Mix.Project

  @version "1.0.0"

  def vsn do
    @version
  end

  def project do
    [
      app: :jido,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      consolidate_protocols: Mix.env() != :test,

      # Docs
      name: "Jido",
      description:
        "A foundational framework for building autonomous, distributed agent systems in Elixir",
      source_url: "https://github.com/agentjido/jido",
      homepage_url: "https://github.com/agentjido/jido",
      package: package(),
      docs: docs(),

      # Coverage
      test_coverage: [
        tool: ExCoveralls,
        summary: [threshold: 80],
        export: "cov",
        ignore_modules: [~r/^JidoTest\./]
      ],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.github": :test,
        "coveralls.lcov": :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.cobertura": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Jido.Application, []}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support", "test/jido/bus/support"]
  defp elixirc_paths(:dev), do: ["lib", "bench"]
  defp elixirc_paths(_), do: ["lib"]

  defp docs do
    [
      main: "readme",
      api_reference: false,
      source_ref: "v#{@version}",
      source_url: "https://github.com/agentjido/jido",
      authors: ["Mike Hostetler <mike.hostetler@gmail.com>"],
      groups_for_extras: [
        Introduction: ["guides/getting-started.md"],
        Actions: ~r/guides\/actions\/.*\.md$/,
        Signals: ~r/guides\/signals\/.*\.md$/,
        Agents: ~r/guides\/agents\/.*\.md$/,
        Skills: ~r/guides\/skills\/.*\.md$/,
        Examples: ~r/guides\/examples\/.*\.md$/,
        Livebooks: ~r/guides\/livebook\/.*\.livemd$/,
        Tutorials: ~r/guides\/tutorials\/.*\.md$/,
        Project: ["CONTRIBUTING.md", "CHANGELOG.md", "LICENSE.md"]
      ],
      extras: [
        {"README.md", title: "Home"},
        {"CONTRIBUTING.md", title: "Contributing"},
        {"CHANGELOG.md", title: "Changelog"},
        {"LICENSE.md", title: "Apache 2.0 License"},
        {"guides/getting-started.md", title: "Getting Started"},

        # Actions
        {"guides/actions/actions.md", title: "Actions & Workflows"},
        {"guides/actions/instructions.md", title: "Action Instructions"},

        # Signals
        {"guides/signals/bus.md", title: "Signal Bus"},

        # Agents
        {"guides/agents/agents.md", title: "Agents"},
        {"guides/agents/directives.md", title: "Agent Directives"},
        {"guides/agents/sensors.md", title: "Agent Sensors"},

        # Tutorials
        # {"guides/tutorials/tutorial-1.md", title: "Tutorial 1"},

        # Livebooks
        # {"guides/livebook/getting-started-actions.livemd", title: "Getting Started with Actions"},

        # Skills
        {"guides/skills/skills.md", title: "Skills"},
        {"guides/skills/signal-router.md", title: "Signal Router"}
      ],
      extra_section: "Guides",
      formatters: ["html"],
      skip_undefined_reference_warnings_on: [
        "CHANGELOG.md",
        "LICENSE.md"
      ],
      groups_for_modules: [
        Core: [
          Jido,
          Jido.Action,
          Jido.Agent,
          Jido.Agent.Server,
          Jido.Instruction,
          Jido.Sensor,
          Jido.Workflow
        ],
        "Actions: Execution": [
          Jido.Runner,
          Jido.Runner.Chain,
          Jido.Runner.Simple,
          Jido.Workflow,
          Jido.Workflow.Chain,
          Jido.Workflow.Closure
        ],
        "Actions: Directives": [
          Jido.Agent.Directive,
          Jido.Agent.Directive.Enqueue,
          Jido.Agent.Directive.RegisterAction,
          Jido.Agent.Directive.DeregisterAction,
          Jido.Agent.Directive.Kill,
          Jido.Agent.Directive.Spawn,
          Jido.Actions.Directives
        ],
        "Actions: Extra": [
          Jido.Action.Tool
        ],
        "Signals: Core": [
          Jido.Signal,
          Jido.Signal.Router
        ],
        "Signals: Bus": [
          Jido.Bus,
          Jido.Bus.Adapter,
          Jido.Bus.Adapters.InMemory,
          Jido.Bus.Adapters.PubSub
        ],
        "Signals: Dispatch": [
          Jido.Signal.Dispatch,
          Jido.Signal.Dispatch.Adapter,
          Jido.Signal.Dispatch.Bus,
          Jido.Signal.Dispatch.ConsoleAdapter,
          Jido.Signal.Dispatch.LoggerAdapter,
          Jido.Signal.Dispatch.Named,
          Jido.Signal.Dispatch.NoopAdapter,
          Jido.Signal.Dispatch.PidAdapter,
          Jido.Signal.Dispatch.PubSub
        ],
        Skills: [
          Jido.Skill,
          Jido.Skills.Arithmetic
        ],
        Examples: [
          Jido.Actions.Arithmetic,
          Jido.Actions.Basic,
          Jido.Actions.Files,
          Jido.Actions.Simplebot,
          Jido.Sensors.Cron,
          Jido.Sensors.Heartbeat
        ],
        Utilities: [
          Jido.Discovery,
          Jido.Error,
          Jido.Scheduler,
          Jido.Serialization.JsonDecoder,
          Jido.Serialization.JsonSerializer,
          Jido.Serialization.ModuleNameTypeProvider,
          Jido.Serialization.TypeProvider,
          Jido.Supervisor,
          Jido.Util
        ]
      ]
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE.md"],
      maintainers: ["Mike Hostetler"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/agentjido/jido"
      }
    ]
  end

  defp deps do
    [
      # Jido Deps
      {:backoff, "~> 1.1"},
      {:deep_merge, "~> 1.0"},
      {:elixir_uuid, "~> 1.2"},
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.1"},
      {:nimble_parsec, "~> 1.4"},
      {:ok, "~> 2.3"},
      {:phoenix_pubsub, "~> 2.1"},
      {:private, "~> 0.1.2"},
      {:proper_case, "~> 1.3"},
      {:telemetry, "~> 1.3"},
      {:typed_struct, "~> 0.3.0"},
      {:typed_struct_nimble_options, "~> 0.1.1"},
      {:quantum, "~> 3.5"},
      {:ex_dbug, "~> 1.2"},

      # Skill & Action Dependencies for examples
      {:abacus, "~> 2.1"},

      # Development & Test Dependencies
      {:credo, "~> 1.7"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18.3", only: [:dev, :test]},
      {:expublish, "~> 2.7", only: [:dev], runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:mock, "~> 0.3.0", only: :test},
      {:mimic, "~> 1.11", only: :test},
      {:stream_data, "~> 1.0", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      # Helper to run tests with trace when needed
      # test: "test --trace",
      docs: "docs -f html --open",

      # Run to check the quality of your code
      q: ["quality"],
      quality: [
        "format",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "dialyzer --format dialyxir",
        "credo --all"
      ]
    ]
  end
end
