# SLL Readiness — Gate Findings And Design Constraints

> **Outcome: attempt 3 landed and is the implementation in `Seed.ParserATNSimulator`.**
> Two-stage SLL→LL, byte-for-byte correct (`ctx_b` + all vendored grammars),
> and ~2× faster on `parse_throughput.exs` and the deep `sql_big` case with no
> regression on flat JSON. The decisive fix was carrying rule-stop configs
> forward in SLL reach (see "exact correctness mechanism" below) and falling
> back to LL only on a genuine conflict, never on the dip flag. This note is
> retained as the design record.

Roadmap D (SLL-first prediction) was attempted and reverted twice — once for
correctness (`ctx_b` misprediction), once for a 12.8× super-linear performance
regression — before the third attempt succeeded. This note records the
"prove-the-win" gate measurement and the design constraints that made the
difference. Governed by the ADR-008 benchmark gate.

## Gate measurement (does SLL have room to win in Seed's architecture?)

Instrumented the current full-context predictor (`adaptive_predict`) to count,
per parse: total predictions, distinct *decisions*, and distinct full-context
start states `{decision, outer_context}`.

| case        | preds | decisions | fullctx starts | starts/dec | preds/start |
|-------------|------:|----------:|---------------:|-----------:|------------:|
| json_flat   |   402 |         3 |              5 |    1.7     |   80.4      |
| json_nested |  1442 |         5 |             61 |   12.2     |   23.6      |
| sql_big     |  5463 |        39 |            186 |    4.8     |   29.4      |
| sql_fixture |   192 |        54 |            175 |    3.2     |    1.1      |
| erl         |    68 |        32 |             65 |    2.0     |    1.0      |

- **`starts/dec`** — full-context computes 1.7–12.2× more start-state closures
  than SLL would (SLL keys the start state by `decision` alone; full context by
  `{decision, outer_context}`). The redundant closures are the prize.
- **`preds/start`** — full-context cache reuse. On the highly repetitive
  `json_flat` it is 80× (the cache already wins → **SLL must not regress this**,
  the lesson of attempt 2). On real varied code (`erl` 1.0, `sql_fixture` 1.1)
  it is ≈1 — every prediction is a *fresh* full-context closure the cache never
  reuses, which is exactly where SLL's shared empty-context DFA pays off.

**Verdict: the opportunity is real but conditional.** SLL can cut redundant
start-state (and reach) closures 2–12× on varied/deep grammars, but adds pure
overhead on a highly cacheable grammar. A net win requires the SLL happy path
to be *strictly cheaper than the current cached full-context path*.

## Why attempt 2 lost (and the constraints that follow)

Attempt 2 was byte-for-byte correct but 12.8× slower on `json_flat`
(`parse_throughput.exs`). Root cause: ~43% of decisions fell back (SLL pass
*then* a full LL pass = double transient garbage), and per-step GC against the
growing live tree made it super-linear. Two design errors to avoid:

1. **Fall back on CONFLICT, not on DIP.** A loop-exit "dips into outer context"
   on essentially every iteration; falling back to LL on every dip is what
   produced the 43% rate. ANTLR returns a *unique* SLL alternative even when
   dips are present (SLL soundness) and only retries LL on an SLL *conflict*.
   The true context-sensitive-decision rate (e.g. `ctx_b`'s rule `e`) is small,
   so a conflict-gated fallback should be a few percent, not 43%.
2. **The SLL happy path must skip `from_rule_context`.** Today every prediction
   rebuilds the outer-context chain from the frames (O(depth)) just to key the
   cache — wasted on `json_flat` where only 5 distinct contexts exist across 402
   predictions. SLL keys by `decision` alone, so the happy path skips the
   context build *and* uses a smaller cache key. This is how SLL can be cheaper
   than full context even when full context's cache reuse is high.
3. **No double work on fallback.** When a conflict does force LL, reuse the
   SLL closure rather than recomputing from scratch.

## The exact correctness mechanism (what attempts 1 and 2 each got wrong)

Worked out against `ctx_b` (rule `e : INT | ;` called from `a : e ID` and
`b : e INT ID`; input `@ 34 abc` must give `(s @ (b e 34 abc))`, i.e. `e`
matches **empty** in context `b`). The whole game is how a config that fell off
`e` into the outer context (the empty alternative, sitting at the rule-stop)
participates in the SLL decision:

- **Loop-exit case (e.g. `Expr` `expr` loop, extraneous `4`).** The continue
  alternative needs an operator and dies on `4`; the exit alternative dipped to
  the rule-stop. Reach on `4` keeps only the dipped rule-stop config → **unique
  alt = exit** → SLL exits cleanly, *no LL*. Attempt 2 wrongly fell back to LL
  here (it triggered on the dip flag), producing ~43 % fallback and the GC
  blow-up.
- **`ctx_b` case.** Alt 1 (`INT`) *can* consume `34`; alt 2 (empty) dipped to
  the rule-stop. The fix is that in SLL the **rule-stop config must be carried
  forward into the reach set** (ANTLR's `skippedStopStates`, re-added when
  `!fullCtx`), instead of being dropped. Then reach = {alt 1 advanced, alt 2 at
  rule-stop} → **not unique → conflict → defer to LL**, which resolves it with
  the real context. Attempt 1 dropped the dipped config, got a spurious unique
  alt 1, and mispredicted.

**The single rule that satisfies both:** in SLL mode, `compute_reach_set` must
*carry rule-stop configs forward* (don't drop them in `reachable_from`). Then
ordinary unique-alt / `PredictionMode.conflict?` detection does the right
thing — a lone surviving rule-stop alt is a clean exit (no LL); a rule-stop alt
coexisting with a consuming alt is a genuine SLL conflict (defer to LL). Fall
back to LL **only on that conflict**, never on the dip flag alone. This is the
crux change beyond the (already-drafted, behaviour-preserving) `full_ctx?`
threading + `fell_off/2`.

## De-risking plan (measure before replacing)

1. **Shadow SLL.** Implement SLL prediction and run it *alongside* the real
   full-context predictor: assert the answers agree (correctness) and measure
   the true SLL-conflict/fallback rate (perf viability). Flip SLL to primary
   only if conflicts are rare and answers always agree.
2. **Benchmark gate.** `json_flat` is the must-not-regress baseline (parse
   ≈1.26 s at N=5000); `json_nested` / `sql_big` are the must-improve cases.
   Land nothing without a before/after on both.

See [[seed-sll-fast-path-reverted-twice]] (memory) and ADR-008.
