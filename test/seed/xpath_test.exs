defmodule Seed.XPathTest do
  use ExUnit.Case, async: true

  alias Seed.CharStream
  alias Seed.Interp
  alias Seed.Lexer
  alias Seed.ParserInterpreter
  alias Seed.TokenStream
  alias Seed.Trees
  alias Seed.XPath

  @interp_dir Path.expand("../fixtures/interp", __DIR__)

  setup do
    parser = Interp.load!(Path.join(@interp_dir, "Expr.interp"))
    lexer = Interp.load!(Path.join(@interp_dir, "ExprLexer.interp"))

    {:ok, tokens} =
      lexer.atn |> Lexer.new(CharStream.new("x = 1 + 2 ;")) |> TokenStream.from_lexer()

    {:ok, tree} = ParserInterpreter.parse(parser, tokens, 0)
    %{tree: tree, grammar: parser}
  end

  defp rendered(nodes, grammar), do: Enum.map(nodes, &Trees.to_string_tree(&1, grammar))

  test "// matches rule nodes at any depth", %{tree: tree, grammar: grammar} do
    assert XPath.find(tree, "//expr", grammar) |> rendered(grammar) ==
             ["(expr (expr 1) + (expr 2))", "(expr 1)", "(expr 2)"]
  end

  test "// matches terminals by token name", %{tree: tree, grammar: grammar} do
    assert XPath.find(tree, "//ID", grammar) |> rendered(grammar) == ["x"]
    assert XPath.find(tree, "//INT", grammar) |> rendered(grammar) == ["1", "2"]
  end

  test "// matches a terminal by its literal", %{tree: tree, grammar: grammar} do
    assert XPath.find(tree, "//'+'", grammar) |> rendered(grammar) == ["+"]
  end

  test "/ matches direct children, anchored at the root", %{tree: tree, grammar: grammar} do
    assert XPath.find(tree, "/prog/stat", grammar) |> rendered(grammar) ==
             ["(stat x = (expr (expr 1) + (expr 2)) ;)"]
  end

  test "* matches any child", %{tree: tree, grammar: grammar} do
    assert XPath.find(tree, "//stat/*", grammar) |> rendered(grammar) ==
             ["x", "=", "(expr (expr 1) + (expr 2))", ";"]
  end

  test "! inverts a step", %{tree: tree, grammar: grammar} do
    assert XPath.find(tree, "/prog/!stat", grammar) |> rendered(grammar) == ["<EOF>"]
  end

  test "an unknown name raises", %{tree: tree, grammar: grammar} do
    assert_raise ArgumentError, ~r/no rule named/, fn -> XPath.find(tree, "//nope", grammar) end
    assert_raise ArgumentError, ~r/no token named/, fn -> XPath.find(tree, "//NOPE", grammar) end
  end

  test "a path must start with a separator", %{tree: tree, grammar: grammar} do
    assert_raise ArgumentError, ~r{start with}, fn -> XPath.find(tree, "expr", grammar) end
  end
end
