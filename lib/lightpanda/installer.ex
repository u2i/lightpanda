defmodule Lightpanda.Installer do
  @moduledoc false

  # Serializes binary downloads. Multiple callers that hit
  # `Lightpanda.ensure_installed!/0` concurrently all queue against
  # this GenServer's mailbox; the first call performs the download,
  # subsequent calls short-circuit once the binary exists on disk.

  use GenServer

  @install_timeout 5 * 60 * 1_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Blocks until the Lightpanda binary is installed on disk.
  """
  def install do
    case GenServer.whereis(__MODULE__) do
      nil ->
        # Application hasn't started (e.g. compile-time call) — fall
        # back to synchronous install with no concurrency control.
        Lightpanda.install()

      _pid ->
        case GenServer.call(__MODULE__, :install, @install_timeout) do
          :ok ->
            :ok

          {:error, {:throw, reason, _stack}} ->
            throw(reason)

          {:error, {:exit, reason, _stack}} ->
            exit(reason)

          {:error, {:error, reason, stack}} ->
            reraise reason, stack
        end
    end
  end

  @impl true
  def init(:ok), do: {:ok, %{}}

  @impl true
  def handle_call(:install, _from, state) do
    if File.exists?(Lightpanda.bin_path()) do
      {:reply, :ok, state}
    else
      try do
        Lightpanda.install()
        {:reply, :ok, state}
      catch
        kind, reason ->
          {:reply, {:error, {kind, reason, __STACKTRACE__}}, state}
      end
    end
  end
end
