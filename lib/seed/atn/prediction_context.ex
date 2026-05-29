defmodule Seed.ATN.PredictionContext do
  @moduledoc """
  The rule-invocation stack a configuration carries during ATN simulation.

  The reference runtime has three forms — empty, singleton, and array —
  where arrays arise only from *merging* contexts. The lexer never merges
  (its configuration set deduplicates by full equality, including context),
  so the lexer needs only two forms, which this module provides:

    * the empty context `:empty`, the bottom of the stack (`$`); and
    * a singleton `%PredictionContext{parent: ctx, return_state: n}`, one
      rule invocation returning to ATN state `n`.

  A singleton whose return state is the empty sentinel collapses to
  `:empty`, mirroring `SingletonPredictionContext.create`. The parser's
  array form and merge algorithm are a later addition.
  """

  @empty_return_state 0x7FFFFFFF

  @type t :: :empty | %__MODULE__{parent: t(), return_state: non_neg_integer()}

  @enforce_keys [:parent, :return_state]
  defstruct [:parent, :return_state]

  @doc "The sentinel return state marking the bottom of the stack (`$`)."
  @spec empty_return_state() :: pos_integer()
  def empty_return_state, do: @empty_return_state

  @doc "The empty context."
  @spec empty() :: :empty
  def empty, do: :empty

  @doc "Returns `true` for the empty context."
  @spec empty?(t()) :: boolean()
  def empty?(:empty), do: true
  def empty?(%__MODULE__{}), do: false

  @doc """
  Pushes a return to `return_state` onto `parent`.

  Collapses to `:empty` when pushing the empty sentinel onto the empty
  context, matching the reference factory.
  """
  @spec singleton(t(), integer()) :: t()
  def singleton(:empty, @empty_return_state), do: :empty
  def singleton(parent, return_state), do: %__MODULE__{parent: parent, return_state: return_state}
end
