defmodule Seed.ATN.State do
  @moduledoc """
  A single state in an Augmented Transition Network.

  The reference ANTLR4 runtime models states with a class hierarchy; Seed
  represents every state with one struct discriminated by `:state_type`
  (an atom), following the value-oriented approach of the Go runtime. This
  keeps the ATN a plain immutable graph whose edges reference other states
  by integer `state_number`.

  Type-specific fields are populated only for the relevant states:

    * `:non_greedy` / `:decision` — decision states.
    * `:is_precedence_rule` / `:stop_state` — rule-start states.
    * `:is_precedence_decision` / `:loop_back_state` — star-loop-entry,
      plus-loop-back, and star-loop-back states.
    * `:end_state` — block-start states; `:start_state` — block-end states.
  """

  alias Seed.ATN.Transition

  @type state_type ::
          :invalid
          | :basic
          | :rule_start
          | :block_start
          | :plus_block_start
          | :star_block_start
          | :token_start
          | :rule_stop
          | :block_end
          | :star_loop_back
          | :star_loop_entry
          | :plus_loop_back
          | :loop_end

  @type t :: %__MODULE__{
          state_number: non_neg_integer(),
          state_type: state_type(),
          rule_index: integer(),
          transitions: [Transition.t()],
          decision: integer(),
          non_greedy: boolean(),
          is_precedence_rule: boolean(),
          stop_state: non_neg_integer() | nil,
          is_precedence_decision: boolean(),
          loop_back_state: non_neg_integer() | nil,
          end_state: non_neg_integer() | nil,
          start_state: non_neg_integer() | nil
        }

  @enforce_keys [:state_number, :state_type, :rule_index]
  defstruct state_number: nil,
            state_type: :invalid,
            rule_index: -1,
            transitions: [],
            decision: -1,
            non_greedy: false,
            is_precedence_rule: false,
            stop_state: nil,
            is_precedence_decision: false,
            loop_back_state: nil,
            end_state: nil,
            start_state: nil

  # Serialized state-type ids, mirroring ATNState in the reference runtime.
  @type_by_id %{
    1 => :basic,
    2 => :rule_start,
    3 => :block_start,
    4 => :plus_block_start,
    5 => :star_block_start,
    6 => :token_start,
    7 => :rule_stop,
    8 => :block_end,
    9 => :star_loop_back,
    10 => :star_loop_entry,
    11 => :plus_loop_back,
    12 => :loop_end
  }
  @id_by_type Map.new(@type_by_id, fn {id, type} -> {type, id} end)

  @block_start_types [:block_start, :plus_block_start, :star_block_start]
  @decision_types [
    :block_start,
    :plus_block_start,
    :star_block_start,
    :star_loop_entry,
    :plus_loop_back,
    :star_loop_back,
    :token_start
  ]

  @doc "Maps a serialized state-type id to its atom, or `:invalid` for `0`."
  @spec type_from_id(integer()) :: state_type()
  def type_from_id(0), do: :invalid
  def type_from_id(id) when is_map_key(@type_by_id, id), do: @type_by_id[id]

  @doc "Maps a state-type atom to its serialized id (`-1` for `:invalid`)."
  @spec type_id(state_type()) :: integer()
  def type_id(:invalid), do: -1
  def type_id(type) when is_map_key(@id_by_type, type), do: @id_by_type[type]

  @doc "Returns `true` when `type` is one of the block-start state types."
  @spec block_start?(state_type()) :: boolean()
  def block_start?(type), do: type in @block_start_types

  @doc """
  Returns `true` when states of `type` are decision states.

  Decision states carry a `:decision` index and may be marked non-greedy.
  """
  @spec decision?(state_type()) :: boolean()
  def decision?(type), do: type in @decision_types

  @doc """
  Appends `transition` to the state, skipping it if already present.

  Mirroring the reference runtime, a transition is a duplicate when one to
  the same target already exists and either both carry the same label or
  both are epsilon transitions. This keeps parallel edges from being
  double-counted (for example the epsilon return edges derived for a
  rule-stop state).
  """
  @spec add_transition(t(), Transition.t()) :: t()
  def add_transition(%__MODULE__{transitions: transitions} = state, %Transition{} = transition) do
    if duplicate?(transitions, transition) do
      state
    else
      %{state | transitions: transitions ++ [transition]}
    end
  end

  defp duplicate?(transitions, new_transition) do
    new_label = Transition.label(new_transition)
    Enum.any?(transitions, &same_edge?(&1, new_transition, new_label))
  end

  defp same_edge?(
         %Transition{target: target} = existing,
         %Transition{target: target} = new,
         new_label
       ) do
    existing_label = Transition.label(existing)

    cond do
      not is_nil(existing_label) and not is_nil(new_label) -> existing_label == new_label
      Transition.epsilon?(existing) and Transition.epsilon?(new) -> true
      true -> false
    end
  end

  defp same_edge?(_existing, _new, _new_label), do: false
end
