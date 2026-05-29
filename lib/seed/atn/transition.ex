defmodule Seed.ATN.Transition do
  @moduledoc """
  An edge between two ATN states.

  As with `Seed.ATN.State`, every transition is one struct discriminated by
  `:type` (an atom) instead of a class hierarchy. `:target` is the
  destination state's integer `state_number`. The remaining fields are
  populated per type:

    * `:atom` — `:label` (the matched symbol).
    * `:range` — `:from`/`:to` (inclusive bounds).
    * `:set` / `:not_set` — `:set` (a `Seed.IntervalSet`).
    * `:rule` — `:rule_start`, `:rule_index`, `:precedence`, `:follow_state`.
    * `:predicate` — `:rule_index`, `:pred_index`, `:ctx_dependent`.
    * `:action` — `:rule_index`, `:action_index`, `:ctx_dependent`.
    * `:precedence` — `:precedence`.
    * `:epsilon` / `:wildcard` — `:target` only. Epsilon transitions
      derived for rule-stop states also carry `:outermost_precedence_return`
      (the rule index whose precedence context ends, or `-1`).

  Epsilon, rule, predicate, action, and precedence transitions are
  *epsilon transitions*: they consume no input symbol.
  """

  alias Seed.IntervalSet

  @type transition_type ::
          :epsilon
          | :range
          | :rule
          | :predicate
          | :atom
          | :action
          | :set
          | :not_set
          | :wildcard
          | :precedence

  @type t :: %__MODULE__{
          type: transition_type(),
          target: non_neg_integer(),
          label: integer() | nil,
          from: integer() | nil,
          to: integer() | nil,
          set: IntervalSet.t() | nil,
          rule_start: non_neg_integer() | nil,
          rule_index: integer() | nil,
          precedence: integer() | nil,
          follow_state: non_neg_integer() | nil,
          pred_index: integer() | nil,
          action_index: integer() | nil,
          ctx_dependent: boolean() | nil,
          outermost_precedence_return: integer() | nil
        }

  @enforce_keys [:type, :target]
  defstruct type: nil,
            target: nil,
            label: nil,
            from: nil,
            to: nil,
            set: nil,
            rule_start: nil,
            rule_index: nil,
            precedence: nil,
            follow_state: nil,
            pred_index: nil,
            action_index: nil,
            ctx_dependent: nil,
            outermost_precedence_return: nil

  # Serialized transition-type ids, mirroring Transition in the reference
  # runtime.
  @type_by_id %{
    1 => :epsilon,
    2 => :range,
    3 => :rule,
    4 => :predicate,
    5 => :atom,
    6 => :action,
    7 => :set,
    8 => :not_set,
    9 => :wildcard,
    10 => :precedence
  }
  @id_by_type Map.new(@type_by_id, fn {id, type} -> {type, id} end)

  @epsilon_types [:epsilon, :rule, :predicate, :action, :precedence]

  @doc "Maps a serialized transition-type id to its atom."
  @spec type_from_id(integer()) :: transition_type()
  def type_from_id(id) when is_map_key(@type_by_id, id), do: @type_by_id[id]

  @doc "Maps a transition-type atom to its serialized id."
  @spec serialization_type(t()) :: integer()
  def serialization_type(%__MODULE__{type: type}), do: @id_by_type[type]

  @doc "Returns `true` when the transition consumes no input symbol."
  @spec epsilon?(t()) :: boolean()
  def epsilon?(%__MODULE__{type: type}), do: type in @epsilon_types

  @doc """
  Returns the symbols the transition matches as an interval set, or `nil`.

  Atom, range, set, and not-set transitions are *labeled*; epsilon-style
  transitions and wildcards are not. Mirrors `Transition.label()` in the
  reference runtime and is used to deduplicate parallel edges.
  """
  @spec label(t()) :: IntervalSet.t() | nil
  def label(%__MODULE__{type: :atom, label: value}) do
    IntervalSet.add_one(IntervalSet.new(), value)
  end

  def label(%__MODULE__{type: :range, from: from, to: to}) do
    IntervalSet.add_range(IntervalSet.new(), from, to)
  end

  def label(%__MODULE__{type: type, set: set}) when type in [:set, :not_set], do: set
  def label(%__MODULE__{}), do: nil
end
