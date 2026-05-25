defmodule LightpandaTest do
  use ExUnit.Case

  test "target returns a valid platform string" do
    target = Lightpanda.target()

    assert target in [
             "aarch64-macos",
             "x86_64-macos",
             "aarch64-linux",
             "x86_64-linux",
             "aarch64-linux-musl",
             "x86_64-linux-musl"
           ]
  end

  describe "target/1 (deterministic input)" do
    test "linux glibc → <arch>-linux" do
      assert Lightpanda.target(%{arch: "aarch64", os: {:unix, :linux}, libc: :gnu}) ==
               "aarch64-linux"

      assert Lightpanda.target(%{arch: "x86_64", os: {:unix, :linux}, libc: :gnu}) ==
               "x86_64-linux"
    end

    test "linux musl → <arch>-linux-musl" do
      assert Lightpanda.target(%{arch: "aarch64", os: {:unix, :linux}, libc: :musl}) ==
               "aarch64-linux-musl"

      assert Lightpanda.target(%{arch: "x86_64", os: {:unix, :linux}, libc: :musl}) ==
               "x86_64-linux-musl"
    end

    test "macos ignores libc (always mach-o, no musl variant)" do
      assert Lightpanda.target(%{arch: "aarch64", os: {:unix, :darwin}, libc: :musl}) ==
               "aarch64-macos"
    end

    test "unsupported OS raises" do
      assert_raise RuntimeError, ~r/unsupported OS: nt/, fn ->
        Lightpanda.target(%{arch: "x86_64", os: {:win32, :nt}, libc: :gnu})
      end
    end

    test "unsupported arch raises" do
      assert_raise RuntimeError, ~r/unsupported architecture: riscv64/, fn ->
        Lightpanda.target(%{arch: "riscv64", os: {:unix, :linux}, libc: :gnu})
      end
    end
  end

  describe "detect_libc/1" do
    @tag :tmp_dir
    test "returns :musl when an ld-musl-*.so.1 loader exists", %{tmp_dir: tmp_dir} do
      File.touch!(Path.join(tmp_dir, "ld-musl-x86_64.so.1"))

      assert Lightpanda.detect_libc(libc_probe_dirs: [tmp_dir]) == :musl
    end

    @tag :tmp_dir
    test "returns :gnu when no musl loader is present", %{tmp_dir: tmp_dir} do
      assert Lightpanda.detect_libc(libc_probe_dirs: [tmp_dir]) == :gnu
    end
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
