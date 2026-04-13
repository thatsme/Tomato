defmodule Tomato.Deploy do
  @moduledoc """
  Public deploy API — delegates to focused submodules under `Tomato.Deploy.*`.

  Use `deploy/2` to upload and activate a generated .nix file, `diff/2` to
  compare against the remote config, `rollback/1` to revert to the previous
  NixOS generation, and `test_connection/1` to verify SSH reachability.
  """

  alias Tomato.Deploy.{Config, Diff, Rebuild, SFTP, SSH}

  @type mode :: Rebuild.mode()

  @doc """
  Deploy a .nix file to the target machine.

  Modes:
    - :switch (default) — apply and add to boot menu
    - :test — apply but don't add to boot menu (reverts on reboot)
    - :dry_activate — show what would change without applying
    - :build — build only, don't activate

  Returns {:ok, output} or {:error, reason}.
  """
  @spec deploy(String.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def deploy(nix_file_path, opts \\ %{}) do
    opts = Config.merge(opts)
    mode = Map.get(opts, :mode, :switch)
    is_flake = String.ends_with?(nix_file_path, "flake.nix")
    remote_path = if is_flake, do: "/etc/nixos/flake.nix", else: opts.remote_path

    with {:ok, content} <- File.read(nix_file_path),
         {:ok, conn} <- SSH.connect(opts),
         :ok <- SFTP.upload(conn, content, remote_path),
         {:ok, output} <- Rebuild.apply_config(conn, is_flake, mode),
         :ok <- SSH.disconnect(conn) do
      {:ok, output}
    else
      {:error, reason} -> {:error, to_string(reason)}
    end
  end

  @doc """
  Test SSH connection to the target machine.
  """
  @spec test_connection(map()) :: {:ok, String.t()} | {:error, String.t()}
  def test_connection(opts \\ %{}) do
    opts = Config.merge(opts)

    case SSH.connect(opts) do
      {:ok, conn} ->
        case SSH.exec(
               conn,
               "echo 'Tomato connected' && hostname && nix --version 2>/dev/null || echo 'nix not found'"
             ) do
          {:ok, output} ->
            SSH.disconnect(conn)
            {:ok, String.trim(output)}

          error ->
            SSH.disconnect(conn)
            error
        end

      error ->
        error
    end
  end

  @doc """
  Fetch the current /etc/nixos/configuration.nix (or flake.nix) from the target.
  """
  @spec fetch_current(map()) :: {:ok, String.t()} | {:error, String.t()}
  def fetch_current(opts \\ %{}) do
    opts = Config.merge(opts)
    is_flake = Map.get(opts, :flake, false)
    path = if is_flake, do: "/etc/nixos/flake.nix", else: opts.remote_path

    with {:ok, conn} <- SSH.connect(opts),
         {:ok, content} <- SFTP.read_file(conn, path),
         :ok <- SSH.disconnect(conn) do
      {:ok, content}
    else
      {:error, reason} -> {:error, to_string(reason)}
    end
  end

  @doc """
  Diff a local .nix file against the current remote one.
  Returns {:ok, diff_text} where diff_text is empty if identical.
  """
  @spec diff(String.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def diff(nix_file_path, opts \\ %{}) do
    is_flake = String.ends_with?(nix_file_path, "flake.nix")
    opts = Map.put(Map.new(opts), :flake, is_flake)

    with {:ok, local} <- File.read(nix_file_path),
         {:ok, remote} <- fetch_current(opts) do
      {:ok, Diff.simple_diff(remote, local)}
    end
  end

  @doc """
  List NixOS generations on the target machine.
  """
  @spec list_generations(map()) :: {:ok, String.t()} | {:error, String.t()}
  def list_generations(opts \\ %{}) do
    opts = Config.merge(opts)

    with {:ok, conn} <- SSH.connect(opts),
         {:ok, output} <-
           SSH.exec(
             conn,
             "nixos-rebuild list-generations --json 2>/dev/null || nix-env --list-generations -p /nix/var/nix/profiles/system 2>&1"
           ),
         :ok <- SSH.disconnect(conn) do
      {:ok, output}
    else
      {:error, reason} -> {:error, to_string(reason)}
    end
  end

  @doc """
  Rollback to the previous NixOS generation.
  """
  @spec rollback(map()) :: {:ok, String.t()} | {:error, String.t()}
  def rollback(opts \\ %{}) do
    opts = Config.merge(opts)

    with {:ok, conn} <- SSH.connect(opts),
         {:ok, output} <- SSH.exec(conn, "nixos-rebuild switch --rollback 2>&1"),
         :ok <- SSH.disconnect(conn) do
      {:ok, output}
    else
      {:error, reason} -> {:error, to_string(reason)}
    end
  end

  @doc """
  Simple line-based diff between two strings. Delegates to
  `Tomato.Deploy.Diff.simple_diff/2`.
  """
  @spec simple_diff(String.t(), String.t()) :: String.t()
  defdelegate simple_diff(old, new), to: Diff
end
