defmodule Lightpanda.ServerTest do
  use ExUnit.Case

  @tag :server
  test "starts on a random port and responds to CDP version endpoint" do
    {:ok, pid} = Lightpanda.Server.start_link()

    ws_url = Lightpanda.Server.ws_url(pid)
    base_url = Lightpanda.Server.base_url(pid)
    port = Lightpanda.Server.port(pid)

    assert ws_url == "ws://127.0.0.1:#{port}"
    assert base_url == "http://127.0.0.1:#{port}"

    # Hit the CDP /json/version endpoint
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, {{_, 200, _}, _, body}} =
      :httpc.request(:get, {~c"#{base_url}/json/version", []}, [], body_format: :binary)

    assert body =~ "webSocketDebuggerUrl"

    Lightpanda.Server.stop(pid)
  end

  @tag :server
  test "starts on a specified port" do
    {:ok, socket} = :gen_tcp.listen(0, [:inet, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)

    {:ok, pid} = Lightpanda.Server.start_link(port: port)
    assert Lightpanda.Server.port(pid) == port

    Lightpanda.Server.stop(pid)
  end

  @tag :server
  test "multiple instances on different ports" do
    {:ok, pid1} = Lightpanda.Server.start_link()
    {:ok, pid2} = Lightpanda.Server.start_link()

    port1 = Lightpanda.Server.port(pid1)
    port2 = Lightpanda.Server.port(pid2)

    assert port1 != port2

    Lightpanda.Server.stop(pid1)
    Lightpanda.Server.stop(pid2)
  end
end
