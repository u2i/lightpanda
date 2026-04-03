defmodule Mix.Tasks.Lightpanda do
  @moduledoc """
  Invokes lightpanda with the given profile and args.

      $ mix lightpanda default serve --host 127.0.0.1 --port 9222
      $ mix lightpanda default fetch https://example.com

  The first argument is the profile name (default: `default`), and the
  remaining arguments are passed directly to the lightpanda binary.

  ## Options

    * `--runtime-config` - load runtime configuration before executing.
  """

  @shortdoc "Invokes lightpanda with the profile and args"
  use Mix.Task

  @impl true
  def run(args) do
    {opts, remaining} = OptionParser.parse_head!(args, strict: [runtime_config: :boolean])

    if opts[:runtime_config] do
      Mix.Task.run("app.config")
    else
      Application.ensure_all_started(:lightpanda)
    end

    Mix.Task.reenable("lightpanda")

    case remaining do
      [profile | extra_args] ->
        install_and_run(String.to_atom(profile), extra_args)

      [] ->
        install_and_run(:default, [])
    end
  end

  defp install_and_run(profile, args) do
    case Lightpanda.install_and_run(profile, args) do
      0 -> :ok
      status -> Mix.raise("lightpanda exited with status #{status}")
    end
  end
end
