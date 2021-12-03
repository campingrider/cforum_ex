import Config

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with brunch.io to recompile .js and .css sources.
config :cforum, CforumWeb.Endpoint,
  http: [port: 4000],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [
    yarn: ["run", "dev", cd: Path.expand("../assets", __DIR__)]
  ]

# Watch static and templates for browser reloading.
config :cforum, CforumWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r{priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$},
      ~r{priv/gettext/.*(po)$},
      ~r{lib/cforum_web/views/.*(ex)$},
      ~r{lib/cforum_web/templates/.*(eex)$}
    ]
  ]

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :cforum, Oban, crontab: false

# Configure your database
config :cforum, Cforum.Repo,
  database: "cforum_development",
  hostname: "localhost",
  pool_size: 10

config :cforum, Cforum.Mailer, adapter: Swoosh.Adapters.Local
config :swoosh, serve_mailbox: true, preview_port: 4001

config :cforum,
  mail_sender: "cforum@wwwtech.de",
  paginator: [
    per_page: 50,
    distance: 3
  ],
  base_url: "http://localhost:4000/",
  blog_base_url: "http://blog.localhost:4000/",
  environment: Mix.env(),
  search_dict: "german",
  uploads_dir: Path.expand("../priv/uploads", __DIR__),
  media_dir: Path.expand("../priv/uploads/pictures", __DIR__),
  avatar_dir: Path.expand("../priv/", __DIR__),
  avatar_url: "/uploads/users/avatars",
  thumbnail_dir: Path.expand("../priv/", __DIR__),
  thumbnail_url: "/uploads/thumbnails",
  convert: "/usr/bin/convert",
  cfmarkdown: [
    cli: "./node_modules/.bin/babel-node ./bin/cfmarkdown2html.js",
    pwd: Path.expand("../cfmarkdown"),
    pool_size: 5
  ]

config :appsignal, :config,
  otp_app: :cforum,
  active: false
