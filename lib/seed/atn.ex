defmodule Seed.ATN do
  @moduledoc """
  An Augmented Transition Network: the graph an ANTLR grammar compiles to.

  An ATN is produced by `Seed.ATNDeserializer` from the serialized integer
  stream the ANTLR tool emits. It is an immutable value: `states` is a map
  from `state_number` to `Seed.ATN.State` (with `nil` for invalid slots),
  and every edge references other states by number, so the whole graph is a
  plain term with no cyclic references.

  This module is the data container plus read-only accessors. The lexer and
  parser ATN simulators (a later milestone) interpret it.
  """

  alias Seed.ATN.{State, Transition}

  @type grammar_type :: :lexer | :parser

  @type t :: %__MODULE__{
          grammar_type: grammar_type(),
          max_token_type: integer(),
          states: %{optional(non_neg_integer()) => State.t() | nil},
          num_states: non_neg_integer(),
          rule_to_start_state: [non_neg_integer()],
          rule_to_stop_state: [non_neg_integer()],
          rule_to_token_type: [integer()] | nil,
          mode_to_start_state: [non_neg_integer()],
          decision_to_state: [non_neg_integer()],
          lexer_actions: [Seed.ATN.LexerAction.t()],
          sets: [Seed.IntervalSet.t()]
        }

  @enforce_keys [:grammar_type, :max_token_type]
  defstruct grammar_type: nil,
            max_token_type: 0,
            states: %{},
            num_states: 0,
            rule_to_start_state: [],
            rule_to_stop_state: [],
            rule_to_token_type: nil,
            mode_to_start_state: [],
            decision_to_state: [],
            lexer_actions: [],
            sets: []

  @doc "Returns the state with the given `state_number`, or `nil`."
  @spec state(t(), non_neg_integer()) :: State.t() | nil
  def state(%__MODULE__{states: states}, state_number), do: Map.get(states, state_number)

  @doc "Returns the number of states, including invalid (`nil`) slots."
  @spec num_states(t()) :: non_neg_integer()
  def num_states(%__MODULE__{num_states: num_states}), do: num_states

  @doc "Returns the number of rules."
  @spec num_rules(t()) :: non_neg_integer()
  def num_rules(%__MODULE__{rule_to_start_state: rules}), do: length(rules)

  @doc "Returns the number of decisions."
  @spec num_decisions(t()) :: non_neg_integer()
  def num_decisions(%__MODULE__{decision_to_state: decisions}), do: length(decisions)

  @doc "Returns the number of lexer modes."
  @spec num_modes(t()) :: non_neg_integer()
  def num_modes(%__MODULE__{mode_to_start_state: modes}), do: length(modes)

  @doc """
  Returns a histogram of serialized state-type id to count.

  Invalid (`nil`) states are counted under id `-1`, matching the reference
  runtime's accounting.
  """
  @spec state_type_histogram(t()) :: %{integer() => pos_integer()}
  def state_type_histogram(%__MODULE__{states: states}) do
    states
    |> Map.values()
    |> Enum.reduce(%{}, fn
      nil, acc -> increment(acc, -1)
      %State{state_type: type}, acc -> increment(acc, State.type_id(type))
    end)
  end

  @doc """
  Returns a histogram of serialized transition-type id to count.

  This counts every transition on every state, including the epsilon
  transitions derived for rule-stop states during deserialization.
  """
  @spec transition_type_histogram(t()) :: %{integer() => pos_integer()}
  def transition_type_histogram(%__MODULE__{states: states}) do
    states
    |> Map.values()
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(%{}, fn %State{transitions: transitions}, acc ->
      Enum.reduce(transitions, acc, fn transition, acc ->
        increment(acc, Transition.serialization_type(transition))
      end)
    end)
  end

  defp increment(map, key), do: Map.update(map, key, 1, &(&1 + 1))
end
