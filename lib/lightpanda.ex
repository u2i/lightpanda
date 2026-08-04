defmodule Lightpanda do
  @moduledoc """
  Lightpanda is an installer and runner for the
  [Lightpanda](https://github.com/lightpanda-io/browser) headless browser.

  This package fetches binaries from the official upstream releases.
  The release tag and download URL are baked in; there are no knobs
  for swapping the source. Bump the dep to upgrade.

  ## Configuration

  Configure in your `config/config.exs`:

      config :lightpanda,
        default: [
          args: ~w(serve --host 127.0.0.1 --port 9222)
        ]

  ## Global options

    * `:path` - point at a locally-built binary on disk instead of the
      one this package downloads. Takes a full file path, not a
      directory. Intended for developers working on the lightpanda
      fork itself who want to test rebuilds without republishing the
      package. Production users should leave this unset.

    * `:install_dir` - directory where the binary is installed and
      looked for. The package always picks the filename
      (`lightpanda-<target>`), so consumers set only the directory.
      Relative paths are resolved against the current working
      directory (`File.cwd!/0`) — e.g. `".browsers"` resolves to
      `<project_root>/.browsers/lightpanda-<target>`, matching the
      convention used by Chrome for Testing and Puppeteer. May also
      be set via the `LIGHTPANDA_INSTALL_DIR` environment variable;
      the config key takes precedence when both are present.

  Precedence: `:path` (full file) overrides `:install_dir` (directory),
  which overrides the default location under `_build/`.

  ## Profiles

  Each profile accepts:

    * `:args` - arguments to pass to the lightpanda binary.
    * `:cd` - the working directory.
    * `:env` - environment variables as a map of string key/value pairs.
  """

  require Logger

  # The Lightpanda binary release this package tracks. Bump (and
  # publish a new package version) when upstream cuts a release.
  # Pinned to an explicit tag rather than resolved as "latest" —
  # upstream marks its rolling `nightly` release as latest.
  @release "0.3.6"

  @doc """
  Returns the release tag of the Lightpanda binary this package
  downloads.
  """
  def release, do: @release

  @doc """
  Returns the path to the Lightpanda binary.

  By default this is `_build/lightpanda-<target>`. Override via
  `:path` (full file path) or `:install_dir` /
  `LIGHTPANDA_INSTALL_DIR` (directory; the package supplies the
  per-target filename). See the module doc for precedence.
  """
  def bin_path do
    Application.get_env(:lightpanda, :path) ||
      Path.join(install_dir(), "lightpanda-#{target()}")
  end

  defp install_dir do
    configured =
      Application.get_env(:lightpanda, :install_dir) ||
        System.get_env("LIGHTPANDA_INSTALL_DIR")

    case configured do
      nil -> default_install_dir()
      "" -> default_install_dir()
      dir -> Path.expand(dir, File.cwd!())
    end
  end

  defp default_install_dir do
    if Code.ensure_loaded?(Mix.Project) do
      Path.dirname(Mix.Project.build_path())
    else
      Path.expand("_build")
    end
  end

  @doc """
  Returns the platform target string (e.g., `"aarch64-macos"`).
  """
  def target do
    arch_str =
      case :erlang.system_info(:system_architecture) |> List.to_string() do
        "aarch64" <> _ -> "aarch64"
        "arm" <> _ -> "aarch64"
        "x86_64" <> _ -> "x86_64"
        _ -> raise "unsupported architecture: #{:erlang.system_info(:system_architecture)}"
      end

    os_str =
      case :os.type() do
        {:unix, :darwin} -> "macos"
        {:unix, :linux} -> "linux"
        {_, os} -> raise "unsupported OS: #{os}"
      end

    "#{arch_str}-#{os_str}"
  end

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
  Installs the Lightpanda binary by downloading it from the upstream
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
    "https://github.com/lightpanda-io/browser/releases/download/" <>
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
