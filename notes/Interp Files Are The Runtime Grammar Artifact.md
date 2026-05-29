---
id: "20260529200000"
aliases: ["Seed.Interp", "interp loading", "runtime grammar"]
tags: ["grammar", "interpreter", "interoperability"]
---
Seed loads an ANTLR `.interp` file as its runtime grammar artifact: one file carries the serialized ATN plus token, rule, channel, and mode names, so a grammar can be lexed and parsed at run time with no code generation.

## What

The ANTLR tool emits a `<Grammar>.interp` per recognizer alongside generated
code. `Seed.Interp.load!/1` parses its headed sections into a
`Seed.Grammar` (`atn`, `vocabulary`, `rule_names`, and for lexers
`channel_names`/`mode_names`), deserializing the bracketed ATN integers with
the existing `Seed.ATNDeserializer`.

## Why

Seed's interpreter already parses from a serialized ATN, but the ATN alone
lacks the names needed for diagnostics and tree rendering, which previously
had to be supplied out of band. The `.interp` file bundles all of it, so a
single artifact makes Seed an interpreter-first runtime: point it at a
`.interp` and parse, no build step. This also keeps the
serialized-ATN-as-contract boundary intact — the file is just that contract
plus the names the tool already computed.

## How

Treat `.interp` as the unit of grammar interchange. Load it once into a
`Seed.Grammar` and pass that to the lexer, parser interpreter, and tree
renderer rather than threading bare ATNs and rule-name lists. Regenerate
the test fixtures with `scripts/gen_interp_fixtures.sh`.

## Links

- [[Serialized ATN Is The Contract]] - The .interp file is that contract plus names.
- [[Idiomatic Facade Over Faithful Core]] - Grammar metadata is part of the idiomatic facade.
