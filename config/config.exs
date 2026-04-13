# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :tomato,
  generators: [timestamp_type: :utc_datetime]

# Local Nix syntax validation (parse-only) for generated leaf fragments.
# Set enabled: false to skip even when nix-instantiate is on PATH.
config :tomato, :nix_validation, enabled: true

# NixOS deploy target — override in config/deploy.secret.exs or env vars
# See README.md for setup instructions.
#
# Auth: set TOMATO_DEPLOY_IDENTITY_FILE to use SSH key auth (recommended).
# TOMATO_DEPLOY_PASSWORD is the legacy lab-only fallback.
config :tomato, Tomato.Deploy,
  host: System.get_env("TOMATO_DEPLOY_HOST", "localhost"),
  port: String.to_integer(System.get_env("TOMATO_DEPLOY_PORT", "22")),
  user: System.get_env("TOMATO_DEPLOY_USER", "root"),
  password: System.get_env("TOMATO_DEPLOY_PASSWORD"),
  identity_file: System.get_env("TOMATO_DEPLOY_IDENTITY_FILE")

# Configure the endpoint
config :tomato, TomatoWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: TomatoWeb.ErrorHTML, json: TomatoWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Tomato.PubSub,
  live_view: [signing_salt: "6Z3JZQSd"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  tomato: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  tomato: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

# Optional local deploy credentials (gitignored)
if File.exists?(Path.expand("deploy.secret.exs", __DIR__)) do
  import_config "deploy.secret.exs"
end
