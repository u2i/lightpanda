# `:install` tests assume the binary is installed at the configured
# path. Skip by default; run with `mix test --include install` after
# `mix lightpanda.install`.
ExUnit.start(exclude: [:install])
