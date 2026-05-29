defmodule Seed.GeneratedTest do
  use ExUnit.Case, async: true

  alias Seed.Trees

  defmodule Expr do
    use Seed.Generated,
      parser: "test/fixtures/interp/Expr.interp",
      lexer: "test/fixtures/interp/ExprLexer.interp"
  end

  test "bakes the grammar metadata into the module" do
    assert Expr.rule_names() == ["prog", "stat", "expr"]
    assert %Seed.Grammar{} = Expr.parser_grammar()
    assert %Seed.Grammar{} = Expr.lexer_grammar()
    assert Seed.Vocabulary.display_name(Expr.vocabulary(), 1) == "'='"
  end

  test "parse/1 parses from the start rule" do
    assert {:ok, tree} = Expr.parse("x = 1 + 2 ;")
    assert Trees.to_string_tree(tree, Expr.parser_grammar()) =~ "prog"
  end

  test "parse_<rule>/1 parses from a named rule, including a left-recursive one" do
    assert {:ok, tree} = Expr.parse_stat("x = 1 + 2 ;")
    assert Trees.to_string_tree(tree, Expr.parser_grammar()) =~ "stat"

    assert {:ok, expr} = Expr.parse_expr("1 + 2 * 3")
    assert Trees.to_string_tree(expr, Expr.parser_grammar()) =~ "expr"
  end

  test "parse/2 resolves a rule by name (atom or string) or index" do
    assert {:ok, _} = Expr.parse("1 + 2", :expr)
    assert {:ok, _} = Expr.parse("1 + 2", "expr")
    assert {:ok, _} = Expr.parse("1 + 2", 2)
  end

  test "tokenize/1 lexes with the baked lexer" do
    assert {:ok, tokens} = Expr.tokenize("x = 1 ;")
    assert Enum.any?(tokens, &(&1.type > 0))
  end

  test "parse/2 raises on an unknown rule name" do
    assert_raise ArgumentError, ~r/unknown rule/, fn -> Expr.parse("x", :nope) end
  end

  test "error recovery flows through the generated entry points" do
    assert {:error, [%Seed.Diagnostic{} | _], _tree} = Expr.parse("x x = 1 ;")
  end
end
