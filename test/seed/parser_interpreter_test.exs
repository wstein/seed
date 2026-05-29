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
  @cases [
    %{name: "hello", grammar: "Hello", start_rule: 0},
    %{name: "expr", grammar: "Expr", start_rule: 0}
  ]

  for fixture <- @cases do
    test "#{fixture.name}: parse tree matches the reference parser" do
      %{name: name, grammar: grammar, start_rule: start_rule} = unquote(Macro.escape(fixture))

      parser_grammar = Interp.load!(Path.join(@interp_dir, grammar <> ".interp"))
      tokens = tokenize(grammar, name)
      tree = ParserInterpreter.parse(parser_grammar, tokens, start_rule)

      assert Trees.to_string_tree(tree, parser_grammar) == expected(name)
    end
  end

  defp tokenize(grammar, name) do
    lexer_grammar = Interp.load!(Path.join(@interp_dir, grammar <> "Lexer.interp"))
    input = @parse_dir |> Path.join("#{name}.input") |> File.read!() |> CharStream.new()
    lexer_grammar.atn |> Lexer.new(input) |> TokenStream.from_lexer()
  end

  defp expected(name) do
    @parse_dir |> Path.join("#{name}.tree") |> File.read!() |> String.trim()
  end
end
