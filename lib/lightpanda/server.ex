defmodule Lightpanda.Server do
  @moduledoc """
  A GenServer that manages a Lightpanda browser process.

  Starts the binary in serve mode on an automatically-assigned port,
  waits for it to be ready, and provides the WebSocket URL for CDP
  connections.

  ## Usage

      {:ok, pid} = Lightpanda.Server.start_link()
      ws_url = Lightpanda.Server.ws_url(pid)
      # => "ws://127.0.0.1:52431"

  ## Options

    * `:host` - the host to bind to (default: `"127.0.0.1"`)
    * `:port` - the port to bind to (default: automatically assigned)
    * `:extra_args` - additional CLI arguments to pass to the binary
    * `:name` - GenServer name registration
  """

  use GenServer
  require Logger

  defstruct [:port_number, :host, :os_port, :os_pid, :ready]

  @ready_timeout 10_000

  @doc """
  Starts a Lightpanda server process.

  Options:

    * `:host` - the host to bind to (default: `"127.0.0.1"`)
    * `:port` - the port to bind to (default: automatically assigned)
    * `:extra_args` - additional CLI arguments to pass to the binary
    * `:name` - GenServer name registration
    * `:wrapper_script` - optional path to a wrapper shell script that
      re-executes the binary as its first argument. When supplied the
      Port spawns the wrapper (not the binary directly) with
      `:use_stdio` enabled.  The wrapper must print `PID: <n>` on
      stdout before the child is killed so this server can capture the
      OS pid for `kill -9` in `terminate/2`, and must kill the child
      when its stdin closes.  This allows the Lightpanda process to be
      cleaned up even when the BEAM is killed with SIGKILL (in which
      case `terminate/2` never runs but the Port's stdin pipe closes at
      the OS level).  See `priv/run_command.sh` in the wallabidi
      library for a reference implementation.
  """
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Returns the WebSocket URL for CDP connections.

  Blocks until the server is ready, up to the timeout.
  """
  def ws_url(server, timeout \\ @ready_timeout) do
    GenServer.call(server, :ws_url, timeout)
  end

  @doc """
  Returns the base HTTP URL (e.g. for `/json/version`).
  """
  def base_url(server, timeout \\ @ready_timeout) do
    GenServer.call(server, :base_url, timeout)
  end

  @doc """
  Returns the port number the server is listening on.
  """
  def port(server, timeout \\ @ready_timeout) do
    GenServer.call(server, :port, timeout)
  end

  @doc """
  Stops the server and the underlying Lightpanda process.
  """
  def stop(server) do
    GenServer.stop(server)
  end

  # -- Callbacks --

  @impl true
  def init(opts) do
    host = Keyword.get(opts, :host, "127.0.0.1")
    port_number = Keyword.get(opts, :port) || find_available_port()
    extra_args = Keyword.get(opts, :extra_args, [])

    Lightpanda.ensure_installed!()
    bin = Lightpanda.bin_path()
    wrapper = Keyword.get(opts, :wrapper_script)

    lp_args = ["serve", "--host", host, "--port", to_string(port_number)] ++ extra_args

    {executable, port_args, extra_port_opts} =
      if wrapper do
        {wrapper, [bin | lp_args], [:use_stdio]}
      else
        {bin, lp_args, []}
      end

    os_port =
      Port.open({:spawn_executable, to_charlist(executable)}, [
        :binary,
        :stderr_to_stdout,
        :exit_status
        | extra_port_opts
      ] ++ [args: port_args])

    state = %__MODULE__{
      port_number: port_number,
      host: host,
      os_port: os_port,
      ready: false
    }

    # Start readiness check
    send(self(), :check_ready)

    {:ok, state}
  end

  @impl true
  def handle_call(:ws_url, from, %{ready: false} = state) do
    {:noreply, Map.update(state, :waiters, [from], &[from | &1])}
  end

  def handle_call(:ws_url, _from, state) do
    {:reply, "ws://#{state.host}:#{state.port_number}", state}
  end

  def handle_call(:base_url, from, %{ready: false} = state) do
    {:noreply, Map.update(state, :base_waiters, [from], &[from | &1])}
  end

  def handle_call(:base_url, _from, state) do
    {:reply, "http://#{state.host}:#{state.port_number}", state}
  end

  def handle_call(:port, from, %{ready: false} = state) do
    {:noreply, Map.update(state, :port_waiters, [from], &[from | &1])}
  end

  def handle_call(:port, _from, state) do
    {:reply, state.port_number, state}
  end

  @impl true
  def handle_info(:check_ready, state) do
    case check_port_open(state.host, state.port_number) do
      true ->
        state = reply_to_waiters(%{state | ready: true})
        {:noreply, state}

      false ->
        Process.send_after(self(), :check_ready, 50)
        {:noreply, state}
    end
  end

  def handle_info({port, {:data, data}}, %{os_port: port, os_pid: nil} = state) do
    state =
      case Regex.run(~r/PID:\s*(\d+)/, data) do
        [_, pid_str] -> %{state | os_pid: String.to_integer(pid_str)}
        nil -> state
      end

    Logger.debug("[lightpanda] #{String.trim(data)}")
    {:noreply, state}
  end

  def handle_info({port, {:data, data}}, %{os_port: port} = state) do
    Logger.debug("[lightpanda] #{String.trim(data)}")
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{os_port: port} = state) do
    Logger.error("[lightpanda] process exited with status #{status}")
    {:stop, {:lightpanda_exit, status}, state}
  end

  @impl true
  def terminate(_reason, %{os_port: port, os_pid: os_pid} = _state) do
    # Kill the Lightpanda process directly with SIGKILL — it ignores SIGTERM.
    # When a wrapper_script was used, os_pid is the Lightpanda child (not the
    # wrapper); without a wrapper, fall back to the Port's os_pid.
    pid_to_kill =
      os_pid ||
        case Port.info(port) do
          info when is_list(info) -> Keyword.get(info, :os_pid)
          nil -> nil
        end

    if pid_to_kill do
      System.cmd("kill", ["-9", to_string(pid_to_kill)], stderr_to_stdout: true)
    end

    # Closing the Port also closes its stdin pipe. When a wrapper_script
    # is in use, the wrapper's stdin-close handler fires kill -KILL on
    # Lightpanda — this is the path that cleans up on BEAM kill -9.
    if Port.info(port) != nil, do: Port.close(port)

    :ok
  end

  # -- Private --

  defp find_available_port do
    {:ok, socket} = :gen_tcp.listen(0, [:inet, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  defp check_port_open(host, port) do
    case :gen_tcp.connect(String.to_charlist(host), port, [:inet], 100) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _} ->
        false
    end
  end

  defp reply_to_waiters(state) do
    ws = "ws://#{state.host}:#{state.port_number}"
    base = "http://#{state.host}:#{state.port_number}"

    for from <- Map.get(state, :waiters, []), do: GenServer.reply(from, ws)
    for from <- Map.get(state, :base_waiters, []), do: GenServer.reply(from, base)
    for from <- Map.get(state, :port_waiters, []), do: GenServer.reply(from, state.port_number)

    state
    |> Map.delete(:waiters)
    |> Map.delete(:base_waiters)
    |> Map.delete(:port_waiters)
  end
end
