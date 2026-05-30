defmodule Seed.TreePatternMatcherTest do
  use ExUnit.Case, async: true

  alias Seed.Interp
  alias Seed.ParseTreeMatch
  alias Seed.TreePatternMatcher
  alias Seed.Trees

  @interp_dir Path.expand("../fixtures/interp", __DIR__)
  @pattern_dir Path.expand("../fixtures/pattern", __DIR__)

  # Each case mirrors an entry in scripts/gen_pattern_fixtures.sh:
  # {name, grammar, subject_start_rule, pattern_rule, xpath, pattern}.
  @cases [
    {"expr_stat", "Expr", "prog", "stat", "//stat", "<ID> = <expr>;"},
    {"expr_add", "Expr", "prog", "expr", "//expr", "<expr> + <expr>"},
    {"expr_label", "Expr", "prog", "stat", "//stat", "<lhs:ID> = <rhs:expr>;"},
    {"expr_int", "Expr", "prog", "stat", "//stat", "<ID> = <INT>;"},
    {"calc_pow", "Calc", "prog", "expr", "//expr", "<expr> ^ <expr>"},
    {"json_pair", "JSON", "json", "pair", "//pair", "<STRING> : <value>"}
  ]

  describe "match dumps are byte-identical to ANTLR's ParseTreePatternMatcher" do
    for {name, grammar, start_rule, pattern_rule, xpath, pattern} <- @cases do
      @tag case: name
      test "#{name}: #{pattern}" do
        {name, grammar, start_rule, pattern_rule, xpath, pattern} =
          {unquote(name), unquote(grammar), unquote(start_rule), unquote(pattern_rule),
           unquote(xpath), unquote(pattern)}

        lexer = Interp.load!(Path.join(@interp_dir, "#{grammar}Lexer.interp"))
        parser = Interp.load!(Path.join(@interp_dir, "#{grammar}.interp"))

        {:ok, tree} =
          Seed.parse(parser, lexer, File.read!(input_path(name)), rule_index(parser, start_rule))

        matcher = TreePatternMatcher.new(lexer, parser)
        compiled = TreePatternMatcher.compile(matcher, pattern, rule_index(parser, pattern_rule))

        dump = render(compiled, tree, xpath, parser)
        assert dump == File.read!(dump_path(name))
      end
    end
  end

  # Reproduces scripts/PatternDump.java's canonical dump.
  defp render(compiled, tree, xpath, grammar) do
    header = "PATTERN " <> Trees.to_string_tree(compiled.tree, grammar) <> "\n"

    matches =
      compiled
      |> TreePatternMatcher.find_all(tree, xpath)
      |> Enum.map_join("", &render_match(&1, grammar))

    header <> matches
  end

  defp render_match(%ParseTreeMatch{tree: tree, labels: labels}, grammar) do
    bound =
      labels
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map_join("", fn key ->
        nodes = Enum.map_join(labels[key], "|", &Trees.to_string_tree(&1, grammar))
        " #{key}=[#{nodes}]"
      end)

    "#{Trees.to_string_tree(tree, grammar)} ::#{bound}\n"
  end

  defp rule_index(parser, name), do: Enum.find_index(parser.rule_names, &(&1 == name))
  defp input_path(name), do: Path.join(@pattern_dir, "#{name}.input")
  defp dump_path(name), do: Path.join(@pattern_dir, "#{name}.dump")
end
