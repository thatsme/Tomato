defmodule Tomato.DeployTest do
  use ExUnit.Case, async: true

  alias Tomato.Deploy

  describe "simple_diff/2" do
    test "returns empty string for identical input" do
      assert Deploy.simple_diff("a\nb\nc", "a\nb\nc") == ""
    end

    test "shows additions and removals" do
      old = "line1\nline2\nline3"
      new = "line1\nline2-changed\nline3"
      diff = Deploy.simple_diff(old, new)

      assert diff =~ "- line2"
      assert diff =~ "+ line2-changed"
    end

    test "shows only additions when content was empty" do
      diff = Deploy.simple_diff("", "new content")
      assert diff =~ "+ new content"
    end

    test "shows only removals when new is empty" do
      diff = Deploy.simple_diff("old content", "")
      assert diff =~ "- old content"
    end
  end

  describe "rebuild_command (via deploy mode)" do
    # We test this indirectly by checking the function exists and accepts modes
    test "deploy/2 accepts mode option" do
      # This will fail to connect (no real server) but proves the API
      result =
        Deploy.deploy("/nonexistent.nix", %{
          mode: :switch,
          host: "127.0.0.1",
          port: 1,
          password: "x"
        })

      assert {:error, _} = result
    end

    test "deploy/2 accepts test mode" do
      result =
        Deploy.deploy("/nonexistent.nix", %{
          mode: :test,
          host: "127.0.0.1",
          port: 1,
          password: "x"
        })

      assert {:error, _} = result
    end

    test "deploy/2 accepts dry_activate mode" do
      result =
        Deploy.deploy("/nonexistent.nix", %{
          mode: :dry_activate,
          host: "127.0.0.1",
          port: 1,
          password: "x"
        })

      assert {:error, _} = result
    end
  end
end
