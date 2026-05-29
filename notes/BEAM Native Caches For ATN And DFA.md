---
id: "20260529100300"
aliases: ["persistent_term for ATN", "ETS DFA cache"]
tags: ["architecture", "performance", "security"]
---
Seed stores the static, immutable ATN in `:persistent_term` and the growing adaptive DFA cache in bounded `ETS`. This preserves cross-parse memoization on the BEAM without a process bottleneck and without unbounded memory growth.

## What

Two distinct storages with opposite access patterns. The deserialized ATN is large, immutable, and read constantly: it goes in `:persistent_term` for zero-copy concurrent reads. The DFA cache is mutated as the parser observes new lookahead: it goes in an `ETS` table, keyed by grammar, with a size bound and eviction.

## Why

Adaptive LL(*) performance depends on memoizing decisions across parses, which a pure-functional cache threaded through calls would lose, and which a single owning process would serialize. ETS gives concurrent read/write shared state without a mailbox. The cache bound is a deliberate denial-of-service mitigation: an unbounded cache fed adversarial input is a memory-exhaustion vector. `:persistent_term` is reserved for the static ATN only, because writing to it triggers a global garbage collection and must never happen per parse.

## How

Load and store each grammar's ATN in `:persistent_term` once at setup. Create the ETS DFA cache per grammar, enforce its bound on insert, and evict under pressure. Never place per-parse data in `:persistent_term`.

## Links

- [[Parsers Are Pure Functions]] - Shared caches replace per-process parser state.
- [[Serialized ATN Is The Contract]] - The static ATN placed in persistent_term is the deserialized contract artifact.
