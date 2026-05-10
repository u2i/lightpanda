defmodule Lightpanda do
  @moduledoc """
  Lightpanda is an installer and runner for the
  [Lightpanda](https://github.com/lightpanda-io/browser) headless browser.

  By default this package fetches binaries from the [u2i fork build][u2i]
  of Lightpanda, which carries an extra patch sending session cookies on
  the WebSocket upgrade request — required for cookie-authenticated WS
  endpoints (e.g. Phoenix LiveView). To use upstream binaries instead,
  override `:url` (see below).

  [u2i]: https://github.com/u2i/lightpanda-browser

  ## Configuration

  Configure in your `config/config.exs`:

      config :lightpanda,
        version: "fork-2026-05-10",
        default: [
          args: ~w(serve --host 127.0.0.1 --port 9222)
        ]

  ## Global options

    * `:version` - the expected lightpanda binary version. Defaults to
      the fork release tag this package tracks.

    * `:path` - the path to the lightpanda binary. By default it is
      automatically downloaded and placed inside the `_build` directory.

    * `:release` - which release to track. Either a version string
      (default, derived from `:version`) or `"nightly"` to track the
      nightly build (only available against upstream's URL template).

    * `:url` - the base URL template to download the binary from.
      Defaults to `Lightpanda.default_base_url/0` (u2i fork releases).
      To use upstream binaries:

          config :lightpanda,
            url: "https://github.com/lightpanda-io/browser/releases/download/$version/lightpanda-$target"

      Supports the placeholders `$version` and `$target`.

    * `:verify_checksum` - set to `false` to skip SHA-256 verification
      of the downloaded binary. Useful when pointing `:url` at a build
      whose checksums aren't baked into this package. Defaults to `true`.

    * `:version_check` - set to `false` to skip the boot-time check
      that warns when the installed binary's version doesn't match the
      configured `:version`. Defaults to `true`.

  ## Profiles

  Each profile accepts:

    * `:args` - arguments to pass to the lightpanda binary.
    * `:cd` - the working directory.
    * `:env` - environment variables as a map of string key/value pairs.
  """

  require Logger

  # SHA-256 checksums for the release binaries, keyed by target.
  # Empty by default — the u2i fork releases don't yet have published
  # checksums (the upstream-version SHAs in 0.2.10-rc.1 no longer
  # apply because the fork rebuilds binaries with the cookie-on-WS-
  # upgrade patch). Verification is skipped with a warning until this
  # map is populated. Set `config :lightpanda, :verify_checksum, false`
  # to silence the warning explicitly.
  @checksums %{}

  # The Lightpanda binary release this package tracks. Defaults to
  # the latest u2i fork release tag. Decoupled from the Hex package
  # version — bump when a new fork build is cut.
  @latest_version "fork-2026-05-10"

  @doc """
  Returns the latest known version of the Lightpanda binary.
  """
  def latest_version, do: @latest_version

  @doc """
  Returns the configured version of the Lightpanda binary.
  """
  def configured_version do
    Application.get_env(:lightpanda, :version, latest_version())
  end

  @doc """
  Returns the path to the Lightpanda binary.
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
  Returns the version of the installed Lightpanda binary, or `nil` if not found.
  """
  def bin_version do
    path = bin_path()

    with true <- File.exists?(path),
         {result, 0} <- System.cmd(path, ["version"], stderr_to_stdout: true) do
      result |> String.trim() |> parse_version()
    else
      _ -> nil
    end
  end

  defp parse_version(output) do
    case Regex.run(~r/(\d+\.\d+\.\d+)/, output) do
      [_, version] -> version
      _ -> output
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

  Concurrent callers are deduplicated via `Lightpanda.Installer` so
  that parallel `install_and_run/2` invocations (or `Lightpanda.Server`
  startups) only download once.
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
  Returns the default URL template used to fetch the binary.

  Defaults to the u2i fork releases (https://github.com/u2i/lightpanda-browser),
  which include the cookie-on-WebSocket-upgrade patch needed by cookie-
  authenticated WS endpoints (e.g. Phoenix LiveView).

  Supports `$version` and `$target` placeholders. Override via
  `config :lightpanda, :url, "..."` to point at upstream's releases
  or a local mirror.
  """
  def default_base_url do
    "https://github.com/u2i/lightpanda-browser/releases/download/$version/lightpanda-$target"
  end

  @doc """
  Installs the Lightpanda binary.
  """
  def install do
    version = configured_version()
    release = Application.get_env(:lightpanda, :release, version)
    target = target()
    name = "lightpanda-#{target}"

    urls = release_urls(release, target)

    bin = bin_path()

    tmp_dir =
      Path.join(System.tmp_dir!(), "lightpanda-install-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    tmp_file = Path.join(tmp_dir, name)

    try do
      download_first!(urls, tmp_file)
      verify_checksum!(tmp_file, target)
      File.chmod!(tmp_file, 0o755)
      File.mkdir_p!(Path.dirname(bin))
      File.cp!(tmp_file, bin)
    after
      File.rm_rf!(tmp_dir)
    end
  end

  # Build the candidate URL list for a given release. Templates the
  # configured (or default) base URL; for stable releases we also try
  # the legacy `v`-prefixed form because Lightpanda's tag naming has
  # been inconsistent across releases.
  defp release_urls(release, target) do
    template = Application.get_env(:lightpanda, :url, default_base_url())

    case release do
      "nightly" ->
        [render_url(template, "nightly", target)]

      v ->
        [render_url(template, v, target), render_url(template, "v" <> v, target)]
        |> Enum.uniq()
    end
  end

  defp render_url(template, version, target) do
    template
    |> String.replace("$version", version)
    |> String.replace("$target", target)
  end

  @doc false
  # Compares the installed binary's version to the configured version
  # and logs a warning on mismatch. Called from the application boot
  # sequence; opt out via `config :lightpanda, :version_check, false`.
  def maybe_warn_version_mismatch do
    if Application.get_env(:lightpanda, :version_check, true) do
      configured = configured_version()
      installed = bin_version()

      cond do
        is_nil(installed) ->
          :ok

        installed == configured ->
          :ok

        true ->
          Logger.warning("""
          Outdated lightpanda binary. Expected #{configured}, got #{installed}.
          Run `mix lightpanda.install` to update.
          """)
      end
    end

    :ok
  end

  defp verify_checksum!(file, target) do
    cond do
      Application.get_env(:lightpanda, :verify_checksum, true) == false ->
        # Opted out via config — used when pointing at a fork build whose
        # binaries don't match the upstream-version checksums baked in
        # below. Caller is responsible for source trust.
        Logger.info("checksum verification disabled via config, skipping")

      checksum = @checksums[target] ->
        actual = file |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

        if actual != checksum do
          raise """
          checksum mismatch for lightpanda-#{target}

            expected: #{checksum}
            got:      #{actual}

          This could mean the download was corrupted or tampered with.
          If you've configured a custom version, update the checksums in the Lightpanda module
          or set `config :lightpanda, :verify_checksum, false` to opt out.
          """
        end

      true ->
        Logger.warning("no checksum available for target #{target}, skipping verification")
    end
  end

  defp download_first!(urls, dest) do
    ensure_httpc!()

    Enum.reduce_while(urls, nil, fn url, _last_error ->
      case download(url, dest) do
        :ok -> {:halt, :ok}
        {:error, reason} -> {:cont, {url, reason}}
      end
    end)
    |> case do
      :ok ->
        :ok

      {url, reason} ->
        raise "couldn't download lightpanda from #{url}: #{reason}"
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
