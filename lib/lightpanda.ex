defmodule Lightpanda do
  @moduledoc """
  Lightpanda is an installer and runner for the
  [Lightpanda](https://github.com/lightpanda-io/browser) headless browser.

  ## Configuration

  Configure in your `config/config.exs`:

      config :lightpanda,
        version: "0.2.8",
        default: [
          args: ~w(serve --host 127.0.0.1 --port 9222)
        ]

  ## Global options

    * `:version` - the expected lightpanda version.

    * `:path` - the path to the lightpanda binary. By default it is
      automatically downloaded and placed inside the `_build` directory.

    * `:release` - which release to track. Either a version string like
      `"0.2.8"` (default, derived from `:version`) or `"nightly"` to
      track the nightly build.

  ## Profiles

  Each profile accepts:

    * `:args` - arguments to pass to the lightpanda binary.
    * `:cd` - the working directory.
    * `:env` - environment variables as a map of string key/value pairs.
  """

  require Logger

  # SHA-256 checksums for the release binaries, keyed by target.
  # Update these when bumping the version in mix.exs.
  @checksums %{
    "aarch64-linux" => "9f54f2cc31b0dadd867ba06ecce59f8aa59f7876394798e97882aea680b5ad19",
    "aarch64-macos" => "429c36619dc34535e54e1f00aafe9d40741bef9ccf292262afd74ed73f69057b",
    "x86_64-linux" => "8e3a5e04cf508699990a78a0a8686ea3398912cd9891fda90513429b89230300",
    "x86_64-macos" => "806bcccd2fa6445e4c06addf78abc7834833c5fbf977ea1f2d222fdc2bd77c3d"
  }

  @doc """
  Returns the latest known version of the Lightpanda binary.
  """
  def latest_version do
    Lightpanda.MixProject.project()[:version]
  end

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
    unless File.exists?(bin_path()) do
      install()
    end

    run(profile, extra_args)
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
  Installs the Lightpanda binary.
  """
  def install do
    version = configured_version()
    release = Application.get_env(:lightpanda, :release, version)
    target = target()
    name = "lightpanda-#{target}"

    base_url = "https://github.com/lightpanda-io/browser/releases/download"

    urls =
      case release do
        "nightly" ->
          ["#{base_url}/nightly/#{name}"]

        v ->
          # Lightpanda tags are inconsistent — some use "v" prefix, some don't
          ["#{base_url}/#{v}/#{name}", "#{base_url}/v#{v}/#{name}"]
      end

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

  defp verify_checksum!(file, target) do
    case @checksums[target] do
      nil ->
        Logger.warning("no checksum available for target #{target}, skipping verification")

      expected ->
        actual = file |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

        if actual != expected do
          raise """
          checksum mismatch for lightpanda-#{target}

            expected: #{expected}
            got:      #{actual}

          This could mean the download was corrupted or tampered with.
          If you've configured a custom version, update the checksums in the Lightpanda module.
          """
        end
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

  @doc false
  def config_for!(profile) when is_atom(profile) do
    Application.get_env(:lightpanda, profile) ||
      raise ArgumentError, """
      unknown lightpanda profile. Make sure the profile is defined in your config/config.exs file:

          config :lightpanda,
            version: "#{latest_version()}",
            #{profile}: [
              args: ~w(serve --host 127.0.0.1 --port 9222)
            ]
      """
  end
end
