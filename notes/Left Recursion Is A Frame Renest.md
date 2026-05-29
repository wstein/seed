---
id: "20260529190000"
aliases: ["push_new_recursion_context", "LR unrolling"]
tags: ["parser", "left-recursion", "mechanism"]
---
Seed builds left-recursive parse trees by renesting context frames on a stack instead of rewriting parent pointers. Each loop iteration pops the expression parsed so far and pushes a new frame holding it as the first child — the immutable equivalent of the reference's `pushNewRecursionContext`.

## What

`Seed.Parser` keeps a stack of `Seed.ParserRuleContext` frames; the top is
the current rule. Entering a rule pushes a frame, a matched token appends
to the top frame, and leaving a rule pops the frame and appends it to its
parent. For a left-recursive rule, `push_new_recursion_context/3` pops the
top frame and pushes a fresh frame with the popped one as its first child.
Repeating this grows a left-leaning tree, so `1 + 2 + 3` becomes
`((1 + 2) + 3)`.

## Why

The reference runtime mutates parent pointers in place to reparent the
accumulated context under a new node. That surgery is impossible with
immutable structs. Modelling the context as a stack of frames and treating
recursion as "pop, wrap, push" reproduces the exact tree without any
mutable references, and reparenting on pop preserves child order because a
rule's frame receives no siblings while a sub-rule is on top of it.

## How

Drive it from the ATN: the parser interpreter calls
`push_new_recursion_context` on the epsilon edge out of a precedence
`star_loop_entry` state, and `unroll_recursion_contexts` when the
left-recursive rule stops. Whether to keep looping is decided by the
adaptive-LL(*) precedence filter, not by this renesting.

## Links

- [[Idiomatic Facade Over Faithful Core]] - The renest is the faithful core expressed in immutable terms.
- [[Serialized ATN Is The Contract]] - The precedence decisions that trigger renesting come from the deserialized ATN.
