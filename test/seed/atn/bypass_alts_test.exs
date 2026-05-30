defmodule Seed.ATN.BypassAltsTest do
  use ExUnit.Case, async: true

  alias Seed.ATN.BypassAlts
  alias Seed.Interp
  alias Seed.ParserInterpreter
  alias Seed.ParserRuleContext
  alias Seed.TerminalNode
  alias Seed.Token
  alias Seed.TokenStream

  @interp_dir Path.expand("../../fixtures/interp", __DIR__)

  setup do
    grammar = Interp.load!(Path.join(@interp_dir, "Expr.interp"))
    %{grammar: grammar, bypassed: %{grammar | atn: BypassAlts.add(grammar.atn)}}
  end

  describe "add/1" do
    test "assigns one imaginary token type per rule, above max_token_type", %{
      grammar: grammar,
      bypassed: bypassed
    } do
      nrules = length(grammar.atn.rule_to_start_state)
      expected = Enum.map(0..(nrules - 1), &(grammar.atn.max_token_type + &1 + 1))

      assert bypassed.atn.rule_to_token_type == expected
      assert grammar.atn.rule_to_token_type == nil
    end

    test "adds three states and one decision per rule", %{grammar: grammar, bypassed: bypassed} do
      nrules = length(grammar.atn.rule_to_start_state)

      assert bypassed.atn.num_states == grammar.atn.num_states + 3 * nrules

      assert length(bypassed.atn.decision_to_state) ==
               length(grammar.atn.decision_to_state) + nrules
    end

    test "leaves the original parser ATN untouched (pure)", %{grammar: grammar} do
      before = grammar.atn
      _ = BypassAlts.add(grammar.atn)
      assert grammar.atn == before
    end

    test "rejects a lexer ATN", %{} do
      lexer = Interp.load!(Path.join(@interp_dir, "ExprLexer.interp"))
      assert_raise ArgumentError, fn -> BypassAlts.add(lexer.atn) end
    end
  end

  describe "parsing the imaginary rule token" do
    # The point of the transform: each rule's imaginary token, parsed as that
    # rule, yields a context whose only child is the tag terminal. This is the
    # shape `ParseTreePatternMatcher.getRuleTagToken` looks for.
    test "every rule bypasses to a single-terminal context", %{
      grammar: grammar,
      bypassed: bypassed
    } do
      assert_all_rules_bypass(grammar, bypassed)
    end

    # Calc has a left-recursive `expr` rule, exercising the precedence-prefix
    # branch of the transform (wrap to the StarLoopEntry, exclude the loop-back
    # edge) rather than wrapping to the rule stop.
    test "left-recursive (precedence) rules bypass correctly" do
      grammar = Interp.load!(Path.join(@interp_dir, "Calc.interp"))
      bypassed = %{grammar | atn: BypassAlts.add(grammar.atn)}
      assert_all_rules_bypass(grammar, bypassed)
    end
  end

  defp assert_all_rules_bypass(grammar, bypassed) do
    nrules = length(grammar.atn.rule_to_start_state)

    for rule <- 0..(nrules - 1) do
      token_type = grammar.atn.max_token_type + rule + 1
      token = Token.new(token_type, text: "<tag>", channel: Token.default_channel())
      stream = TokenStream.new([token, Token.eof_token()])

      assert {:ok, tree} = ParserInterpreter.parse(bypassed, stream, rule),
             "rule #{rule} failed to parse its imaginary token"

      assert %ParserRuleContext{rule_index: ^rule, children: [child]} = tree
      assert %TerminalNode{symbol: %Token{type: ^token_type}} = child
    end
  end
end
