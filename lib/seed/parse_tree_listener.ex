defmodule Seed.ParseTreeListener do
  @moduledoc """
  A behaviour for listening to a depth-first walk of a parse tree.

  This is the functional analogue of ANTLR's `ParseTreeListener`: instead of
  side-effecting callbacks, each callback receives the current accumulator
  and returns the next one, which `Seed.ParseTreeWalker` threads through the
  walk. A rule node fires `enter_rule/2` before its children and
  `exit_rule/2` after; leaves fire `visit_terminal/2` or
  `visit_error_node/2`.

  `use Seed.ParseTreeListener` injects no-op (accumulator-passthrough)
  defaults for every callback — the equivalent of ANTLR's base listener — so
  an implementation overrides only the callbacks it cares about:

      defmodule TokenText do
        use Seed.ParseTreeListener

        def visit_terminal(%Seed.TerminalNode{symbol: token}, acc), do: [token.text | acc]
      end

      texts = Seed.ParseTreeWalker.walk(TokenText, tree, []) |> Enum.reverse()
  """

  alias Seed.ErrorNode
  alias Seed.ParserRuleContext
  alias Seed.TerminalNode

  @typedoc "The accumulator threaded through the walk."
  @type acc :: term()

  @callback enter_rule(ParserRuleContext.t(), acc()) :: acc()
  @callback exit_rule(ParserRuleContext.t(), acc()) :: acc()
  @callback visit_terminal(TerminalNode.t(), acc()) :: acc()
  @callback visit_error_node(ErrorNode.t(), acc()) :: acc()

  defmacro __using__(_opts) do
    quote do
      @behaviour Seed.ParseTreeListener

      @impl true
      def enter_rule(_ctx, acc), do: acc

      @impl true
      def exit_rule(_ctx, acc), do: acc

      @impl true
      def visit_terminal(_node, acc), do: acc

      @impl true
      def visit_error_node(_node, acc), do: acc

      defoverridable enter_rule: 2, exit_rule: 2, visit_terminal: 2, visit_error_node: 2
    end
  end
end
