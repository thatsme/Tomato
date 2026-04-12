defmodule Tomato.Deploy do
  @moduledoc """
  Deploys a generated .nix file to a target NixOS machine via SSH.
  Supports switch/test/dry-activate modes, diff against current config,
  and rollback to previous generations.
  """

  require Logger

  @type mode :: :switch | :test | :dry_activate | :build

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
    opts = merge_config(opts)
    mode = Map.get(opts, :mode, :switch)
    is_flake = String.ends_with?(nix_file_path, "flake.nix")
    remote_path = if is_flake, do: "/etc/nixos/flake.nix", else: opts.remote_path

    with {:ok, content} <- File.read(nix_file_path),
         {:ok, conn} <- connect(opts),
         :ok <- upload(conn, content, remote_path),
         {:ok, output} <- apply_config(conn, is_flake, mode),
         :ok <- disconnect(conn) do
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
    opts = merge_config(opts)

    case connect(opts) do
      {:ok, conn} ->
        case exec(
               conn,
               "echo 'Tomato connected' && hostname && nix --version 2>/dev/null || echo 'nix not found'"
             ) do
          {:ok, output} ->
            disconnect(conn)
            {:ok, String.trim(output)}

          error ->
            disconnect(conn)
            error
        end

      error ->
        error
    end
  end

  @doc """
  Fetch the current /etc/nixos/configuration.nix from the target.
  """
  @spec fetch_current(map()) :: {:ok, String.t()} | {:error, String.t()}
  def fetch_current(opts \\ %{}) do
    opts = merge_config(opts)
    is_flake = Map.get(opts, :flake, false)
    path = if is_flake, do: "/etc/nixos/flake.nix", else: opts.remote_path

    with {:ok, conn} <- connect(opts),
         {:ok, content} <- read_file(conn, path),
         :ok <- disconnect(conn) do
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
      {:ok, simple_diff(remote, local)}
    end
  end

  @doc """
  List NixOS generations on the target machine.
  """
  @spec list_generations(map()) :: {:ok, String.t()} | {:error, String.t()}
  def list_generations(opts \\ %{}) do
    opts = merge_config(opts)

    with {:ok, conn} <- connect(opts),
         {:ok, output} <-
           exec(
             conn,
             "nixos-rebuild list-generations --json 2>/dev/null || nix-env --list-generations -p /nix/var/nix/profiles/system 2>&1"
           ),
         :ok <- disconnect(conn) do
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
    opts = merge_config(opts)

    with {:ok, conn} <- connect(opts),
         {:ok, output} <- exec(conn, "nixos-rebuild switch --rollback 2>&1"),
         :ok <- disconnect(conn) do
      {:ok, output}
    else
      {:error, reason} -> {:error, to_string(reason)}
    end
  end

  # --- Config ---

  defp merge_config(overrides) do
    app_config = Application.get_env(:tomato, __MODULE__, [])

    defaults = %{
      host: Keyword.get(app_config, :host, "localhost"),
      port: Keyword.get(app_config, :port, 22),
      user: Keyword.get(app_config, :user, "root"),
      password: Keyword.get(app_config, :password, "tomato"),
      remote_path: "/etc/nixos/configuration.nix",
      timeout: 30_000
    }

    Map.merge(defaults, Map.new(overrides))
  end

  # --- SSH operations ---

  defp connect(opts) do
    ssh_opts = [
      user: to_charlist(opts.user),
      password: to_charlist(opts.password),
      silently_accept_hosts: true,
      user_interaction: false,
      connect_timeout: opts.timeout
    ]

    case :ssh.connect(to_charlist(opts.host), opts.port, ssh_opts) do
      {:ok, conn} -> {:ok, conn}
      {:error, reason} -> {:error, "SSH connection failed: #{inspect(reason)}"}
    end
  end

  defp disconnect(conn) do
    :ssh.close(conn)
    :ok
  end

  defp upload(conn, content, remote_path) do
    case :ssh_sftp.start_channel(conn) do
      {:ok, sftp} ->
        dir = to_charlist(Path.dirname(remote_path))
        :ssh_sftp.make_dir(sftp, dir)

        result = :ssh_sftp.write_file(sftp, to_charlist(remote_path), content)
        :ssh_sftp.stop_channel(sftp)

        case result do
          :ok ->
            Logger.info("Uploaded config to #{remote_path}")
            :ok

          {:error, reason} ->
            {:error, "SFTP upload failed: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "SFTP channel failed: #{inspect(reason)}"}
    end
  end

  defp read_file(conn, remote_path) do
    case :ssh_sftp.start_channel(conn) do
      {:ok, sftp} ->
        result = :ssh_sftp.read_file(sftp, to_charlist(remote_path))
        :ssh_sftp.stop_channel(sftp)

        case result do
          {:ok, content} -> {:ok, to_string(content)}
          {:error, reason} -> {:error, "SFTP read failed: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "SFTP channel failed: #{inspect(reason)}"}
    end
  end

  defp apply_config(conn, is_flake, mode) do
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

    exec(conn, command)
  end

  defp rebuild_command(true, :switch),
    do: "cd /etc/nixos && nixos-rebuild switch --flake .#$(hostname)"

  defp rebuild_command(true, :test),
    do: "cd /etc/nixos && nixos-rebuild test --flake .#$(hostname)"

  defp rebuild_command(true, :dry_activate),
    do: "cd /etc/nixos && nixos-rebuild dry-activate --flake .#$(hostname)"

  defp rebuild_command(true, :build),
    do: "cd /etc/nixos && nixos-rebuild build --flake .#$(hostname)"

  defp rebuild_command(false, :switch), do: "nixos-rebuild switch"
  defp rebuild_command(false, :test), do: "nixos-rebuild test"
  defp rebuild_command(false, :dry_activate), do: "nixos-rebuild dry-activate"
  defp rebuild_command(false, :build), do: "nixos-rebuild build"

  defp exec(conn, command) do
    case :ssh_connection.session_channel(conn, :infinity) do
      {:ok, channel} ->
        :ssh_connection.exec(conn, channel, to_charlist(command), :infinity)
        collect_output(conn, channel, "")

      {:error, reason} ->
        {:error, "SSH exec failed: #{inspect(reason)}"}
    end
  end

  defp collect_output(conn, channel, acc) do
    receive do
      {:ssh_cm, ^conn, {:data, ^channel, _type, data}} ->
        collect_output(conn, channel, acc <> data)

      {:ssh_cm, ^conn, {:eof, ^channel}} ->
        collect_output(conn, channel, acc)

      {:ssh_cm, ^conn, {:exit_status, ^channel, 0}} ->
        collect_output(conn, channel, acc)

      {:ssh_cm, ^conn, {:exit_status, ^channel, status}} ->
        collect_output(conn, channel, acc <> "\n[exit code: #{status}]")

      {:ssh_cm, ^conn, {:closed, ^channel}} ->
        if String.contains?(acc, "[exit code:") do
          {:error, acc}
        else
          {:ok, acc}
        end
    after
      120_000 ->
        {:error, "SSH command timed out"}
    end
  end

  # --- Diff ---

  @doc """
  Simple line-based diff between two strings.
  Returns a unified-diff-like string.
  """
  @spec simple_diff(String.t(), String.t()) :: String.t()
  def simple_diff(old, new) do
    old_lines = String.split(old, "\n")
    new_lines = String.split(new, "\n")

    if old_lines == new_lines do
      ""
    else
      old_set = MapSet.new(old_lines)
      new_set = MapSet.new(new_lines)

      removed = Enum.reject(old_lines, &MapSet.member?(new_set, &1))
      added = Enum.reject(new_lines, &MapSet.member?(old_set, &1))

      removed_str = Enum.map_join(removed, "\n", &("- " <> &1))
      added_str = Enum.map_join(added, "\n", &("+ " <> &1))

      [removed_str, added_str]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")
    end
  end
end
