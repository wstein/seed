defmodule Seed.ErrorRecoveryTest do
  use ExUnit.Case, async: true

  alias Seed.Interp
  alias Seed.Trees

  @interp_dir Path.expand("../fixtures/interp", __DIR__)
  @recover_dir Path.expand("../fixtures/recover", __DIR__)

  # {name, grammar, start_rule_index}. Each input is malformed; the oracle
  # <name>.tree is ANTLR's *recovered* tree (error nodes + <missing> tokens).
  # Mirrors scripts/gen_recover_fixtures.sh. `expr_extra_tok` is handled
  # separately below as a documented divergence.
  @cases [
    {"expr_missing_semi", "Expr", 0},
    {"expr_missing_eq", "Expr", 0},
    {"expr_no_expr", "Expr", 0},
    {"json_unclosed", "JSON", 0},
    {"json_no_value", "JSON", 0},
    {"calc_missing_operand", "Calc", 0}
  ]

  describe "recovered trees are byte-identical to ANTLR's DefaultErrorStrategy" do
    for {name, grammar, start_rule} <- @cases do
      @tag case: name
      test "#{name}" do
        {name, grammar, start_rule} = {unquote(name), unquote(grammar), unquote(start_rule)}

        assert recovered_tree(grammar, name, start_rule) <> "\n" ==
                 File.read!(Path.join(@recover_dir, "#{name}.tree"))
      end
    end
  end

  # Known divergence, rooted in the absence of an SLL prediction stage
  # (roadmap D). At the `expr` star-loop-exit decision with lookahead `4`,
  # ANTLR predicts in SLL (empty outer context), where exiting the loop reaches
  # the rule end and is viable — so it exits cleanly, returning `(expr 3)`, and
  # `stat` then deletes `4` as extraneous: `(stat x = (expr 3) 4 ;)`. Seed
  # predicts in full context, where exiting `expr` overshoots into `stat`
  # (which expects `;`); since `4` matches neither the loop operator nor `;`,
  # prediction reports no-viable and panic-resync consumes `4` into the still-
  # current `expr` frame. The recovery is sound, only located one rule deeper.
  # On *valid* input full-context and SLL always agree, so this never affects a
  # correct parse. If SLL lands, this should converge to ANTLR's tree.
  test "expr_extra_tok: full-context prediction recovers one rule deeper than ANTLR" do
    seed_tree = recovered_tree("Expr", "expr_extra_tok", 0)
    antlr_tree = String.trim_trailing(File.read!(Path.join(@recover_dir, "expr_extra_tok.tree")))

    assert seed_tree == "(prog (stat x = (expr 3 4) ;) <EOF>)"
    assert antlr_tree == "(prog (stat x = (expr 3) 4 ;) <EOF>)"
    refute seed_tree == antlr_tree
  end

  defp recovered_tree(grammar, name, start_rule) do
    lexer = Interp.load!(Path.join(@interp_dir, "#{grammar}Lexer.interp"))
    parser = Interp.load!(Path.join(@interp_dir, "#{grammar}.interp"))
    input = File.read!(Path.join(@recover_dir, "#{name}.input"))

    tree =
      case Seed.parse(parser, lexer, input, start_rule) do
        {:ok, tree} -> tree
        {:error, _diagnostics, tree} -> tree
      end

    Trees.to_string_tree(tree, parser)
  end
end
