defmodule Seed.ATN.PredictionMode do
  @moduledoc """
  Helpers that decide when adaptive prediction can stop.

  Prediction advances a configuration set token by token until either a
  single alternative remains (`unique_alt/1`) or the surviving alternatives
  are in unresolvable SLL conflict (`sll_conflict?/2`) — two configurations
  at the same ATN state and context but predicting different alternatives.
  This module implements the subset of `PredictionMode` the SLL loop needs.
  """

  alias Seed.ATN.ATNConfig
  alias Seed.ATN.ParserATNConfigSet

  @invalid_alt 0

  @doc "The alternative all configurations agree on, or `0` if they differ."
  @spec unique_alt([ATNConfig.t()]) :: non_neg_integer()
  def unique_alt(configs) do
    case configs |> Enum.map(& &1.alt) |> Enum.uniq() do
      [alt] -> alt
      _many -> @invalid_alt
    end
  end

  @doc "The set of alternatives present in `configs`."
  @spec alts([ATNConfig.t()]) :: MapSet.t()
  def alts(configs), do: MapSet.new(configs, & &1.alt)

  @doc """
  Returns `true` when SLL prediction should stop at `config_set`.

  That is when every configuration is in a rule-stop state (all paths
  ended) or two configurations share an ATN state and context but predict
  different alternatives (an SLL conflict that more lookahead cannot break).
  """
  @spec sll_conflict?(ParserATNConfigSet.t(), Seed.ATN.t()) :: boolean()
  def sll_conflict?(config_set, atn) do
    configs = ParserATNConfigSet.configs(config_set)
    all_in_rule_stop?(configs, atn) or conflicting_alts?(configs)
  end

  @doc "The lowest alternative among `configs` (the SLL conflict resolution)."
  @spec min_alt([ATNConfig.t()]) :: pos_integer()
  def min_alt(configs), do: configs |> Enum.map(& &1.alt) |> Enum.min()

  defp all_in_rule_stop?(configs, atn) do
    Enum.all?(configs, fn config ->
      Map.fetch!(atn.states, config.state).state_type == :rule_stop
    end)
  end

  # True when some (state, context) group spans more than one alternative.
  defp conflicting_alts?(configs) do
    configs
    |> Enum.group_by(fn %ATNConfig{state: state, context: context} -> {state, context} end)
    |> Enum.any?(fn {_key, group} ->
      group |> Enum.map(& &1.alt) |> Enum.uniq() |> length() > 1
    end)
  end
end
