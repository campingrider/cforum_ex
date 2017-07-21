defmodule Cforum.Mixfile do
  use Mix.Project

  def project do
    [app: :cforum,
     version: "0.0.1",
     elixir: "~> 1.2",
     elixirc_paths: elixirc_paths(Mix.env),
     compilers: [:phoenix, :gettext] ++ Mix.compilers,
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     test_coverage: [tool: Coverex.Task, ignore_modules: ignored_modules()],
     aliases: aliases(),
     deps: deps()]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    apps = [:phoenix, :phoenix_pubsub, :phoenix_html, :cowboy, :logger, :gettext,
            :phoenix_ecto, :postgrex, :timex, :guardian, :number, :bamboo, :bamboo_smtp,
            :arc_ecto]

    apps = if Mix.env == :test, do: apps ++ [:faker], else: apps

    [mod: {Cforum, []},
     applications: apps]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_),     do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [{:phoenix, "~> 1.3.0-rc", override: true},
     {:phoenix_pubsub, "~> 1.0"},
     {:phoenix_ecto, "~> 3.2"},
     {:postgrex, ">= 0.0.0"},
     {:phoenix_html, "~> 2.6"},
     {:phoenix_live_reload, "~> 1.0", only: :dev},
     {:gettext, "~> 0.11"},
     {:cowboy, "~> 1.0"},
     {:comeonin, "~> 3.0"},
     {:guardian, "~> 0.14"},
     {:number, "~> 0.5.1"},
     {:bamboo, "~> 0.8"},
     {:bamboo_smtp, "~> 1.3.0"},
     {:timex, "~> 3.0"},
     {:timex_ecto, "~> 3.0"},
     {:arc_ecto, "~> 0.7"},
     {:arc, "~> 0.7"},

     {:ex_guard, "~> 1.2", only: :dev},
     {:coverex, "~> 1.4.10", only: :test},
     {:ex_machina, "~> 2.0", only: :test},
     {:faker, "~> 0.8", only: :test}]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to create, migrate and run the seeds file at once:
  #
  #     $ mix ecto.setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    ["ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
     "ecto.reset": ["ecto.drop", "ecto.setup"],
     "test": ["ecto.create --quiet", "ecto.migrate", "test"]]
  end

  defp ignored_modules do
    [Elixir.Phoenix.Param.Cforum.Accounts.Badge, Elixir.Phoenix.Param.Cforum.Accounts.BadgeUser,
     Elixir.Phoenix.Param.Cforum.Accounts.Notification, Elixir.Phoenix.Param.Cforum.Accounts.PrivMessage,
     Elixir.Phoenix.Param.Cforum.Accounts.Score, Elixir.Phoenix.Param.Cforum.Accounts.Setting,
     Elixir.Phoenix.Param.Cforum.Accounts.User, Elixir.Phoenix.Param.Cforum.Forums.CloseVote,
     Elixir.Phoenix.Param.Cforum.Forums.CloseVoteVoter, Elixir.Phoenix.Param.Cforum.Forums.Forum,
     Elixir.Phoenix.Param.Cforum.Forums.InterestingMessage, Elixir.Phoenix.Param.Cforum.Forums.Message,
     Elixir.Phoenix.Param.Cforum.Forums.MessageTag, Elixir.Phoenix.Param.Cforum.Forums.ReadMessage,
     Elixir.Phoenix.Param.Cforum.Forums.Subscription, Elixir.Phoenix.Param.Cforum.Forums.Tag,
     Elixir.Phoenix.Param.Cforum.Forums.Thread, Elixir.Phoenix.Param.Cforum.Forums.Vote]
  end
end
