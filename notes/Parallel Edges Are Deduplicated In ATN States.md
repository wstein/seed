---
id: "20260529160000"
aliases: ["addTransition dedup", "ATN parallel edge dedup"]
tags: ["atn", "deserialization", "invariant"]
---
When a transition is added to an ATN state, it is dropped if an equivalent one already exists: same target and either the same label or both epsilon. Seed must replicate this deduplication, or rule-stop states accumulate duplicate return edges and the ATN diverges from the reference.

## What

`Seed.ATN.State.add_transition/2` mirrors the reference runtime's
`ATNState.addTransition`: a new edge is skipped when an existing edge has
the same target state and either both carry equal labels (atom, range,
set, not-set) or both are epsilon-style (epsilon, rule, predicate, action,
precedence). This matters most for the epsilon return edges derived for
rule-stop states, where several rule calls can share one follow state.

## Why

Without dedup the transition graph gains phantom edges. This first showed
up as a left-recursive expression grammar producing one extra epsilon on a
rule-stop state: two rule calls shared a follow state, so the naive
"append" produced two identical return edges where the reference keeps one.
The structural histograms then no longer matched the oracle.

## How

Deduplicate inside `add_transition/2`, not at the call sites, so every
path that adds edges (the serialized edges section and the derived
rule-stop returns) gets the same treatment. Validate against the golden
fixtures, whose transition-type histograms count every edge.

## Links

- [[Serialized ATN Is The Contract]] - The deserializer builds these edges from the serialized stream.
- [[Idiomatic Facade Over Faithful Core]] - This dedup is part of the faithful core, validated against the reference.
