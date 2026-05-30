# Vendored grammars

These grammars are third-party, kept verbatim (license header intact) for
conformance testing against the ANTLR reference. They are not authored by
this project.

- `SQLiteLexer.g4`, `SQLiteParser.g4` — from
  https://github.com/antlr/grammars-v4 (`sql/sqlite`), MIT License,
  Copyright (c) 2014 Bart Kiers. Used as a large, real-world grammar to
  stress scale and breadth.
- `Erlang.g4` — from https://github.com/antlr/grammars-v4 (`erlang`), BSD
  licence, Copyright (c) 2013 Terence Parr.
- `ElixirLexer.g4`, `ElixirParser.g4` — from
  https://github.com/antlr/grammars-v4 (`elixir`), MIT License, Copyright
  (c) 2023 bkiers. Used to parse Seed's own Elixir source (see
  `mix seed.dogfood.elixir`).
