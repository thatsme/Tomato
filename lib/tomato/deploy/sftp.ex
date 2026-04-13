defmodule Tomato.Deploy.SFTP do
  @moduledoc """
  SFTP helpers layered on top of an existing SSH connection.
  """

  require Logger

  alias Tomato.Deploy.SSH

  @doc """
  Upload a string payload to a remote path, creating the parent directory
  if necessary.
  """
  @spec upload(SSH.conn(), binary(), String.t()) :: :ok | {:error, String.t()}
  def upload(conn, content, remote_path) do
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

  @doc """
  Read the contents of a remote file over SFTP.
  """
  @spec read_file(SSH.conn(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def read_file(conn, remote_path) do
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
end
