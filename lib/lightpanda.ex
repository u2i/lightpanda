defmodule Lightpanda do
  @moduledoc """
  Lightpanda is an installer and runner for the
  [Lightpanda](https://github.com/lightpanda-io/browser) headless browser.

  This package fetches binaries from the [u2i fork build][u2i] of
  Lightpanda, which carries an extra patch sending session cookies on
  the WebSocket upgrade request — required for cookie-authenticated WS
  endpoints (e.g. Phoenix LiveView). The release tag, download URL,
  and checksums are baked in; there are no knobs for swapping the
  source. If you need an unpatched upstream binary, depend on a
  different installer.

  [u2i]: https://github.com/u2i/lightpanda-browser

  ## Configuration

  Configure in your `config/config.exs`:

      config :lightpanda,
        default: [
          args: ~w(serve --host 127.0.0.1 --port 9222)
        ]

  ## Global options

    * `:path` - point at a locally-built binary on disk instead of the
      one this package downloads. Intended for developers working on
      the lightpanda fork itself who want to test rebuilds without
      republishing the package. Production users should leave this
      unset.

  ## Profiles

  Each profile accepts:

    * `:args` - arguments to pass to the lightpanda binary.
    * `:cd` - the working directory.
    * `:env` - environment variables as a map of string key/value pairs.
  """

  require Logger

  # The Lightpanda binary release this package tracks. Bump (and
  # publish a new package version) when a new fork build is cut.
  @release "fork-2026-05-25"

  @doc """
  Returns the release tag of the Lightpanda binary this package
  downloads.
  """
  def release, do: @release

  @doc """
  Returns the path to the Lightpanda binary.

  By default this is `_build/lightpanda-<target>`. The `:path` config
  knob overrides it for developers running against a local sibling
  checkout of the lightpanda fork — see the module doc.
  """
  def bin_path do
    name = "lightpanda-#{target()}"

    Application.get_env(:lightpanda, :path) ||
      if Code.ensure_loaded?(Mix.Project) do
        Path.join(Path.dirname(Mix.Project.build_path()), name)
      else
        Path.expand("_build/#{name}")
      end
  end

  @doc """
  Returns the platform target string (e.g., `"aarch64-macos"`,
  `"x86_64-linux"`, `"x86_64-linux-musl"`).

  On Linux, the libc flavor is detected at runtime via
  `detect_libc/1` so we pick the right release asset for glibc-based
  distros (Debian, Ubuntu, RHEL) vs musl-based ones (Alpine,
  distroless-static, Void).
  """
  def target do
    target(%{
      arch: detect_arch(),
      os: :os.type(),
      libc: detect_libc()
    })
  end

  @doc false
  # Deterministic core for `target/0`. Public for testing — callers in
  # production should use `target/0`. The map shape mirrors what
  # `target/0` derives from the runtime so the test suite can exercise
  # every (arch, os, libc) combination without touching the host.
  def target(%{arch: arch, os: os, libc: libc}) do
    arch_str =
      case arch do
        "aarch64" <> _ -> "aarch64"
        "arm" <> _ -> "aarch64"
        "x86_64" <> _ -> "x86_64"
        _ -> raise "unsupported architecture: #{arch}"
      end

    case os do
      {:unix, :darwin} ->
        # macOS: no musl variant; always Mach-O against the system libc.
        "#{arch_str}-macos"

      {:unix, :linux} ->
        case libc do
          :gnu -> "#{arch_str}-linux"
          :musl -> "#{arch_str}-linux-musl"
        end

      {_, name} ->
        raise "unsupported OS: #{name}"
    end
  end

  @doc """
  Detects the host's libc flavor. Returns `:musl` if a musl dynamic
  linker is present in any of the probed directories (default
  `/lib`), otherwise `:gnu`.

  ## Options
    * `:libc_probe_dirs` — list of directories to scan for an
      `ld-musl-*.so.1` loader. Exposed for testing; production
      callers should pass no opts.
  """
  @spec detect_libc(keyword) :: :gnu | :musl
  def detect_libc(opts \\ []) do
    probe_dirs = Keyword.get(opts, :libc_probe_dirs, ["/lib"])

    musl_loader? =
      Enum.any?(probe_dirs, fn dir ->
        case File.ls(dir) do
          {:ok, entries} -> Enum.any?(entries, &String.match?(&1, ~r/^ld-musl-.*\.so\.1$/))
          _ -> false
        end
      end)

    if musl_loader?, do: :musl, else: :gnu
  end

  defp detect_arch, do: :erlang.system_info(:system_architecture) |> List.to_string()

  @doc """
  Installs the binary if missing, then runs it with the given profile and extra arguments.

  Returns the exit status.
  """
  def install_and_run(profile, extra_args) do
    ensure_installed!()
    run(profile, extra_args)
  end

  @doc """
  Ensures the Lightpanda binary is installed.

  Concurrent callers are deduplicated via an internal installer
  GenServer so that parallel `install_and_run/2` invocations (or
  Lightpanda.Server startups) only download once.
  """
  def ensure_installed! do
    if File.exists?(bin_path()) do
      :ok
    else
      Lightpanda.Installer.install()
    end
  end

  @doc """
  Runs the Lightpanda binary with the given profile and extra arguments.
  """
  def run(profile, extra_args \\ []) when is_atom(profile) and is_list(extra_args) do
    config = config_for!(profile)
    args = config[:args] || []

    env =
      config
      |> Keyword.get(:env, %{})
      |> Enum.map(fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    opts = [
      cd: config[:cd] || File.cwd!(),
      env: env,
      into: IO.stream(:stdio, :line),
      stderr_to_stdout: true
    ]

    bin_path()
    |> System.cmd(args ++ extra_args, opts)
    |> elem(1)
  end

  @doc """
  Installs the Lightpanda binary by downloading it from the u2i fork
  release for the configured `@release` tag.
  """
  def install do
    target = target()
    name = "lightpanda-#{target}"
    bin = bin_path()

    tmp_dir =
      Path.join(System.tmp_dir!(), "lightpanda-install-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    tmp_file = Path.join(tmp_dir, name)

    try do
      download!(release_url(target), tmp_file)
      File.chmod!(tmp_file, 0o755)
      File.mkdir_p!(Path.dirname(bin))
      File.cp!(tmp_file, bin)
    after
      File.rm_rf!(tmp_dir)
    end
  end

  defp release_url(target) do
    "https://github.com/u2i/lightpanda-browser/releases/download/" <>
      "#{@release}/lightpanda-#{target}"
  end

  defp download!(url, dest) do
    ensure_httpc!()

    case download(url, dest) do
      :ok -> :ok
      {:error, reason} -> raise "couldn't download lightpanda from #{url}: #{reason}"
    end
  end

  defp ensure_httpc! do
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)
    {:ok, _} = Application.ensure_all_started(:public_key)
  end

  defp download(url, dest) do
    Logger.debug("Downloading lightpanda from #{url}")

    if proxy = proxy_for_scheme(URI.parse(url).scheme) do
      %{host: host, port: port} = URI.parse(proxy)
      :httpc.set_options([{proxy_option(URI.parse(url).scheme), {{String.to_charlist(host), port}, []}}])
    end

    http_options = [
      ssl: ssl_options(),
      relaxed: true,
      autoredirect: true
    ]

    options = [body_format: :binary]

    case :httpc.request(:get, {String.to_charlist(url), []}, http_options, options) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        File.write!(dest, body)
        :ok

      {:ok, {{_, status, _}, _headers, _body}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp ssl_options do
    cacertfile = cacertfile()

    [
      verify: :verify_peer,
      cacertfile: String.to_charlist(cacertfile),
      depth: 4,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end

  defp proxy_for_scheme("http"), do: System.get_env("HTTP_PROXY") || System.get_env("http_proxy")

  defp proxy_for_scheme("https"),
    do: System.get_env("HTTPS_PROXY") || System.get_env("https_proxy")

  defp proxy_for_scheme(_), do: nil

  defp proxy_option("http"), do: :proxy
  defp proxy_option("https"), do: :https_proxy

  defp cacertfile do
    cond do
      path = Application.get_env(:lightpanda, :cacerts_path) ->
        path

      path = System.get_env("LIGHTPANDA_CACERTS_PATH") ->
        path

      Code.ensure_loaded?(CAStore) ->
        CAStore.file_path()

      true ->
        # Fall back to OS certificates via OTP
        otp_cacertfile()
    end
  end

  defp otp_cacertfile do
    certs = :public_key.cacerts_get()
    pem_entries = Enum.map(certs, &:public_key.pem_entry_encode(:Certificate, &1))
    pem = :public_key.pem_encode(pem_entries)
    path = Path.join(System.tmp_dir!(), "lightpanda-cacerts.pem")
    File.write!(path, pem)
    path
  end

  @default_profiles %{
    default: [args: ~w(serve --host 127.0.0.1 --port 9222)]
  }

  @doc false
  def config_for!(profile) when is_atom(profile) do
    Application.get_env(:lightpanda, profile) ||
      @default_profiles[profile] ||
      raise ArgumentError, """
      unknown lightpanda profile. Make sure the profile is defined in your config/config.exs file:

          config :lightpanda,
            #{profile}: [
              args: ~w(serve --host 127.0.0.1 --port 9222)
            ]
      """
  end
end
