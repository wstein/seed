# Tree Pattern Matching Needs A Bypass ATN

Roadmap E's tree pattern matcher (`Seed.TreePatternMatcher`, after ANTLR's
`ParseTreePatternMatcher`) lets you ask "does this subtree look like
`<expr> + <expr>`?" and bind the tagged pieces. A pattern string is *compiled*
by parsing it — with tag placeholders — using the **same grammar** that
produced the subject tree, so the pattern tree has the same shape and matching
is a structural walk.

The crux is the `<rule>` tag (e.g. `<expr>`): it stands for an entire rule
subtree, but a rule cannot normally be matched by a single token. ANTLR solves
this with a **bypass-alternatives ATN** (`ATNDeserializer.generateRuleBypass`
behind `getATNWithBypassAlts()`): each rule `r` gains an imaginary token type
(`maxTokenType + ruleIndex + 1`) and an extra alternative that matches exactly
that one token, wrapped in a block. Parsing `<expr>` then yields an
`exprContext` whose only child is the tag terminal — which `matchImpl` detects
(`getRuleTagToken`) and treats as "matches any expr subtree".

## Build order (each commit `make verify`-green)

1. **`Seed.ATN.BypassAlts.add/1`** — faithful port of the transform: per rule,
   add `bypassStart` (block-start decision), `bypassStop` (block-end),
   `matchState` (atom edge on the imaginary token); redirect transitions
   targeting the rule's end state to `bypassStop`; move the rule-start's
   transitions onto `bypassStart`; relink. Left-recursive rules (`is_precedence_rule`)
   wrap to the `StarLoopEntry` instead of the rule stop, excluding the loop-back
   edge. Validated structurally + by parsing a hand-built imaginary-token
   stream through the interpreter.
2. **Pattern tokenizer + tags** — `split/tokenize` (chunks, escapes, `label:tag`),
   `Seed.Token` gains a `:tag` marker (`{:token|:rule, name, label}`), so tag
   tokens stay plain `%Token{}` (the interpreter matches them by type) yet the
   matcher can recover the tag.
3. **`Seed.TreePattern.compile` + `Seed.TreePatternMatcher`** — compile parses
   the tag token stream with the bypass ATN (bail strategy, full-consume check);
   `matches?/match` is the `matchImpl` structural walk binding labels; result is
   a `Seed.ParseTreeMatch`.
4. **Oracle** — `scripts/PatternDump.java` over ANTLR's `ParseTreePatternMatcher`
   + fixtures; conformance test asserts byte-identical match/bindings.

See [[Prediction Uses Full Rule Invocation Context]] and the feature-parity
roadmap (E).
