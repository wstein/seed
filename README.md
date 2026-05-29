# Seed

Seed is an [ANTLR4](https://www.antlr.org/) parser runtime for the BEAM,
written in idiomatic Elixir. It lets grammars authored in ANTLR's `.g4`
notation drive lexers and parsers that run natively on the Erlang VM.

Seed follows the architecture pioneered by
[antlr-ng](https://github.com/antlr-ng/antlr-ng): the grammar **tool**
(the code generator) and the per-language **runtime** are decoupled. The
tool compiles a grammar into a language-neutral, serialized
[ATN](https://www.antlr.org/api/Java/org/antlr/v4/runtime/atn/ATN.html)
(Augmented Transition Network); each runtime only has to deserialize and
simulate that ATN. Seed is the BEAM runtime in that picture — it consumes
the same serialized ATN that the canonical ANTLR4 tool already emits.

## Status

Early development. The implemented and verified foundation is:

- **Tokens & vocabulary** — `Seed.Token`, `Seed.Vocabulary`.
- **Input streams** — `Seed.CharStream` (character input) and
  `Seed.TokenStream` (token buffering).

These layers are complete, tested, and have no dependency on the ATN
simulator. The prediction engine (ATN deserializer and the lexer/parser
ATN simulators) and the Elixir code-generation target are the next
milestones — see the architecture docs for the full roadmap.

## Design principles

- **Idiomatic at the edges, faithful at the core.** The public API is
  Elixir-native — structs, behaviours, pattern matching, and
  `{:ok, result} | {:error, reason}` results. The prediction-engine
  internals are a faithful transliteration of the reference ANTLR4
  runtime, so they can be validated against it decision-for-decision.
- **Serialized ATN is the contract.** Seed never reconstructs an ATN from
  a grammar; it deserializes the integer stream the tool produces. That
  makes the existing ANTLR grammar corpus a ready-made conformance oracle.
- **Pure functions, not processes.** A parse is a value transformation
  (tokens → tree), so parsers are plain modules and functions. Per-parse
  isolation is left to the caller's own processes.

## Getting started

Requires Elixir `~> 1.19` on Erlang/OTP 28.

```sh
make build    # mix compile
make test     # mix test
make check    # mix format --check-formatted
make verify   # check + test + build (the quality gate)
```

## Project layout

- `lib/` — the Seed runtime library.
- `test/` — ExUnit test suites.
- `docs/` — hand-authored arc42 architecture documentation.
- `notes/` — atomic design notes (durable knowledge; see `notes/README.md`).

## Documentation

Architecture documentation lives in `docs/` (an Antora/arc42 site) and is
maintained by hand alongside the code. Durable design decisions are
captured as atomic notes in `notes/`.
