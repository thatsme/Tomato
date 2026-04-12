defmodule Tomato.Deploy.Config do
  @moduledoc """
  Merges user-supplied overrides with application config and env-var
  defaults, then resolves the SSH authentication method.

  Credential resolution order (first match wins):

    1. Explicit `:identity_file` in opts or app config
    2. `TOMATO_DEPLOY_IDENTITY_FILE` environment variable
    3. Auto-discovered `~/.ssh/id_ed25519`
    4. Auto-discovered `~/.ssh/id_rsa`
    5. Password fallback (logged as a warning by the SSH layer)
  """

  @type auth :: {:identity, Path.t()} | {:password, String.t()}

  @candidate_keys ["id_ed25519", "id_rsa"]

  @doc """
  Merge overrides with app config + env defaults and resolve the auth method.
  """
  @spec merge(map()) :: map()
  def merge(overrides \\ %{}) do
    app_config = Application.get_env(:tomato, Tomato.Deploy, [])

    base = %{
      host: Keyword.get(app_config, :host, "localhost"),
      port: Keyword.get(app_config, :port, 22),
      user: Keyword.get(app_config, :user, "root"),
      password: Keyword.get(app_config, :password),
      identity_file: Keyword.get(app_config, :identity_file),
      remote_path: "/etc/nixos/configuration.nix",
      timeout: 30_000
    }

    base
    |> Map.merge(Map.new(overrides))
    |> resolve_auth()
  end

  @doc """
  Resolve the authentication tuple for a merged opts map.

  Takes an optional `home` override for testability (defaults to
  `System.user_home/0`). The env-var check is always performed via
  `System.get_env/1`; tests should manipulate that directly.
  """
  @spec resolve_auth(map(), Path.t() | nil) :: map()
  def resolve_auth(opts, home \\ System.user_home()) do
    Map.put(opts, :auth, find_auth(opts, home))
  end

  defp find_auth(opts, home) do
    explicit_identity(opts) ||
      env_identity() ||
      discovered_identity(home) ||
      {:password, Map.get(opts, :password) || "tomato"}
  end

  defp explicit_identity(%{identity_file: path}) when is_binary(path) do
    if File.exists?(path), do: {:identity, path}, else: nil
  end

  defp explicit_identity(_), do: nil

  defp env_identity do
    case System.get_env("TOMATO_DEPLOY_IDENTITY_FILE") do
      nil -> nil
      "" -> nil
      path -> if File.exists?(path), do: {:identity, path}, else: nil
    end
  end

  defp discovered_identity(nil), do: nil

  defp discovered_identity(home) do
    Enum.find_value(@candidate_keys, fn name ->
      path = Path.join([home, ".ssh", name])
      if File.exists?(path), do: {:identity, path}, else: nil
    end)
  end
end
