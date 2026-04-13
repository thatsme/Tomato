defmodule Tomato.NixValidator do
  @moduledoc """
  Validates Nix configuration fragments using the local `nix-instantiate`
  CLI (parse-only — no evaluation, no sandbox, no network).

  Leaf fragments in Tomato are attribute-set bodies like
  `services.openssh.enable = true;` — they only parse inside a NixOS
  module harness `{ config, pkgs, lib, ... }: { ... }`. This module
  wraps each fragment in that harness before invoking the parser, so
  per-leaf validation reports accurate errors.

  The `nix-instantiate` binary is optional. Call `available?/0` before
  any batch of validations and fall back gracefully when it returns
  `false`.
  """

  @harness_header "{ config, pkgs, lib, ... }: {\n"
  @harness_footer "\n}\n"

  @doc """
  Check whether `nix-instantiate` is on PATH. Not cached — cheap enough
  to call once per validation batch.
  """
  @spec available?() :: boolean()
  def available? do
    System.find_executable("nix-instantiate") != nil
  end

  @doc """
  Validate a single Nix fragment. The fragment is wrapped in a minimal
  module harness before parsing, so attribute-set bodies validate
  correctly.

  Returns `:ok` on clean parse, or `{:error, reason}` where `reason`
  is the cleaned stderr output with the scratch file path redacted.
  """
  @spec validate_fragment(String.t()) :: :ok | {:error, String.t()}
  def validate_fragment(fragment) when is_binary(fragment) do
    wrapped = @harness_header <> fragment <> @harness_footer

    tmp_path =
      Path.join(
        System.tmp_dir!(),
        "tomato_nix_#{System.unique_integer([:positive])}.nix"
      )

    try do
      File.write!(tmp_path, wrapped)

      case System.cmd("nix-instantiate", ["--parse", tmp_path], stderr_to_stdout: true) do
        {_output, 0} -> :ok
        {output, _} -> {:error, clean_error(output, tmp_path)}
      end
    after
      File.rm(tmp_path)
    end
  end

  @spec clean_error(String.t(), String.t()) :: String.t()
  defp clean_error(output, tmp_path) do
    output
    |> String.replace(tmp_path, "<fragment>")
    |> String.trim()
  end
end
