---
id: "20260529210000"
aliases: ["Seed.Diagnostic", "structured errors", "error tuples"]
tags: ["api", "errors", "diagnostics"]
---
Seed surfaces lex and parse failures as structured `Seed.Diagnostic` values returned in `{:error, [diagnostic]}`, not as raised strings. Each diagnostic carries a machine-readable code, a severity, the source position, and a message.

## What

`Seed.Lexer.tokenize/1` and `Seed.ParserInterpreter.parse/3` return
`{:ok, result} | {:error, [Seed.Diagnostic.t()]}`. Internally the hot path
still raises a `Seed.Lexer.Error`/`Seed.Parser.Error`, but those exceptions
now carry a `%Seed.Diagnostic{}`, which the public boundary rescues into the
error tuple.

## Why

Structured diagnostics suit tooling — editors and language servers can act
on a `code`, `severity`, `line`, and `column` rather than parse a string —
and returning them as values matches the project's idiomatic-facade rule
(`{:ok, _} | {:error, _}` at the edges). Keeping the raise internal avoids
threading result tuples through the recursive simulators; the translation
happens once, at the boundary. This is the foundation error recovery will
build on (recovery will accumulate several diagnostics rather than one).

## How

Build diagnostics at the raise site, where the offending token or input
position is in hand (`Seed.Diagnostic.error/3` takes `:line`/`:column`).
Rescue the carrying exception only at the public entry points; lower-level
streaming primitives such as `Seed.Lexer.next_token/1` keep raising. When a
grammar is supplied, the parser carries its `Seed.Vocabulary`, so mismatch
messages name the expected token (`expected ID`) instead of its numeric
type; without a vocabulary they fall back to the number.

The parser accumulates diagnostics on the `Seed.Parser` struct and recovers
where it can: single-token deletion drops an extraneous token when the next
one is the expected one, so a parse reports a diagnostic per error rather
than stopping at the first. An unrecoverable error raises with the full
accumulated list (`Seed.Parser.Error` carries `:diagnostics`); a parse that
recovered throughout still returns `{:error, diagnostics}` because the input
was not well-formed. Token insertion and resync sets are the next steps.

## Links

- [[Idiomatic Facade Over Faithful Core]] - Error tuples are part of the idiomatic facade over the raising core.
- [[Interp Files Are The Runtime Grammar Artifact]] - Diagnostics reference grammar positions; vocabulary names can enrich messages.
