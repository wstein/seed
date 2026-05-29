defmodule Seed.ParserRuleContext do
  @moduledoc """
  A node in the parse tree, representing one rule invocation.

  Mirroring ANTLR, the rule context *is* the tree node: it records which
  rule it came from (`rule_index`) and its ordered `children`, each a nested
  `Seed.ParserRuleContext`, a `Seed.TerminalNode`, or a `Seed.ErrorNode`
  (a token involved in error recovery). The parser interpreter builds these
  as it walks the ATN.

  The parser builds children with `prepend_child/2` (O(1)) and calls `seal/1`
  once when a context is finished to restore source order, avoiding the O(n²)
  of appending to a wide rule. `add_child/2` is the ordered, append-at-end
  variant for callers building a context by hand.
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

  @doc "Appends `child` (a rule context or terminal) in source order."
  @spec add_child(t(), child()) :: t()
  def add_child(%__MODULE__{children: children} = context, child) do
    %{context | children: children ++ [child]}
  end

  @doc """
  Prepends `child` — the O(1) building primitive used by the parser.

  Children accumulate reversed; call `seal/1` once the context is finished to
  restore source order.
  """
  @spec prepend_child(t(), child()) :: t()
  def prepend_child(%__MODULE__{children: children} = context, child) do
    %{context | children: [child | children]}
  end

  @doc """
  Finalizes a context built with `prepend_child/2`, restoring source order.

  Reverses only this context's direct children; nested contexts are sealed
  individually as they finish.
  """
  @spec seal(t()) :: t()
  def seal(%__MODULE__{children: children} = context) do
    %{context | children: Enum.reverse(children)}
  end
end
