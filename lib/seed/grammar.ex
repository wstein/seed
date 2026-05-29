defmodule Seed.Grammar do
  @moduledoc """
  A grammar's runtime metadata: everything needed to lex or parse, with no
  generated code.

  It bundles the deserialized `Seed.ATN` with the names the ANTLR tool emits
  alongside it — a `Seed.Vocabulary` (literal and symbolic token names),
  the rule names, and (for lexers) the channel and mode names. `Seed.Interp`
  builds one from a `.interp` file; the parser interpreter and tree renderer
  consume it so callers no longer pass bare ATNs and rule-name lists around.
  """

  alias Seed.ATN
  alias Seed.Vocabulary

  @type t :: %__MODULE__{
          atn: ATN.t(),
          vocabulary: Vocabulary.t(),
          rule_names: [String.t()],
          channel_names: [String.t()],
          mode_names: [String.t()]
        }

  @enforce_keys [:atn, :vocabulary, :rule_names]
  defstruct [:atn, :vocabulary, :rule_names, channel_names: [], mode_names: []]

  @doc "Returns the name of the rule with index `rule_index`, or `nil`."
  @spec rule_name(t(), non_neg_integer()) :: String.t() | nil
  def rule_name(%__MODULE__{rule_names: rule_names}, rule_index),
    do: Enum.at(rule_names, rule_index)
end
