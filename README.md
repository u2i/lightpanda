# Lightpanda

Mix tasks for installing and invoking the
[Lightpanda](https://github.com/lightpanda-io/browser) headless browser.

This package fetches binaries from the
[u2i fork build](https://github.com/u2i/lightpanda-browser) of
Lightpanda, which carries an extra patch sending session cookies on the
WebSocket upgrade request. Without this, cookie-authenticated WS
endpoints (e.g. Phoenix LiveView) reject the upgrade.

The release tag and download URL are baked into the package; bump the
dep to upgrade. If you need an unpatched upstream binary, depend on a
different installer.

## Installation

```elixir
def deps do
  [
    {:lightpanda, "~> 0.3", only: :test}
  ]
end
```

### Supported platforms

| Platform                | Asset                              |
|-------------------------|------------------------------------|
| macOS (Apple Silicon)   | `lightpanda-aarch64-macos`         |
| Linux x86_64 (glibc)    | `lightpanda-x86_64-linux`          |
| Linux aarch64 (glibc)   | `lightpanda-aarch64-linux`         |
| Linux x86_64 (musl)     | `lightpanda-x86_64-linux-musl`     |
| Linux aarch64 (musl)    | `lightpanda-aarch64-linux-musl`    |

On Linux the libc flavor is detected at runtime by looking for a musl
dynamic linker (`/lib/ld-musl-*.so.1`). Alpine, distroless-static, and
other musl-based distros automatically pick the `-linux-musl` asset.

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
