defmodule Seed.G4BootstrapTest do
  @moduledoc """
  ADR-007 Phase 0: prove Seed's runtime can parse ANTLR grammar files.

  Using `G4.interp`/`G4Lexer.interp` — a grammar describing a *subset* of
  `.g4` syntax, compiled by the reference tool — Seed parses its own grammar
  fixtures. This is the bootstrap the self-hosting tool's front end will use
  (parse `.g4` with Seed, then build the ATN). Grammar features outside the
  subset (semantic predicates `{...}?`, embedded actions, `..` ranges) are
  not yet covered and are the next grammar iteration, not a bootstrap
  blocker.
  """
  use ExUnit.Case, async: true

  alias Seed.Interp
  alias Seed.XPath

  @interp_dir Path.expand("../fixtures/interp", __DIR__)
  @grammar_dir Path.expand("../fixtures/atn/grammars", __DIR__)

  setup_all do
    %{
      grammar: Interp.load!(Path.join(@interp_dir, "G4.interp")),
      lexer: Interp.load!(Path.join(@interp_dir, "G4Lexer.interp"))
    }
  end

  # These fixtures stay within the Phase-0 subset of .g4 syntax.
  for name <- ~w(Hello Expr Hidden Ctx) do
    test "parses #{name}.g4 with the runtime", %{grammar: grammar, lexer: lexer} do
      source = File.read!(Path.join(@grammar_dir, unquote(name) <> ".g4"))
      assert {:ok, _tree} = Seed.parse(grammar, lexer, source, 0)
    end
  end

  test "the parsed tree is queryable with XPath", %{grammar: grammar, lexer: lexer} do
    source = File.read!(Path.join(@grammar_dir, "Hello.g4"))
    assert {:ok, tree} = Seed.parse(grammar, lexer, source, 0)

    # Hello.g4 declares one grammar and three rules (greeting, ID, WS).
    assert length(XPath.find(tree, "//grammarSpec", grammar)) == 1
    assert length(XPath.find(tree, "//ruleSpec", grammar)) == 3
  end
end
