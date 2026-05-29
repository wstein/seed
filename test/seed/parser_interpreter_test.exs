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
    %{name: "json", grammar: "JSON", start_rule: 0}
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

    assert {:error, [%Seed.Diagnostic{code: :missing_token, message: message}]} =
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

    assert {:error, [%Seed.Diagnostic{code: :token_mismatch, message: message}]} =
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

    assert {:error, diagnostics} = ParserInterpreter.parse(parser, tokens, 0)
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

    assert {:error, diagnostics} = ParserInterpreter.parse(parser, tokens, 0)
    assert Enum.map(diagnostics, & &1.code) == [:no_viable_alternative, :extraneous_input]
  end

  test "parser predictions are memoized in the DFA cache" do
    parser_grammar = Interp.load!(Path.join(@interp_dir, "Expr.interp"))
    tokens = tokenize("Expr", "expr")

    assert {:ok, _tree} = ParserInterpreter.parse(parser_grammar, tokens, 0)

    keys = :seed_dfa_cache |> :ets.tab2list() |> Enum.map(&elem(&1, 0))
    assert Enum.any?(keys, &(tuple_size(&1) > 1 and elem(&1, 1) in [:parser_start, :parser_edge]))
  end

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
