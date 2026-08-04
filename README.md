# Lightpanda

Mix tasks for installing and invoking the
[Lightpanda](https://github.com/lightpanda-io/browser) headless browser.

This package fetches binaries from the official upstream Lightpanda
releases. The package version tracks the binary version it installs.

The release tag and download URL are baked into the package; bump the
dep to upgrade.

## Installation

```elixir
def deps do
  [
    {:lightpanda, "~> 0.3.0", only: :test}
  ]
end
```

## Quick start

```elixir
# config/test.exs
config :lightpanda,
  default: [args: ~w(serve --host 127.0.0.1 --port 9222)]
```

```sh
mix lightpanda.install   # download the binary
mix lightpanda           # run the default profile
```

## Configuration

| Option   | Default                            | Description                                                                          |
|----------|------------------------------------|--------------------------------------------------------------------------------------|
| `:path`  | `_build/lightpanda-<target>`       | Override the binary location. Intended for developers running against a locally-built sibling checkout of the fork; production users should leave it unset. |

## Why a fork?

The cookie-on-WebSocket-upgrade fix has been submitted to upstream
([PR](https://github.com/lightpanda-io/browser) — pending review). Until
that ships, this package uses the u2i build so cookie-authenticated WS
endpoints work out of the box.

## License

MIT.
