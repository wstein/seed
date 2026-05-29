defmodule Seed.ParseTreeWalker do
  @moduledoc """
  Walks a parse tree depth-first, driving a `Seed.ParseTreeListener`.

  Mirrors ANTLR's `ParseTreeWalker`: for a rule node it calls `enter_rule`,
  walks the children left to right, then calls `exit_rule`; for a leaf it
  calls `visit_terminal` or `visit_error_node`. The listener's accumulator is
  threaded through every callback and the final value is returned, so the
  walk is a pure fold over the tree.
  """

  alias Seed.ErrorNode
  alias Seed.ParserRuleContext
  alias Seed.ParseTreeListener
  alias Seed.TerminalNode

  @doc """
  Walks `tree` with `listener`, threading `acc`, and returns the final
  accumulator.
  """
  @spec walk(
          module(),
          ParserRuleContext.t() | TerminalNode.t() | ErrorNode.t(),
          ParseTreeListener.acc()
        ) :: ParseTreeListener.acc()
  def walk(listener, %TerminalNode{} = node, acc), do: listener.visit_terminal(node, acc)

  def walk(listener, %ErrorNode{} = node, acc), do: listener.visit_error_node(node, acc)

  def walk(listener, %ParserRuleContext{} = ctx, acc) do
    acc = listener.enter_rule(ctx, acc)
    acc = Enum.reduce(ctx.children, acc, fn child, acc -> walk(listener, child, acc) end)
    listener.exit_rule(ctx, acc)
  end
end
