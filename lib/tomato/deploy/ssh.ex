defmodule Tomato.Deploy.SSH do
  @moduledoc """
  Thin wrapper over Erlang `:ssh` and `:ssh_connection` for the deploy path.

  Supports both public-key auth (via `user_dir` pointing at a directory
  containing a standard-named key like `id_ed25519`) and legacy password
  auth. See `Tomato.Deploy.Config` for the credential resolution order.
  """

  require Logger

  @type conn :: :ssh.connection_ref()

  @doc """
  Open an SSH connection using the resolved auth tuple in `opts.auth`.
  """
  @spec connect(map()) :: {:ok, conn()} | {:error, String.t()}
  def connect(opts) do
    ssh_opts = build_ssh_opts(opts)

    case :ssh.connect(to_charlist(opts.host), opts.port, ssh_opts) do
      {:ok, conn} -> {:ok, conn}
      {:error, reason} -> {:error, "SSH connection failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Close an SSH connection.
  """
  @spec disconnect(conn()) :: :ok
  def disconnect(conn) do
    :ssh.close(conn)
    :ok
  end

  @doc """
  Execute a remote command and collect stdout/stderr until EOF or exit.
  """
  @spec exec(conn(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def exec(conn, command) do
    case :ssh_connection.session_channel(conn, :infinity) do
      {:ok, channel} ->
        :ssh_connection.exec(conn, channel, to_charlist(command), :infinity)
        collect_output(conn, channel, "")

      {:error, reason} ->
        {:error, "SSH exec failed: #{inspect(reason)}"}
    end
  end

  defp build_ssh_opts(opts) do
    base = [
      user: to_charlist(opts.user),
      silently_accept_hosts: true,
      user_interaction: false,
      connect_timeout: opts.timeout
    ]

    case Map.get(opts, :auth) do
      {:identity, key_path} ->
        user_dir = key_path |> Path.dirname() |> to_charlist()
        [user_dir: user_dir] ++ base

      {:password, password} ->
        Logger.warning(
          "Tomato.Deploy: using SSH password authentication. " <>
            "Set :identity_file or TOMATO_DEPLOY_IDENTITY_FILE to use key auth."
        )

        [password: to_charlist(password)] ++ base
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
end
