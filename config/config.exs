import Config

# Resource guard for *this* project's runs (tests, `mix run`, IEx). A
# dependency never loads this config, so it does not constrain a host
# application that merely depends on `seed` — see `Seed.Application`.
#
#   * cap each process's heap at ~2 GB and kill it if exceeded (so a runaway
#     parse cannot OOM the machine — the parser's own prediction guard
#     normally fails gracefully long before this); and
#   * cap the BEAM at half the available schedulers (limit CPU).
config :seed,
  resource_guard: [
    # 268_435_456 words * 8 bytes ≈ 2 GB
    max_heap_words: 268_435_456,
    cap_schedulers_to: :half
  ]
