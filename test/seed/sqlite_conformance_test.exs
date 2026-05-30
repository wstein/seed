defmodule Seed.SQLiteConformanceTest do
  @moduledoc """
  A large, real-world grammar (vendored SQLite, ~1180 lines) parsed
  byte-identically to the ANTLR reference — a scale and breadth check beyond
  the small authored fixtures. See `test/fixtures/atn/grammars/VENDORED.md`.
  """
  use ExUnit.Case, async: true

  alias Seed.CharStream
  alias Seed.Interp
  alias Seed.Lexer
  alias Seed.ParserInterpreter
  alias Seed.TokenStream
  alias Seed.Trees

  @interp_dir Path.expand("../fixtures/interp", __DIR__)
  @parse_dir Path.expand("../fixtures/parse", __DIR__)

  # sql: select with joins, IN, ORDER BY, LIMIT.
  # sql2: WITH/CTE, INSERT...SELECT, CASE WHEN, scalar subquery, UNION.
  for name <- ~w(sql sql2) do
    test "parses #{name}.input identically to the reference" do
      parser = Interp.load!(Path.join(@interp_dir, "SQLiteParser.interp"))
      lexer = Interp.load!(Path.join(@interp_dir, "SQLiteLexer.interp"))

      input =
        @parse_dir |> Path.join(unquote(name) <> ".input") |> File.read!() |> CharStream.new()

      {:ok, tokens} = lexer.atn |> Lexer.new(input) |> TokenStream.from_lexer()

      # `parse` is rule 0; the case-insensitive keywords come baked into the ATN.
      assert {:ok, tree} = ParserInterpreter.parse(parser, tokens, 0)

      expected =
        @parse_dir |> Path.join(unquote(name) <> ".tree") |> File.read!() |> String.trim()

      assert Trees.to_string_tree(tree, parser) == expected
    end
  end
end
