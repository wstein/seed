defmodule Seed.ParserInterpreterTest do
  use ExUnit.Case, async: true

  alias Seed.CharStream
  alias Seed.Interp
  alias Seed.Lexer
  alias Seed.ParserInterpreter
  alias Seed.TokenStream
  alias Seed.Trees

  @interp_dir Path.expand("../fixtures/interp", __DIR__)
  @parse_dir Path.expand("../fixtures/parse", __DIR__)

  # Grammars are loaded from their .interp files, so rule names come from the
  # grammar rather than being hardcoded here.
  #
  # Ctx is the canonical context-sensitive grammar: rule `e` is called from
  # two follow-contexts, so its decision can only be resolved with the full
  # rule-invocation stack. ctx_b (`@ 34 abc`) is the discriminating case —
  # picking the lowest conflicting alternative would mispredict and fail.
  @cases [
    %{name: "hello", grammar: "Hello", start_rule: 0},
    %{name: "expr", grammar: "Expr", start_rule: 0},
    %{name: "ctx_a", grammar: "Ctx", start_rule: 0},
    %{name: "ctx_b", grammar: "Ctx", start_rule: 0},
    # A real grammar: lexer fragments, recursion, multi-alt decisions,
    # not-set, and number/string lexing.
    %{name: "json", grammar: "JSON", start_rule: 0},
    # Modes stresses lexer modes (pushMode/popMode), a hidden channel, and a
    # non-greedy rule; Calc stresses right-associative precedence and unary
    # operators. Both are diffed against ANTLR's generated parser.
    %{name: "modes", grammar: "Modes", start_rule: 0},
    %{name: "calc", grammar: "Calc", start_rule: 0},
    # Misc stresses Unicode code points (Greek), string escapes, and a custom
    # named channel that must be filtered from the parser.
    %{name: "misc", grammar: "Misc", start_rule: 0},
    # More stresses a token built across lexer rules with `more` and finalized
    # with `type()`.
    %{name: "more", grammar: "More", start_rule: 0},
    # Erlang: a real-world 698-line grammar with a deep precedence cascade,
    # diffed against the reference's generated parser.
    %{name: "erl", grammar: "Erlang", start_rule: 0}
  ]

  for fixture <- @cases do
    test "#{fixture.name}: parse tree matches the reference parser" do
      %{name: name, grammar: grammar, start_rule: start_rule} = unquote(Macro.escape(fixture))

      parser_grammar = Interp.load!(Path.join(@interp_dir, grammar <> ".interp"))
      tokens = tokenize(grammar, name)

      assert {:ok, tree} = ParserInterpreter.parse(parser_grammar, tokens, start_rule)
      assert Trees.to_string_tree(tree, parser_grammar) == expected(name)
    end
  end

  test "recovers from a missing token by single-token insertion" do
    parser_grammar = Interp.load!(Path.join(@interp_dir, "Hello.interp"))
    lexer_grammar = Interp.load!(Path.join(@interp_dir, "HelloLexer.interp"))
    # "greeting : 'hello' ID EOF" but the input ends after 'hello': the ID is
    # missing. Inserting it lets the trailing EOF still match, so parsing
    # recovers and reports one diagnostic instead of failing.
    {:ok, tokens} =
      lexer_grammar.atn |> Lexer.new(CharStream.new("hello")) |> TokenStream.from_lexer()

    assert {:error, [%Seed.Diagnostic{code: :missing_token, message: message}], _tree} =
             ParserInterpreter.parse(parser_grammar, tokens, 0)

    # The expected token is rendered by its vocabulary name, not its number.
    assert message =~ "ID"
    assert message =~ "<EOF>"
  end

  test "parse/3 returns a diagnostic on an unrecoverable mismatch" do
    parser_grammar = Interp.load!(Path.join(@interp_dir, "Hello.interp"))
    lexer_grammar = Interp.load!(Path.join(@interp_dir, "HelloLexer.interp"))
    # Empty input: 'hello' is neither present nor recoverable (nothing can be
    # deleted, and inserting it leaves EOF unable to continue), so the
    # mismatch is reported as-is.
    {:ok, tokens} =
      lexer_grammar.atn |> Lexer.new(CharStream.new("")) |> TokenStream.from_lexer()

    assert {:error, [%Seed.Diagnostic{code: :token_mismatch, message: message}], _tree} =
             ParserInterpreter.parse(parser_grammar, tokens, 0)

    assert message =~ "hello"
  end

  test "recovers from extraneous tokens, accumulating one diagnostic per error" do
    parser = Interp.load!(Path.join(@interp_dir, "Expr.interp"))
    lexer = Interp.load!(Path.join(@interp_dir, "ExprLexer.interp"))
    # Two stray identifiers before '='; each is recovered by single-token
    # deletion, so parsing continues and both errors are reported.
    {:ok, tokens} =
      lexer.atn |> Lexer.new(CharStream.new("x x = 1 ; y y = 2 ;")) |> TokenStream.from_lexer()

    assert {:error, diagnostics, _tree} = ParserInterpreter.parse(parser, tokens, 0)
    assert Enum.map(diagnostics, & &1.code) == [:extraneous_input, :extraneous_input]
  end

  test "parses starting directly at a left-recursive rule" do
    parser = Interp.load!(Path.join(@interp_dir, "Expr.interp"))
    lexer = Interp.load!(Path.join(@interp_dir, "ExprLexer.interp"))

    {:ok, tokens} =
      lexer.atn |> Lexer.new(CharStream.new("1 + 2 * 3")) |> TokenStream.from_lexer()

    # Rule index 2 is `expr`, a precedence (left-recursive) rule. Starting
    # there directly still applies the precedence so `*` binds tighter.
    assert {:ok, tree} = ParserInterpreter.parse(parser, tokens, 2)

    assert Trees.to_string_tree(tree, parser) ==
             "(expr (expr 1) + (expr (expr 2) * (expr 3)))"
  end

  test "resynchronizes past a no-viable decision to the rule's follow set" do
    parser = Interp.load!(Path.join(@interp_dir, "Expr.interp"))
    lexer = Interp.load!(Path.join(@interp_dir, "ExprLexer.interp"))
    # After "x = 1" the stray "2" leaves the `expr` decision with no viable
    # alternative (it is neither an operator to continue the expression nor a
    # ';' to end the statement). The parser enters panic mode, discards "2" up
    # to expr's follow (';'), and recovers. The second statement ("y y = 2 ;")
    # then parses, removing its own extraneous ID by single-token deletion —
    # proving the walk continued past the resynchronization.
    {:ok, tokens} =
      lexer.atn |> Lexer.new(CharStream.new("x = 1 2 ; y y = 2 ;")) |> TokenStream.from_lexer()

    assert {:error, diagnostics, _tree} = ParserInterpreter.parse(parser, tokens, 0)
    assert Enum.map(diagnostics, & &1.code) == [:no_viable_alternative, :extraneous_input]
  end

  test "attaches error nodes to the recovered tree" do
    hello = Interp.load!(Path.join(@interp_dir, "Hello.interp"))
    hello_lexer = Interp.load!(Path.join(@interp_dir, "HelloLexer.interp"))
    expr = Interp.load!(Path.join(@interp_dir, "Expr.interp"))
    expr_lexer = Interp.load!(Path.join(@interp_dir, "ExprLexer.interp"))

    # An inserted token is a fabricated `<missing …>` error-node leaf.
    {:ok, missing} =
      hello_lexer.atn |> Lexer.new(CharStream.new("hello")) |> TokenStream.from_lexer()

    assert {:error, _diagnostics, tree} = ParserInterpreter.parse(hello, missing, 0)
    assert Trees.to_string_tree(tree, hello) == "(greeting hello <missing ID> <EOF>)"

    # A token discarded during resynchronization is kept as an error node
    # (here the stray "2" inside the expression it interrupted).
    {:ok, discarded} =
      expr_lexer.atn |> Lexer.new(CharStream.new("x = 1 2 ;")) |> TokenStream.from_lexer()

    assert {:error, _, resynced} = ParserInterpreter.parse(expr, discarded, 0)
    assert Trees.to_string_tree(resynced, expr) == "(prog (stat x = (expr 1 2) ;) <EOF>)"
  end

  test "a semantic predicate disambiguates otherwise-ambiguous alternatives" do
    parser = Interp.load!(Path.join(@interp_dir, "Pred.interp"))
    lexer = Interp.load!(Path.join(@interp_dir, "PredLexer.interp"))
    # `item : {tagged}? foo | bar ;` — `foo` and `bar` both match "x ;", so
    # only the predicate on the first alternative chooses between them.
    {:ok, tokens} = lexer.atn |> Lexer.new(CharStream.new("x ;")) |> TokenStream.from_lexer()

    # Default: predicates are satisfied, so the first alternative wins.
    assert {:ok, default_tree} = ParserInterpreter.parse(parser, tokens, 0)
    assert Trees.to_string_tree(default_tree, parser) == "(prog (item (foo x ;)) <EOF>)"

    # Predicate true keeps `foo`; predicate false selects `bar`.
    assert {:ok, foo} =
             ParserInterpreter.parse(parser, tokens, 0, sempred: fn _, _, _ -> true end)

    assert Trees.to_string_tree(foo, parser) == "(prog (item (foo x ;)) <EOF>)"

    assert {:ok, bar} =
             ParserInterpreter.parse(parser, tokens, 0, sempred: fn _, _, _ -> false end)

    assert Trees.to_string_tree(bar, parser) == "(prog (item (bar x ;)) <EOF>)"
  end

  test "the predicate callback receives the rule and predicate index" do
    parser = Interp.load!(Path.join(@interp_dir, "Pred.interp"))
    lexer = Interp.load!(Path.join(@interp_dir, "PredLexer.interp"))
    {:ok, tokens} = lexer.atn |> Lexer.new(CharStream.new("x ;")) |> TokenStream.from_lexer()

    me = self()

    ParserInterpreter.parse(parser, tokens, 0,
      sempred: fn rule_index, pred_index, _ctx ->
        send(me, {:sempred, rule_index, pred_index})
        true
      end
    )

    # The predicate lives in rule `item` (index 1) as that rule's predicate 0.
    assert_received {:sempred, 1, 0}
  end

  test "the parser skips tokens routed to a non-default channel" do
    parser = Interp.load!(Path.join(@interp_dir, "Hidden.interp"))
    lexer = Interp.load!(Path.join(@interp_dir, "HiddenLexer.interp"))
    # `prog : ID+ EOF` with COMMENT on the hidden channel: the comment is in
    # the token stream but must not reach the parser.
    {:ok, tokens} =
      lexer.atn |> Lexer.new(CharStream.new("a # c\nb")) |> TokenStream.from_lexer()

    assert {:ok, tree} = ParserInterpreter.parse(parser, tokens, 0)
    assert Trees.to_string_tree(tree, parser) == "(prog a b <EOF>)"
  end

  test "bail mode aborts at the first error without recovering" do
    parser = Interp.load!(Path.join(@interp_dir, "Expr.interp"))
    lexer = Interp.load!(Path.join(@interp_dir, "ExprLexer.interp"))

    {:ok, tokens} =
      lexer.atn |> Lexer.new(CharStream.new("x x = 1 ; y y = 2 ;")) |> TokenStream.from_lexer()

    # Recovery reports a diagnostic per error and still returns a tree.
    assert {:error, recovered, _tree} = ParserInterpreter.parse(parser, tokens, 0)
    assert length(recovered) == 2

    # Bail mode stops at the first error: one diagnostic, no tree.
    assert {:error, [%Seed.Diagnostic{}]} = ParserInterpreter.parse(parser, tokens, 0, bail: true)
  end

  test "parser predictions populate the persisted DFA (interned states, edges, resolutions)" do
    parser_grammar = Interp.load!(Path.join(@interp_dir, "Expr.interp"))
    tokens = tokenize("Expr", "expr")

    assert {:ok, _tree} = ParserInterpreter.parse(parser_grammar, tokens, 0)

    tags = :seed_dfa_cache |> :ets.tab2list() |> Enum.map(&elem(&1, 0)) |> Enum.map(&kind/1)
    # The DFA was built: interned states, transition edges, and cached
    # per-state resolutions all appear.
    assert :dfa_configs in tags
    assert :dfa_edge in tags
    assert :dfa_pred in tags
  end

  # The discriminating element of a DFA cache key, e.g. `{cache_key, :dfa_edge,
  # …}` -> `:dfa_edge`.
  defp kind(key) when is_tuple(key) and tuple_size(key) > 1, do: elem(key, 1)
  defp kind(_key), do: nil

  defp tokenize(grammar, name) do
    lexer_grammar = Interp.load!(Path.join(@interp_dir, grammar <> "Lexer.interp"))
    input = @parse_dir |> Path.join("#{name}.input") |> File.read!() |> CharStream.new()
    {:ok, tokens} = lexer_grammar.atn |> Lexer.new(input) |> TokenStream.from_lexer()
    tokens
  end

  defp expected(name) do
    @parse_dir |> Path.join("#{name}.tree") |> File.read!() |> String.trim()
  end
end
