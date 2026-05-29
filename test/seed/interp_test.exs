defmodule Seed.InterpTest do
  use ExUnit.Case, async: true

  alias Seed.Grammar
  alias Seed.Interp
  alias Seed.Vocabulary

  @dir Path.expand("../fixtures/interp", __DIR__)

  defp load(name), do: Interp.load!(Path.join(@dir, name <> ".interp"))

  test "loads a parser grammar's rule names, vocabulary, and ATN" do
    grammar = load("Expr")

    assert grammar.atn.grammar_type == :parser
    assert grammar.rule_names == ~w(prog stat expr)
    assert Vocabulary.display_name(grammar.vocabulary, 1) == "'='"
    assert Vocabulary.display_name(grammar.vocabulary, 9) == "ID"
    assert Grammar.rule_name(grammar, 2) == "expr"
    assert grammar.atn.max_token_type == 11
  end

  test "loads a lexer grammar's channel and mode names" do
    grammar = load("ExprLexer")

    assert grammar.atn.grammar_type == :lexer
    assert grammar.channel_names == ["DEFAULT_TOKEN_CHANNEL", "HIDDEN"]
    assert grammar.mode_names == ["DEFAULT_MODE"]
    # Implicit literal-token rules plus the named lexer rules.
    assert "ID" in grammar.rule_names
  end

  test "parse!/1 reads the section format and maps null to nil" do
    grammar =
      Interp.parse!("""
      token literal names:
      null
      'hello'

      token symbolic names:
      null
      HI

      rule names:
      greeting

      atn:
      #{File.read!(Path.join(@dir, "Hello.interp")) |> atn_line()}
      """)

    assert grammar.rule_names == ["greeting"]
    assert Vocabulary.literal_name(grammar.vocabulary, 1) == "'hello'"
    assert Vocabulary.symbolic_name(grammar.vocabulary, 1) == "HI"
    assert grammar.atn.grammar_type == :parser
  end

  test "raises on a malformed file" do
    assert_raise Interp.Error, fn -> Interp.parse!("rule names:\ngreeting\n") end
  end

  # Extracts the bracketed ATN line from a real .interp fixture.
  defp atn_line(content) do
    content
    |> String.split("\n")
    |> Enum.find(&String.starts_with?(&1, "["))
  end
end
