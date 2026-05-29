defmodule Seed.ParserRuleContext do
  @moduledoc """
  A node in the parse tree, representing one rule invocation.

  Mirroring ANTLR, the rule context *is* the tree node: it records which
  rule it came from (`rule_index`) and its ordered `children`, each either a
  nested `Seed.ParserRuleContext` or a `Seed.TerminalNode`. The parser
  interpreter builds these as it walks the ATN.
  """

  @type child :: t() | Seed.TerminalNode.t()
  @type t :: %__MODULE__{rule_index: non_neg_integer(), children: [child()]}

  @enforce_keys [:rule_index]
  defstruct rule_index: nil, children: []

  @doc "Returns a new context for `rule_index`."
  @spec new(non_neg_integer()) :: t()
  def new(rule_index) when is_integer(rule_index), do: %__MODULE__{rule_index: rule_index}

  @doc "Appends `child` (a rule context or terminal) to the context."
  @spec add_child(t(), child()) :: t()
  def add_child(%__MODULE__{children: children} = context, child) do
    %{context | children: children ++ [child]}
  end
end
