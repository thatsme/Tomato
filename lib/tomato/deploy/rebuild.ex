defmodule Tomato.Deploy.Rebuild do
  @moduledoc """
  Builds `nixos-rebuild` shell invocations and runs them on the target.
  """

  require Logger

  alias Tomato.Deploy.SSH

  @type mode :: :switch | :test | :dry_activate | :build

  @doc """
  Run the rebuild script for the given mode, prefixing a small preview of
  the uploaded config file.
  """
  @spec apply_config(SSH.conn(), boolean(), mode()) :: {:ok, String.t()} | {:error, String.t()}
  def apply_config(conn, is_flake, mode) do
    cmd = rebuild_command(is_flake, mode)
    Logger.info("Running #{cmd}...")

    config_path = if is_flake, do: "/etc/nixos/flake.nix", else: "/etc/nixos/configuration.nix"
    label = if is_flake, do: "flake.nix", else: "configuration.nix"

    command = """
    echo "==> Uploaded #{label}"
    head -5 #{config_path}
    echo "..."
    echo ""
    echo "==> Running #{cmd}..."
    #{cmd} 2>&1
    echo ""
    echo "==> Done"
    echo "Host: $(hostname)"
    echo "Date: $(date)"
    """

    SSH.exec(conn, command)
  end

  @doc """
  Return the `nixos-rebuild` command string for the given (flake?, mode) pair.
  """
  @spec rebuild_command(boolean(), mode()) :: String.t()
  def rebuild_command(true, :switch),
    do: "cd /etc/nixos && nixos-rebuild switch --flake .#$(hostname)"

  def rebuild_command(true, :test),
    do: "cd /etc/nixos && nixos-rebuild test --flake .#$(hostname)"

  def rebuild_command(true, :dry_activate),
    do: "cd /etc/nixos && nixos-rebuild dry-activate --flake .#$(hostname)"

  def rebuild_command(true, :build),
    do: "cd /etc/nixos && nixos-rebuild build --flake .#$(hostname)"

  def rebuild_command(false, :switch), do: "nixos-rebuild switch"
  def rebuild_command(false, :test), do: "nixos-rebuild test"
  def rebuild_command(false, :dry_activate), do: "nixos-rebuild dry-activate"
  def rebuild_command(false, :build), do: "nixos-rebuild build"
end
