---
id: "20260529220000"
aliases: ["full-context prediction", "no SLL stage", "context-sensitive parsing"]
tags: ["parser", "prediction", "correctness"]
---
Seed's parser prediction always uses the real rule-invocation stack, so context-sensitive decisions are resolved correctly without a separate SLL-then-LL fallback. The reference's SLL-first stage is a performance optimization Seed forgoes, not a correctness feature it lacks.

## What

`Seed.ParserATNSimulator` builds each decision's start state from the
parser's actual call stack (`from_rule_context`) and merges configuration
contexts in full-LL mode (root not treated as wildcard). A decision whose
viable alternative depends on who called the rule therefore resolves to the
right alternative. An irreducible conflict (same state and context, different
alternatives) picks the lowest alternative, matching ANTLR's default
ambiguity resolution.

## Why

ANTLR runs SLL first (ignoring call context, for DFA cacheability across
call sites) and falls back to full-context LL only on conflict. That
two-stage design exists for speed; correctness comes from the LL stage.
Seed goes straight to full context, so it needs no fallback and never
mispredicts a context-sensitive grammar — verified on the canonical
`CtxSensitiveDFA` grammar in both call contexts (`test/fixtures/parse/ctx_a`,
`ctx_b`). The cost is forgoing SLL's cross-context DFA sharing, which is a
future performance optimization, not a correctness gap.

## How

Keep prediction context-faithful: never substitute an empty/wildcard outer
context for the real stack. When adding the SLL fast path later, treat it
strictly as an optimization with a full-context fallback, and keep the
full-context path as the correctness oracle.

## Links

- [[Left Recursion Is A Frame Renest]] - Precedence handling layered on the same prediction.
- [[DFA Cache Is Supervised ETS Keyed Per Grammar]] - Memoizes these full-context decisions.
- [[Idiomatic Facade Over Faithful Core]] - Full-context prediction is the faithful core.
