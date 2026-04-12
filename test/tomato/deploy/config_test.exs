defmodule Tomato.Deploy.ConfigTest do
  # Not async: the tests manipulate the TOMATO_DEPLOY_IDENTITY_FILE env var.
  use ExUnit.Case, async: false

  alias Tomato.Deploy.Config

  @env_var "TOMATO_DEPLOY_IDENTITY_FILE"

  setup do
    prev_env = System.get_env(@env_var)
    System.delete_env(@env_var)

    tmp =
      Path.join(
        System.tmp_dir!(),
        "tomato_config_test_#{System.unique_integer([:positive])}"
      )

    ssh_dir = Path.join(tmp, ".ssh")
    File.mkdir_p!(ssh_dir)

    on_exit(fn ->
      File.rm_rf!(tmp)
      if prev_env, do: System.put_env(@env_var, prev_env), else: System.delete_env(@env_var)
    end)

    {:ok, home: tmp, ssh_dir: ssh_dir}
  end

  describe "resolve_auth/2 — credential resolution order" do
    test "explicit identity_file wins when file exists", %{home: home, ssh_dir: ssh_dir} do
      key = Path.join(ssh_dir, "custom_key")
      File.write!(key, "fake key material")

      result = Config.resolve_auth(%{identity_file: key, password: "p"}, home)

      assert result.auth == {:identity, key}
    end

    test "non-existent identity_file is ignored, falls through", %{home: home} do
      result =
        Config.resolve_auth(%{identity_file: "/nonexistent/key", password: "p"}, home)

      assert result.auth == {:password, "p"}
    end

    test "env var identity_file is used when file exists", %{home: home, ssh_dir: ssh_dir} do
      key = Path.join(ssh_dir, "env_key")
      File.write!(key, "fake key")
      System.put_env(@env_var, key)

      result = Config.resolve_auth(%{password: "p"}, home)

      assert result.auth == {:identity, key}
    end

    test "env var identity_file pointing at nothing falls through", %{home: home} do
      System.put_env(@env_var, "/nonexistent/env/key")

      result = Config.resolve_auth(%{password: "p"}, home)

      assert result.auth == {:password, "p"}
    end

    test "auto-discovers ~/.ssh/id_ed25519", %{home: home, ssh_dir: ssh_dir} do
      key = Path.join(ssh_dir, "id_ed25519")
      File.write!(key, "fake ed25519")

      result = Config.resolve_auth(%{password: "p"}, home)

      assert result.auth == {:identity, key}
    end

    test "falls back to ~/.ssh/id_rsa when id_ed25519 missing", %{home: home, ssh_dir: ssh_dir} do
      key = Path.join(ssh_dir, "id_rsa")
      File.write!(key, "fake rsa")

      result = Config.resolve_auth(%{password: "p"}, home)

      assert result.auth == {:identity, key}
    end

    test "prefers id_ed25519 over id_rsa when both exist", %{home: home, ssh_dir: ssh_dir} do
      ed = Path.join(ssh_dir, "id_ed25519")
      rsa = Path.join(ssh_dir, "id_rsa")
      File.write!(ed, "fake ed25519")
      File.write!(rsa, "fake rsa")

      result = Config.resolve_auth(%{password: "p"}, home)

      assert result.auth == {:identity, ed}
    end

    test "falls back to password when no key is found", %{home: home} do
      result = Config.resolve_auth(%{password: "secret"}, home)

      assert result.auth == {:password, "secret"}
    end

    test "uses default password when none provided", %{home: home} do
      result = Config.resolve_auth(%{}, home)

      assert result.auth == {:password, "tomato"}
    end

    test "handles nil home dir gracefully" do
      result = Config.resolve_auth(%{password: "p"}, nil)

      assert result.auth == {:password, "p"}
    end
  end

  describe "merge/1" do
    test "adds :auth to the merged map" do
      merged = Config.merge(%{host: "example.com"})

      assert merged.host == "example.com"
      assert Map.has_key?(merged, :auth)
    end

    test "preserves :mode and other passthrough keys" do
      merged = Config.merge(%{mode: :test, host: "example.com"})

      assert merged.mode == :test
    end
  end
end
