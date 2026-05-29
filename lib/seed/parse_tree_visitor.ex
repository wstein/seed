defmodule Seed.ParseTreeVisitor do
  @moduledoc """
  A behaviour for visiting a parse tree and computing a value from it.

  This is the functional analogue of ANTLR's `ParseTreeVisitor`: unlike a
  listener, which threads one accumulator through a fixed walk, a visitor
  decides for each node what to compute and which children to descend into,
  returning a value. `visit/2` dispatches on the node kind to the visitor
  module's `visit_rule/1`, `visit_terminal/1`, or `visit_error_node/1`.

  `use Seed.ParseTreeVisitor` injects defaults equivalent to ANTLR's base
  visitor: `visit_rule/1` descends into the children (`visit_children/1`) and
  the leaf callbacks return `nil`. `visit_children/1` returns the list of the
  children's results; override `visit_rule/1` to aggregate them differently:

      defmodule TerminalCount do
        use Seed.ParseTreeVisitor

        def visit_terminal(_node), do: 1
        def visit_rule(ctx), do: ctx |> visit_children() |> Enum.sum()
      end

      count = Seed.ParseTreeVisitor.visit(TerminalCount, tree)
  """

  alias Seed.ErrorNode
  alias Seed.ParserRuleContext
  alias Seed.TerminalNode

  @typedoc "The value a visit computes."
  @type result :: term()

  @callback visit_rule(ParserRuleContext.t()) :: result()
  @callback visit_terminal(TerminalNode.t()) :: result()
  @callback visit_error_node(ErrorNode.t()) :: result()

  @doc "Dispatches to `visitor`'s callback for the kind of `node`."
  @spec visit(module(), ParserRuleContext.t() | TerminalNode.t() | ErrorNode.t()) :: result()
  def visit(visitor, %ParserRuleContext{} = ctx), do: visitor.visit_rule(ctx)
  def visit(visitor, %TerminalNode{} = node), do: visitor.visit_terminal(node)
  def visit(visitor, %ErrorNode{} = node), do: visitor.visit_error_node(node)

  defmacro __using__(_opts) do
    quote do
      @behaviour Seed.ParseTreeVisitor

      @impl true
      def visit_rule(ctx), do: visit_children(ctx)

      @impl true
      def visit_terminal(_node), do: nil

      @impl true
      def visit_error_node(_node), do: nil

      @doc "Visits each child with this visitor, returning the list of results."
      @spec visit_children(Seed.ParserRuleContext.t()) :: [Seed.ParseTreeVisitor.result()]
      def visit_children(%Seed.ParserRuleContext{children: children}) do
        Enum.map(children, &Seed.ParseTreeVisitor.visit(__MODULE__, &1))
      end

      defoverridable visit_rule: 1, visit_terminal: 1, visit_error_node: 1, visit_children: 1
    end
  end
end
