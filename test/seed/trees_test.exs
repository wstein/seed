defmodule Seed.TreesTest do
  use ExUnit.Case, async: true
  doctest Seed.Trees

  alias Seed.ParserRuleContext, as: Rule
  alias Seed.TerminalNode
  alias Seed.Token
  alias Seed.Trees

  defp terminal(type, text), do: TerminalNode.new(Token.new(type, text: text))

  test "renders a flat rule as (rule child child ...) matching the hello fixture" do
    tree =
      Rule.new(0)
      |> Rule.add_child(terminal(1, "hello"))
      |> Rule.add_child(terminal(2, "world"))
      |> Rule.add_child(TerminalNode.new(Token.eof_token()))

    assert Trees.to_string_tree(tree, ["greeting"]) == "(greeting hello world <EOF>)"
  end

  test "renders nested rules, matching expression precedence shape" do
    # (expr (expr 1) + (expr 2))
    one = Rule.new(2) |> Rule.add_child(terminal(10, "1"))
    two = Rule.new(2) |> Rule.add_child(terminal(10, "2"))

    expr =
      Rule.new(2)
      |> Rule.add_child(one)
      |> Rule.add_child(terminal(5, "+"))
      |> Rule.add_child(two)

    assert Trees.to_string_tree(expr, ~w(prog stat expr)) == "(expr (expr 1) + (expr 2))"
  end

  test "renders a childless rule as just its name" do
    assert Trees.to_string_tree(Rule.new(1), ~w(prog stat expr)) == "stat"
  end

  test "escapes whitespace in terminal text" do
    assert Trees.to_string_tree(terminal(3, "a\nb"), ["r"]) == "a\\nb"
  end
end
