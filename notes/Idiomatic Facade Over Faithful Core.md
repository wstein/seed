---
id: "20260529100100"
aliases: ["Two-layer design", "Faithful core"]
tags: ["architecture", "api", "porting"]
---
Seed is two layers: an idiomatic Elixir facade over a prediction engine that is a faithful transliteration of the reference ANTLR4 runtime. Idiom stops at the facade; the core stays literal so it can be validated decision-for-decision.

## What

The public API uses Elixir-native shapes — structs, behaviours, pattern matching, and `{:ok, result} | {:error, reason}` results. The internal prediction engine (ATN simulators, prediction context, configuration-set merging) mirrors the reference runtime's algorithm closely, even where that feels un-idiomatic.

## Why

The prediction engine is the most subtle code in ANTLR. It has no independent specification other than the reference implementation, so the only way to know it is correct is to diff its decisions against that reference. "Improving" it functionally would discard the oracle and risk parsing bugs that surface only on rare ambiguous grammars years later. The facade, by contrast, has obvious correct behavior and benefits from feeling native.

## How

Keep the seam explicit. Do not let Java-isms leak outward into the public API, and do not let idiomatic refactors leak inward into the simulators. When code generation uses macros, still emit inspectable source so generated parsers remain debuggable.

## Links

- [[Serialized ATN Is The Contract]] - The faithful core begins at deserializing the tool's output.
- [[Parsers Are Pure Functions]] - The idiomatic facade exposes parsing as pure functions.
- [[BEAM Native Caches For ATN And DFA]] - The core's caches use BEAM-native storage without leaking into the API.
