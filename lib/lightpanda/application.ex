defmodule Lightpanda.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      Lightpanda.Installer
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Lightpanda.Supervisor)
  end
end
