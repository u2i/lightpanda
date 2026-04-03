defmodule Mix.Tasks.Lightpanda.Install do
  @moduledoc """
  Installs the Lightpanda binary.

      $ mix lightpanda.install
      $ mix lightpanda.install --if-missing

  By default, it installs #{Lightpanda.latest_version()} but you
  can configure it in your config files:

      config :lightpanda, version: "#{Lightpanda.latest_version()}"

  ## Options

    * `--runtime-config` - load the runtime configuration before executing.
    * `--if-missing` - only install if the binary is not already present.
  """

  @shortdoc "Installs the Lightpanda binary"
  use Mix.Task

  @impl true
  def run(args) do
    {opts, _} =
      OptionParser.parse_head!(args, strict: [runtime_config: :boolean, if_missing: :boolean])

    if opts[:runtime_config] do
      Mix.Task.run("app.config")
    end

    if opts[:if_missing] && File.exists?(Lightpanda.bin_path()) do
      :ok
    else
      Lightpanda.install()
    end
  end
end
