# Grammar `.interp` fixtures

`.interp` files emitted by the ANTLR4 tool (version 4.13.2) for the
grammars in `../atn/grammars/`. Each recognizer contributes one file:

- `<Grammar>.interp` — the parser: token literal/symbolic names, rule
  names, and the serialized ATN.
- `<Grammar>Lexer.interp` — the lexer: the same token names plus channel
  names, mode names, and the lexer ATN.

`Seed.Interp.load!/1` reads these into a `Seed.Grammar`, so a grammar can
be lexed and parsed at run time with no code generation. The tests load
grammars from these fixtures (rule names included), which is why the
end-to-end parser tests no longer hardcode rule-name lists.

Regenerate with:

```sh
scripts/gen_interp_fixtures.sh
```

The script is deterministic: with the same ANTLR version it reproduces
byte-identical fixtures, which is what the CI drift gate checks.
