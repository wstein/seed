# Cap each test at 30 s so a pathological parse cannot hang the suite (the
# resource guard in config/config.exs caps memory and CPU).
ExUnit.start(timeout: 30_000)
