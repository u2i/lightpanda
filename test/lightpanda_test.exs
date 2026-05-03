defmodule LightpandaTest do
  use ExUnit.Case

  test "target returns a valid platform string" do
    target = Lightpanda.target()
    assert target in ["aarch64-macos", "x86_64-macos", "aarch64-linux", "x86_64-linux"]
  end

  test "configured_version returns default when not configured" do
    assert Lightpanda.configured_version() == Lightpanda.latest_version()
  end

  test "bin_path returns a path containing the target" do
    path = Lightpanda.bin_path()
    assert String.contains?(path, "lightpanda-")
    assert String.contains?(path, Lightpanda.target())
  end

  test "config_for! raises on unknown profile" do
    assert_raise ArgumentError, ~r/unknown lightpanda profile/, fn ->
      Lightpanda.config_for!(:nonexistent)
    end
  end

  @tag :install
  test "bin_version returns version after install" do
    assert Lightpanda.bin_version() == Lightpanda.latest_version()
  end

  test "default_base_url contains $version and $target placeholders" do
    url = Lightpanda.default_base_url()
    assert String.contains?(url, "$version")
    assert String.contains?(url, "$target")
  end
end
