---
id: "20260529173000"
aliases: ["ETS DFA cache", "Seed.DFACache"]
tags: ["lexer", "atn", "performance", "cache"]
---
The ATN simulators memoize their decisions in a single supervised, bounded ETS table owned by `Seed.DFACache`, keyed by the grammar's `cache_key`. It is a pure optimization: a miss recomputes and the result is identical, so the simulators behave the same whether or not the cache process is running.

## What

`Seed.DFACache` is a GenServer (started by `Seed.Application`) that owns a
`:public`, `:named_table` ETS table. Callers use `memoize/2` to read and
write it directly, with no message round-trip. The lexer caches the two
expensive results: each mode's start-state closure and each edge's reach.

## Why

This implements the ADR-005 decision to hold the adaptive cache in ETS for
cross-parse reuse. Three design points make it safe: a *supervised owner*
so the table outlives any one parse; a *per-grammar key* (`cache_key`, a
hash of the serialized ATN stamped at deserialization) so different
grammars never collide; and a *bound* (the table is cleared wholesale on
overflow) so adversarial input cannot grow it without limit. Because it is
pure memoization, it never changes the tokens produced — only the work done.

## How

Look decisions up through `Seed.DFACache.memoize(key, fn -> compute end)`;
include `atn.cache_key` in every key. The accessors degrade to plain
computation when the table is absent, so code paths work without the OTP
application started (for example in isolated tests).

## Links

- [[BEAM Native Caches For ATN And DFA]] - The ADR-005 rationale this realizes.
- [[Parsers Are Pure Functions]] - The cache is shared state behind an otherwise pure interface.
- [[Serialized ATN Is The Contract]] - cache_key is a hash of that serialized contract.
