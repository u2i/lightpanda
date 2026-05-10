# Changelog

## 0.2.10-rc.2 — 2026-05-10

- **Default URL now points at the [u2i fork build](https://github.com/u2i/lightpanda-browser)**
  of Lightpanda. The fork carries a patch to send session cookies on
  the WebSocket upgrade request, fixing cookie-authenticated WS
  endpoints (e.g. Phoenix LiveView). Override `:url` to use upstream
  binaries (see README).
- `@latest_version` bumped to `"fork-2026-05-10"` (the first u2i fork
  release tag).
- `@checksums` reset to empty: the upstream-version SHAs no longer
  apply to fork builds. Verification is skipped with a warning until
  the fork release artifacts have published checksums. Users can also
  opt out explicitly via `config :lightpanda, :verify_checksum, false`.
- New `:verify_checksum` config flag (defaults to `true`) — set
  `false` to silence the missing-checksum warning when pointing `:url`
  at a custom mirror or build.

## 0.2.10-rc.1

- Lazy install on first invocation, concurrent-call deduplication,
  startup version-mismatch warning.

## 0.2.9 and earlier

- See git log.
