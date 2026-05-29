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
- **ATN model & deserializer** — `Seed.ATN` and `Seed.ATNDeserializer`
  reconstruct the full ATN graph (states, transitions, interval sets,
  lexer actions) from the tool's serialized integer stream, validated
  decision-for-decision against the canonical ANTLR4 runtime via golden
  fixtures (see `test/fixtures/atn/`).
- **Lexer** — `Seed.LexerATNSimulator` and `Seed.Lexer` tokenize input by
  simulating the lexer ATN, including lexer commands (`skip`, `channel`,
  `type`, modes). Validated against the reference lexer's token streams
  (see `test/fixtures/lex/`).
- **Parser** — `Seed.ParserATNSimulator` (adaptive LL(\*) prediction with
  the precedence filter) and `Seed.ParserInterpreter` build a parse tree by
  walking the ATN, including left-recursive rules. `parse/3` accepts a
  `Seed.Grammar` (or a bare ATN), and `Seed.Trees` renders the tree with the
  grammar's rule names. Validated against the reference parser's trees (see
  `test/fixtures/parse/`), including operator precedence.

- **DFA cache** — `Seed.DFACache` memoizes ATN decisions in a supervised,
  bounded ETS table (ADR-005), keyed per grammar. It is a pure speedup:
  results are identical with or without it.
- **Grammar loading** — `Seed.Interp` loads an ANTLR `.interp` file into a
  `Seed.Grammar` (ATN + vocabulary + rule/channel/mode names), so a grammar
  can be lexed and parsed at run time with no code generation.
- **Diagnostics** — `Seed.Lexer.tokenize/1` and `Seed.ParserInterpreter.parse/3`
  return `{:ok, result} | {:error, [Seed.Diagnostic.t()]}`; a diagnostic
  carries a machine-readable code, severity, and source position.

Full-context (LL) fallback for SLL-ambiguous grammars and the Elixir
code-generation target are the next milestones — see the architecture docs
for the full roadmap.

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

## Usage

Generate a grammar's `.interp` files with the ANTLR tool, then lex and
parse with no code generation:

```elixir
lexer = Seed.Interp.load!("ExprLexer.interp")
parser = Seed.Interp.load!("Expr.interp")

{:ok, tree} = Seed.parse(parser, lexer, "x = 1 + 2 * 3;", 0)
Seed.Trees.to_string_tree(tree, parser)
# => "(prog (stat x = (expr (expr 1) + (expr (expr 2) * (expr 3))) ;) <EOF>)"
```

`Seed.parse/4` and `Seed.tokenize/2` return `{:ok, result}` or
`{:error, [Seed.Diagnostic.t()]}`.

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
