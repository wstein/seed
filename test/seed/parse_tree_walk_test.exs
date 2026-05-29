defmodule Seed.ParseTreeWalkTest do
  use ExUnit.Case, async: true

  alias Seed.CharStream
  alias Seed.Interp
  alias Seed.Lexer
  alias Seed.ParserInterpreter
  alias Seed.ParseTreeVisitor
  alias Seed.ParseTreeWalker
  alias Seed.TokenStream

  @interp_dir Path.expand("../fixtures/interp", __DIR__)

  # Records the rule-enter/exit and leaf events in order.
  defmodule EventLog do
    use Seed.ParseTreeListener

    def enter_rule(ctx, acc), do: [{:enter, ctx.rule_index} | acc]
    def exit_rule(ctx, acc), do: [{:exit, ctx.rule_index} | acc]
    def visit_terminal(node, acc), do: [{:terminal, node.symbol.text} | acc]
  end

  # Sums 1 per terminal, ignoring rule structure.
  defmodule TerminalCount do
    use Seed.ParseTreeVisitor

    def visit_terminal(_node), do: 1
    def visit_rule(ctx), do: ctx |> visit_children() |> Enum.sum()
  end

  setup do
    parser = Interp.load!(Path.join(@interp_dir, "Expr.interp"))
    lexer = Interp.load!(Path.join(@interp_dir, "ExprLexer.interp"))
    {:ok, tokens} = lexer.atn |> Lexer.new(CharStream.new("x = 1 ;")) |> TokenStream.from_lexer()
    {:ok, tree} = ParserInterpreter.parse(parser, tokens, 0)
    %{tree: tree}
  end

  test "walker fires enter/exit around children and visits terminals in order", %{tree: tree} do
    events = ParseTreeWalker.walk(EventLog, tree, []) |> Enum.reverse()

    # prog enters first and exits last; every entered rule is exited.
    assert hd(events) == {:enter, 0}
    assert List.last(events) == {:exit, 0}

    assert Enum.count(events, &match?({:enter, _}, &1)) ==
             Enum.count(events, &match?({:exit, _}, &1))

    # Terminals appear in source order.
    terminals = for {:terminal, text} <- events, do: text
    assert terminals == ["x", "=", "1", ";", "<EOF>"]
  end

  test "visitor aggregates a value over the tree", %{tree: tree} do
    # "x = 1 ;" has five terminals including EOF.
    assert ParseTreeVisitor.visit(TerminalCount, tree) == 5
  end

  test "default visitor descends and returns nil leaves", %{tree: tree} do
    defmodule PassThrough do
      use Seed.ParseTreeVisitor
    end

    # With no overrides, every leaf is nil and rules return the child lists,
    # so flattening yields only nils — proving the default walk reached them.
    result = ParseTreeVisitor.visit(PassThrough, tree)
    assert result |> List.flatten() |> Enum.all?(&is_nil/1)
  end
end
