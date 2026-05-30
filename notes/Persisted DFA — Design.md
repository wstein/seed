# Persisted DFA — Design

The next prediction-performance lever (chosen after SLL landed). Today
`Seed.DFACache` memoizes reach config-sets keyed by the *config-set itself*,
and `resolve` recomputes `unique_alt`/`conflict?` on every visit. Profiling a
warm `sql_big` parse (611 ms, **2021 GCs**, 15.3M reductions) shows that even
fully cached, each prediction step allocates — it builds a config-list cache
key and re-resolves. A real DFA replaces that warm path with integer
edge-walks.

## Model (after ANTLR's `DFA` / `DFAState`)

A *DFA state* is an interned config set with an integer id. Per grammar
(`cache_key`), stored in the existing `Seed.DFACache` ETS table:

- `intern(cache_key, configs) -> id` — canonicalize a config set to a stable
  integer id (allocate on first sight). Reverse map `id -> configs` for the
  cold path. Races only cost sharing, never correctness (the cache is a pure
  optimization).
- `edge(cache_key, id, token, full_ctx?) -> target_id | nil` and
  `put_edge/5` — the DFA transition table, integer-keyed.
- `prediction(cache_key, id, full_ctx?) -> {:accept, alt} | :conflict |
  :continue` — the resolution, computed once per state and cached.

## Hot loop (after rewiring)

Thread `{id, configs}` instead of a bare config set:

```
decide({id, configs}, input, full_ctx?):
  case prediction(id, full_ctx?):           # cached resolution
    {:accept, alt} -> alt                    # O(1), no resolve
    :conflict      -> on_conflict(...)
    :continue ->
      t = LA(1)
      target_id =
        edge(id, t, full_ctx?) ||            # O(1) integer lookup on a warm edge
          (reach = compute_reach_set(configs, t); rid = intern(reach);
           put_edge(id, t, full_ctx?, rid); rid)
      decide({target_id, configs_of(target_id)}, consume(input), full_ctx?)
```

The win: a warm step is an integer `prediction`/`edge` lookup — no config-list
key building, no list hashing, no re-resolution → far less garbage. Interning
still hashes a config set, but only when a *new* state is created (the cold
path), not on every step.

## Build order (each `make verify`-green, ctx_b + vendored byte-for-byte, benchmark-gated)

1. **`Seed.DFA` data layer** — `intern` / `configs` / `edge` / `put_edge`
   over the DFACache ETS table, with unit tests. Additive, no loop change.
2. **Cache the resolution** — add `prediction/3` (accept/conflict/continue)
   per state; still keyed by config-set first to de-risk.
3. **Rewire `decide`** to thread `{id, configs}` and walk edges by id. The
   risky step — validate against ctx_b, all vendored grammars, the recovery
   oracle, and `bench/prediction_cost.exs` (must beat the current warm path,
   must not regress json_flat).
4. **Revisit the documented scan divergences** (`hasStateAssociatedWithOneAlt`,
   `resolvesToJustOneViableAlt`) — with cheap cached rescans they may now pay
   off rather than blow up. Each strictly benchmark-gated.

Bound: the DFA shares `Seed.DFACache`'s wholesale-clear-on-overflow guard.
SLL and LL keep separate states/edges via the `full_ctx?` key bit, as today.
See [[seed-sll-fast-path-reverted-twice]] and `notes/SLL Readiness`.
