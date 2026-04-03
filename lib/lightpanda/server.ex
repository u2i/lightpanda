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

  defstruct [:port_number, :host, :os_port, :ready]

  @ready_timeout 10_000

  @doc """
  Starts a Lightpanda server process.
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

    bin = Lightpanda.bin_path()

    unless File.exists?(bin) do
      Lightpanda.install()
    end

    args =
      ["serve", "--host", host, "--port", to_string(port_number)] ++ extra_args

    os_port =
      Port.open({:spawn_executable, bin}, [
        :binary,
        :stderr_to_stdout,
        :exit_status,
        args: args
      ])

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

  def handle_info({port, {:data, data}}, %{os_port: port} = state) do
    Logger.debug("[lightpanda] #{String.trim(data)}")
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{os_port: port} = state) do
    Logger.error("[lightpanda] process exited with status #{status}")
    {:stop, {:lightpanda_exit, status}, state}
  end

  @impl true
  def terminate(_reason, %{os_port: port} = _state) do
    if Port.info(port) != nil do
      Port.close(port)
    end

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
