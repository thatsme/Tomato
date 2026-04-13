defmodule Tomato.NixValidatorTest do
  use ExUnit.Case, async: true

  alias Tomato.NixValidator

  describe "available?/0" do
    test "returns a boolean" do
      assert is_boolean(NixValidator.available?())
    end
  end

  describe "validate_fragment/1" do
    @describetag :nix_cli

    test "valid fragment returns :ok" do
      fragment = """
      services.openssh.enable = true;
      networking.hostName = "test";
      """

      assert :ok = NixValidator.validate_fragment(fragment)
    end

    test "empty fragment returns :ok" do
      assert :ok = NixValidator.validate_fragment("")
    end

    test "syntactically invalid fragment returns error" do
      fragment = "services.openssh.enable = ;"

      assert {:error, reason} = NixValidator.validate_fragment(fragment)
      assert is_binary(reason)
      assert reason != ""
    end

    test "error does not leak the temp file path" do
      fragment = "bad = ;"

      assert {:error, reason} = NixValidator.validate_fragment(fragment)
      refute reason =~ System.tmp_dir!()
    end

    test "temp file is cleaned up after success" do
      before = count_tomato_tmp_files()
      assert :ok = NixValidator.validate_fragment("x = 1;")
      assert count_tomato_tmp_files() == before
    end

    test "temp file is cleaned up after error" do
      before = count_tomato_tmp_files()
      assert {:error, _} = NixValidator.validate_fragment("bad = ;")
      assert count_tomato_tmp_files() == before
    end
  end

  defp count_tomato_tmp_files do
    System.tmp_dir!()
    |> File.ls!()
    |> Enum.count(&String.starts_with?(&1, "tomato_nix_"))
  end
end
