defmodule LightpandaTest do
  use ExUnit.Case

  test "target returns a valid platform string" do
    target = Lightpanda.target()
    assert target in ["aarch64-macos", "x86_64-macos", "aarch64-linux", "x86_64-linux"]
  end

  test "release returns the baked-in fork tag" do
    assert Lightpanda.release() =~ ~r/^fork-\d{4}-\d{2}-\d{2}$/
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
end
