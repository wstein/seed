---
id: "20260529100200"
aliases: ["No GenServer parser", "Parsing as a value transformation"]
tags: ["architecture", "api", "concurrency"]
---
Seed models a parse as a pure transformation of tokens into a tree. Lexers and parsers are plain modules and functions with no process identity; concurrency and isolation are the caller's concern.

## What

There is no `GenServer` or process behind a Seed parser. Calling a parser is calling a function: input values in, result values out, no hidden mutable state across calls.

## Why

A parse is deterministic and self-contained, so a process would add a mailbox bottleneck and concealed state without benefit. Keeping parsing referentially transparent makes it trivially testable and reproducible. It also lets callers exploit the BEAM's real strength — many isolated concurrent parses — by spawning their own processes, each running a parse in isolation, rather than contending on a shared parser process.

## How

Expose lexing and parsing as functions returning `{:ok, result} | {:error, reason}`. Where the algorithm needs caches (the adaptive DFA), share them through BEAM-native storage keyed by grammar, not through a per-parser process.

## Links

- [[Idiomatic Facade Over Faithful Core]] - Pure functions are part of the idiomatic facade.
- [[BEAM Native Caches For ATN And DFA]] - Shared caches replace the per-process state a stateful parser would hold.
