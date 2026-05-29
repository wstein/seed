defmodule Seed.ParserInterpreterTest do
  use ExUnit.Case, async: true

  alias Seed.ATNDeserializer
  alias Seed.CharStream
  alias Seed.Lexer
  alias Seed.ParserInterpreter
  alias Seed.TokenStream
  alias Seed.Trees

  @atn_dir Path.expand("../fixtures/atn", __DIR__)
  @parse_dir Path.expand("../fixtures/parse", __DIR__)

  # Each grammar's start rule, rule names, and the fixture base name.
  @cases [
    %{name: "hello", start_rule: 0, rule_names: ~w(greeting)},
    %{name: "expr", start_rule: 0, rule_names: ~w(prog stat expr)}
  ]

  for fixture <- @cases do
    test "#{fixture.name}: parse tree matches the reference parser" do
      %{name: name, start_rule: start_rule, rule_names: rule_names} =
        unquote(Macro.escape(fixture))

      tree = parse(name, start_rule)
      assert Trees.to_string_tree(tree, rule_names) == expected(name)
    end
  end

  defp parse(name, start_rule) do
    parser_atn = load_atn("#{name}_parser")
    lexer_atn = load_atn("#{name}_lexer")
    input = @parse_dir |> Path.join("#{name}.input") |> File.read!() |> CharStream.new()
    tokens = lexer_atn |> Lexer.new(input) |> TokenStream.from_lexer()
    ParserInterpreter.parse(parser_atn, tokens, start_rule)
  end

  defp load_atn(name) do
    @atn_dir
    |> Path.join("#{name}.atn")
    |> File.read!()
    |> String.trim()
    |> String.split(",")
    |> Enum.map(&String.to_integer/1)
    |> ATNDeserializer.deserialize!()
  end

  defp expected(name) do
    @parse_dir |> Path.join("#{name}.tree") |> File.read!() |> String.trim()
  end
end
