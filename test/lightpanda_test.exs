defmodule LightpandaTest do
  use ExUnit.Case

  test "target returns a valid platform string" do
    target = Lightpanda.target()
    assert target in ["aarch64-macos", "x86_64-macos", "aarch64-linux", "x86_64-linux"]
  end

  test "release returns the baked-in upstream tag" do
    assert Lightpanda.release() =~ ~r/^\d+\.\d+\.\d+$/
  end

  test "release matches the package version" do
    # The package version tracks the upstream binary version it
    # installs; a bump to one without the other is a mistake.
    assert Lightpanda.release() ==
             Mix.Project.config()[:version] |> Version.parse!() |> to_string()
  end

  test "bin_path returns a path containing the target" do
    path = Lightpanda.bin_path()
    assert String.contains?(path, "lightpanda-")
    assert String.contains?(path, Lightpanda.target())
  end

  describe "bin_path/0 with overrides" do
    setup do
      original_path = Application.get_env(:lightpanda, :path)
      original_install_dir = Application.get_env(:lightpanda, :install_dir)
      original_env = System.get_env("LIGHTPANDA_INSTALL_DIR")

      on_exit(fn ->
        restore(:path, original_path)
        restore(:install_dir, original_install_dir)

        case original_env do
          nil -> System.delete_env("LIGHTPANDA_INSTALL_DIR")
          val -> System.put_env("LIGHTPANDA_INSTALL_DIR", val)
        end
      end)

      :ok
    end

    test "default falls back to _build dir with per-target filename" do
      Application.delete_env(:lightpanda, :path)
      Application.delete_env(:lightpanda, :install_dir)
      System.delete_env("LIGHTPANDA_INSTALL_DIR")

      path = Lightpanda.bin_path()
      assert Path.basename(path) == "lightpanda-#{Lightpanda.target()}"
      assert String.contains?(path, "_build")
    end

    test ":install_dir resolves a relative dir against File.cwd!" do
      Application.delete_env(:lightpanda, :path)
      Application.put_env(:lightpanda, :install_dir, ".browsers")
      System.delete_env("LIGHTPANDA_INSTALL_DIR")

      expected = Path.join([File.cwd!(), ".browsers", "lightpanda-#{Lightpanda.target()}"])
      assert Lightpanda.bin_path() == expected
    end

    test ":install_dir accepts an absolute dir" do
      Application.delete_env(:lightpanda, :path)
      Application.put_env(:lightpanda, :install_dir, "/opt/lp")
      System.delete_env("LIGHTPANDA_INSTALL_DIR")

      assert Lightpanda.bin_path() ==
               "/opt/lp/lightpanda-#{Lightpanda.target()}"
    end

    test "LIGHTPANDA_INSTALL_DIR env var works when config key is unset" do
      Application.delete_env(:lightpanda, :path)
      Application.delete_env(:lightpanda, :install_dir)
      System.put_env("LIGHTPANDA_INSTALL_DIR", "/var/lp")

      assert Lightpanda.bin_path() ==
               "/var/lp/lightpanda-#{Lightpanda.target()}"
    end

    test ":install_dir config key takes precedence over env var" do
      Application.delete_env(:lightpanda, :path)
      Application.put_env(:lightpanda, :install_dir, "/from/config")
      System.put_env("LIGHTPANDA_INSTALL_DIR", "/from/env")

      assert Lightpanda.bin_path() ==
               "/from/config/lightpanda-#{Lightpanda.target()}"
    end

    test ":path overrides :install_dir and supplies the full filename" do
      Application.put_env(:lightpanda, :path, "/custom/lightpanda-bin")
      Application.put_env(:lightpanda, :install_dir, "/ignored")
      System.put_env("LIGHTPANDA_INSTALL_DIR", "/also-ignored")

      assert Lightpanda.bin_path() == "/custom/lightpanda-bin"
    end

    defp restore(key, nil), do: Application.delete_env(:lightpanda, key)
    defp restore(key, val), do: Application.put_env(:lightpanda, key, val)
  end

  test "config_for! raises on unknown profile" do
    assert_raise ArgumentError, ~r/unknown lightpanda profile/, fn ->
      Lightpanda.config_for!(:nonexistent)
    end
  end
end
