defmodule Seed.ParserRuleContext do
  @moduledoc """
  A node in the parse tree, representing one rule invocation.

  Mirroring ANTLR, the rule context *is* the tree node: it records which
  rule it came from (`rule_index`) and its ordered `children`, each a nested
  `Seed.ParserRuleContext`, a `Seed.TerminalNode`, or a `Seed.ErrorNode`
  (a token involved in error recovery). The parser interpreter builds these
  as it walks the ATN.
  """

  @type child :: t() | Seed.TerminalNode.t() | Seed.ErrorNode.t()
  @type t :: %__MODULE__{
          rule_index: non_neg_integer(),
          children: [child()],
          invoking_state: integer()
        }

  @enforce_keys [:rule_index]
  defstruct rule_index: nil, children: [], invoking_state: -1

  @doc """
  Returns a new context for `rule_index`.

  `invoking_state` is the ATN state from which the rule was invoked (`-1`
  for the root); the parser uses it to return to the caller. It does not
  affect tree rendering.
  """
  @spec new(non_neg_integer(), integer()) :: t()
  def new(rule_index, invoking_state \\ -1) when is_integer(rule_index) do
    %__MODULE__{rule_index: rule_index, invoking_state: invoking_state}
  end

  @doc "Appends `child` (a rule context or terminal) to the context."
  @spec add_child(t(), child()) :: t()
  def add_child(%__MODULE__{children: children} = context, child) do
    %{context | children: children ++ [child]}
  end
end
