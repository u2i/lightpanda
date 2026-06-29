# Changelog

## 0.3.4-rc.0 — 2026-06-29

- **`Lightpanda.Server` now accepts a `:wrapper_script` option.**
  When supplied, the server spawns the wrapper (with `:use_stdio`) and
  passes the Lightpanda binary + args as its arguments, rather than
  spawning the binary directly.  The wrapper must print `PID: <n>` on
  stdout so the server can capture the child's OS pid for `kill -9` in
  `terminate/2`, and must kill the child when its stdin closes.  This
  allows Lightpanda to be cleaned up even when the BEAM is terminated
  with SIGKILL — in which case `terminate/2` never runs, but the Port's
  stdin pipe closes at the OS level and the wrapper fires `kill -KILL`
  on Lightpanda.  Without `:wrapper_script` behaviour is unchanged.
  See `priv/run_command.sh` in the [wallabidi](https://github.com/u2i/wallabidi)
  library for a reference wrapper implementation.

## 0.3.1 — 2026-05-30

- **Track upstream Lightpanda `v0.3.1`.** Bumped fork release tag to
  `fork-2026-05-30`, rebased the cookie-on-WS-upgrade patch onto
  upstream `v0.3.1`. The patch was reworked to use the new
  `exec.context.global` API (a `GlobalScope` union of `.frame` /
  `.worker`) since upstream refactored `WebSocket.init` to take an
  `Execution` instead of a `*Frame`. Picks up upstream improvements
  while keeping cookie-authenticated WS upgrades working.
- **Expanded test coverage on the cookie patch.** The fork now ships
  four additional regression tests alongside the original happy-path:
  path-scoped cookies don't leak across paths, `SameSite=Strict` still
  attaches on same-site upgrades, empty cookie jar produces no
  `Cookie:` header, and multiple matching cookies are joined per RFC
  6265 §5.4.
- **New `:install_dir` config + `LIGHTPANDA_INSTALL_DIR` env var.**
  Override the directory the binary is installed and looked for in,
  while the package keeps owning the per-target filename
  (`lightpanda-<target>`). Relative paths resolve against
  `File.cwd!/0`, so `config :lightpanda, install_dir: ".browsers"`
  lands the binary under `<project_root>/.browsers/` — matching the
  layout used by Chrome for Testing / Puppeteer and making
  Docker/CI cache mapping a single-directory affair. Default
  behaviour is unchanged (`_build/lightpanda-<target>`). Precedence:
  `:path` (full file) > `:install_dir` config > `LIGHTPANDA_INSTALL_DIR`
  env var > default.

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
