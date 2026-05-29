defmodule Seed.Trees do
  @moduledoc """
  Renders a parse tree as a LISP-style string, matching ANTLR's
  `Trees.toStringTree`.

  A terminal renders as its token text; a rule context renders as its rule
  name when it has no children, or `(rule child child ...)` otherwise.
  Whitespace in node text is escaped (`\\n`, `\\r`, `\\t`) as the reference
  does, so the output can be compared against the parse-tree fixtures.
  """

  alias Seed.Grammar
  alias Seed.ParserRuleContext
  alias Seed.TerminalNode

  @doc """
  Returns the LISP-style string for `tree`.

  Rule names come from a `Seed.Grammar` or an explicit rule-name list.

      iex> tree = Seed.ParserRuleContext.new(0) |> Seed.ParserRuleContext.add_child(
      ...>   Seed.TerminalNode.new(Seed.Token.new(1, text: "hi")))
      iex> Seed.Trees.to_string_tree(tree, ["greeting"])
      "(greeting hi)"
  """
  @spec to_string_tree(ParserRuleContext.t() | TerminalNode.t(), Grammar.t() | [String.t()]) ::
          String.t()
  def to_string_tree(node, %Grammar{rule_names: rule_names}) do
    to_string_tree(node, rule_names)
  end

  def to_string_tree(%TerminalNode{symbol: token}, _rule_names) do
    escape_whitespace(node_text(token))
  end

  def to_string_tree(%ParserRuleContext{rule_index: rule_index, children: []}, rule_names) do
    rule_name(rule_names, rule_index)
  end

  def to_string_tree(%ParserRuleContext{rule_index: rule_index, children: children}, rule_names) do
    rendered = Enum.map_join(children, " ", &to_string_tree(&1, rule_names))
    "(" <> rule_name(rule_names, rule_index) <> " " <> rendered <> ")"
  end

  defp node_text(%{text: nil}), do: "<EOF>"
  defp node_text(%{text: text}), do: text

  defp rule_name(rule_names, rule_index),
    do: Enum.at(rule_names, rule_index, Integer.to_string(rule_index))

  defp escape_whitespace(text) do
    text
    |> String.replace("\t", "\\t")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
  end
end
