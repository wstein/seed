---
id: "20260529173000"
aliases: ["No lexer DFA cache yet", "ATN-only lexer"]
tags: ["lexer", "atn", "performance", "tradeoff"]
---
Seed's lexer simulator runs the ATN directly and does not build the adaptive DFA cache. The DFA only memoizes decisions the ATN already makes, so omitting it produces identical tokens — it just recomputes each step. This keeps the first lexer port small and correct on the immutable BEAM.

## What

The reference `LexerATNSimulator` caches computed edges in a per-mode DFA
to avoid re-running the ATN closure on repeated inputs. Seed's
`Seed.LexerATNSimulator` implements the same closure/reach/longest-match
algorithm but skips the cache: every symbol is resolved by ATN simulation.

## Why

The DFA cache is the one part of the simulator that is fundamentally
mutable and shared, which is awkward on the BEAM and not required for
correctness. Leaving it out lets the lexer be a pure function validated
decision-for-decision against the reference, and defers the mutable-cache
question to a deliberate, BEAM-native design (ETS) rather than a hurried
transliteration. The cost is recomputation, i.e. throughput, not wrong
tokens.

## How

Treat the cache as a later, behavior-preserving optimization: an ETS table
keyed per grammar and mode, populated as decisions are computed, consulted
before falling back to the ATN. Until then, rely on the simulator being
correct on its own. See the ETS/persistent_term cache decision.

## Links

- [[BEAM Native Caches For ATN And DFA]] - Where the deferred DFA cache will live (ETS).
- [[Idiomatic Facade Over Faithful Core]] - The simulator is faithful core; the omission preserves behavior.
- [[Parsers Are Pure Functions]] - Omitting the mutable cache keeps the lexer a pure function for now.
