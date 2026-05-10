# Lightpanda

Mix tasks for installing and invoking the
[Lightpanda](https://github.com/lightpanda-io/browser) headless browser.

By default this package fetches binaries from the
[u2i fork build](https://github.com/u2i/lightpanda-browser) of
Lightpanda, which carries an extra patch sending session cookies on the
WebSocket upgrade request. Without this, cookie-authenticated WS
endpoints (e.g. Phoenix LiveView) reject the upgrade.

## Installation

```elixir
def deps do
  [
    {:lightpanda, "~> 0.2.10-rc.2", only: :test}
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

| Option              | Default                            | Description                                                                                  |
|---------------------|------------------------------------|----------------------------------------------------------------------------------------------|
| `:version`          | the fork release tag (see below)   | The binary release this dep tracks.                                                          |
| `:release`          | derived from `:version`            | Override the release name independently of `:version` (e.g. `"nightly"` for upstream URLs).  |
| `:path`             | `_build/lightpanda-<target>`       | Path the binary is installed to.                                                             |
| `:url`              | u2i fork release URL template      | Base URL template with `$version` / `$target` placeholders.                                  |
| `:verify_checksum`  | `true`                             | Verify the SHA-256 of the downloaded binary against the package's bundled checksums.         |
| `:version_check`    | `true`                             | Warn at boot if the installed binary's version doesn't match `:version`.                     |

### Use upstream binaries instead of the fork

```elixir
config :lightpanda,
  url: "https://github.com/lightpanda-io/browser/releases/download/$version/lightpanda-$target",
  version: "0.2.9",
  verify_checksum: false  # this package's @checksums map targets fork builds
```

### Use a local mirror

```elixir
config :lightpanda,
  url: "https://my-mirror.example.com/lightpanda/$version/lightpanda-$target"
```

## Why a fork?

The cookie-on-WebSocket-upgrade fix has been submitted to upstream
([PR](https://github.com/lightpanda-io/browser) — pending review). Until
that ships, this package defaults to the u2i build so cookie-
authenticated WS endpoints work out of the box.

## License

MIT.
