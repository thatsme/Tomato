defmodule Tomato.Deploy do
  @moduledoc """
  Deploys a generated .nix file to a target machine via SSH.
  Uploads configuration.nix, validates it with nix-instantiate,
  and applies packages via nix-env.
  """

  require Logger

  @doc """
  Deploy a .nix file to the target machine.
  Returns {:ok, output} or {:error, reason}.
  """
  @spec deploy(String.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def deploy(nix_file_path, opts \\ %{}) do
    opts = merge_config(opts)
    is_flake = String.ends_with?(nix_file_path, "flake.nix")
    remote_path = if is_flake, do: "/etc/nixos/flake.nix", else: opts.remote_path

    with {:ok, content} <- File.read(nix_file_path),
         {:ok, conn} <- connect(opts),
         :ok <- upload(conn, content, remote_path),
         {:ok, output} <- apply_config(conn, is_flake),
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
        # Ensure directory exists
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

  defp apply_config(conn, true) do
    Logger.info("Running nixos-rebuild switch --flake...")

    command = """
    echo "==> Uploaded flake.nix"
    head -5 /etc/nixos/flake.nix
    echo "..."
    echo ""
    echo "==> Running nixos-rebuild switch --flake..."
    cd /etc/nixos && nixos-rebuild switch --flake .#$(hostname) 2>&1
    echo ""
    echo "==> Done"
    echo "Host: $(hostname)"
    echo "Date: $(date)"
    """

    exec(conn, command)
  end

  defp apply_config(conn, false) do
    Logger.info("Running nixos-rebuild switch...")

    command = """
    echo "==> Uploaded configuration.nix"
    head -5 /etc/nixos/configuration.nix
    echo "..."
    echo ""
    echo "==> Running nixos-rebuild switch..."
    nixos-rebuild switch 2>&1
    echo ""
    echo "==> Done"
    echo "Host: $(hostname)"
    echo "Date: $(date)"
    """

    exec(conn, command)
  end

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
      60_000 ->
        {:error, "SSH command timed out"}
    end
  end
end
