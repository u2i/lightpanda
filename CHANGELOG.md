# Changelog

## 0.3.0 — 2026-05-23

- **Track upstream Lightpanda `v0.3.0`.** Bumped to fork release
  `fork-2026-05-23`, rebased onto upstream `v0.3.0`. Picks up 120
  commits of upstream improvements (CDP refactor, Page container,
  additional Worker APIs, SameSite cookie fixes) while keeping the
  WS-cookie-on-upgrade patch.
- **Hex package version now tracks the lightpanda binary version**
  (we jumped past `0.2.10` to match upstream's `0.3.0`). Future bumps
  follow upstream cadence — `0.3.1` when upstream cuts `v0.3.1`, etc.
- **Breaking: removed binary-source config knobs.** The package no
  longer reads `:version`, `:release`, `:url`, `:verify_checksum`, or
  `:version_check`. The release tag and download URL are baked in;
  bump the dep to upgrade. The `:path` knob is kept for developers
  running against a locally-built sibling checkout.
- **Removed APIs:**

  ```
  Lightpanda.latest_version/0
  Lightpanda.configured_version/0
  Lightpanda.bin_version/0
  Lightpanda.default_base_url/0
  Lightpanda.maybe_warn_version_mismatch/0
  ```

  Added `Lightpanda.release/0` returning the baked-in fork tag.

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
