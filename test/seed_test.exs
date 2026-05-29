defmodule SeedTest do
  use ExUnit.Case, async: true
  doctest Seed

  alias Seed.Diagnostic
  alias Seed.Interp
  alias Seed.Token
  alias Seed.Trees

  @interp_dir Path.expand("fixtures/interp", __DIR__)
  @parse_dir Path.expand("fixtures/parse", __DIR__)

  test "version/0 returns the configured project version" do
    assert Seed.version() == Mix.Project.config()[:version]
    assert is_binary(Seed.version())
  end

  describe "parse/4" do
    test "lexes and parses end to end" do
      parser = load("Expr")
      lexer = load("ExprLexer")
      input = File.read!(Path.join(@parse_dir, "expr.input"))
      expected = @parse_dir |> Path.join("expr.tree") |> File.read!() |> String.trim()

      assert {:ok, tree} = Seed.parse(parser, lexer, input, 0)
      assert Trees.to_string_tree(tree, parser) == expected
    end

    test "returns a lexer diagnostic when the input cannot be tokenized" do
      assert {:error, [%Diagnostic{code: :no_viable_token}]} =
               Seed.parse(load("Expr"), load("ExprLexer"), "@", 0)
    end
  end

  describe "tokenize/2" do
    test "returns the token list ending with EOF" do
      assert {:ok, tokens} = Seed.tokenize(load("ExprLexer"), "x")
      assert hd(tokens).text == "x"
      assert List.last(tokens).type == Token.eof()
    end
  end

  defp load(name), do: Interp.load!(Path.join(@interp_dir, name <> ".interp"))
end
