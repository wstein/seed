defmodule Seed.ParseTreeMatch do
  @moduledoc """
  The result of matching a parse tree against a compiled tree pattern, after
  the reference `org.antlr.v4.runtime.tree.pattern.ParseTreeMatch`.

  `labels` maps each tag name — and each explicit label — to the list of tree
  nodes it bound, in document order. A `<expr>` tag binds under `"expr"`; a
  labeled `<e:expr>` binds under both `"e"` and `"expr"`. `mismatched_node` is
  the first node where the match failed, or `nil` when the whole tree matched.
  """

  alias Seed.ErrorNode
  alias Seed.ParserRuleContext
  alias Seed.TerminalNode
  alias Seed.TreePattern

  @type tree_node :: ParserRuleContext.t() | TerminalNode.t() | ErrorNode.t()

  @type t :: %__MODULE__{
          tree: tree_node(),
          pattern: TreePattern.t(),
          labels: %{optional(String.t()) => [tree_node()]},
          mismatched_node: tree_node() | nil
        }

  @enforce_keys [:tree, :pattern, :labels]
  defstruct [:tree, :pattern, :labels, mismatched_node: nil]

  @doc "Returns `true` when the tree matched the pattern with no mismatch."
  @spec succeeded?(t()) :: boolean()
  def succeeded?(%__MODULE__{mismatched_node: nil}), do: true
  def succeeded?(%__MODULE__{}), do: false

  @doc """
  Returns the last node bound to `label`, or `nil`.

  When a label binds several nodes (a tag inside a loop), the last is
  returned, mirroring the reference.
  """
  @spec get(t(), String.t()) :: tree_node() | nil
  def get(%__MODULE__{labels: labels}, label) do
    case Map.get(labels, label) do
      nil -> nil
      nodes -> List.last(nodes)
    end
  end

  @doc "Returns every node bound to `label`, in document order (possibly empty)."
  @spec get_all(t(), String.t()) :: [tree_node()]
  def get_all(%__MODULE__{labels: labels}, label), do: Map.get(labels, label, [])
end
