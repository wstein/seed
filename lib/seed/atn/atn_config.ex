defmodule Seed.ATN.ATNConfig do
  @moduledoc """
  One configuration in an ATN simulation: a position in the grammar plus
  the context needed to interpret it.

  A configuration is an immutable value with the fields the lexer needs:

    * `:state` — the ATN state number;
    * `:alt` — the alternative (for the lexer, the rule, numbered from 1);
    * `:context` — the `Seed.ATN.PredictionContext` call stack;
    * `:lexer_action_executor` — actions accumulated so far, or `nil`; and
    * `:passed_through_non_greedy` — whether the path crossed a non-greedy
      decision.

  Two configurations are equal when all fields are equal. The lexer's
  configuration set relies on this full equality (it never merges
  contexts), so plain struct comparison is the deduplication key. The
  parser's semantic-context and outer-context fields are a later addition.
  """

  alias Seed.ATN.PredictionContext
  alias Seed.ATN.SemanticContext

  @type t :: %__MODULE__{
          state: non_neg_integer(),
          alt: pos_integer(),
          context: PredictionContext.t(),
          semantic_context: SemanticContext.t(),
          reaches_into_outer_context: non_neg_integer(),
          precedence_filter_suppressed: boolean(),
          lexer_action_executor: Seed.ATN.LexerActionExecutor.t() | nil,
          passed_through_non_greedy: boolean()
        }

  @enforce_keys [:state, :alt, :context]
  defstruct [
    :state,
    :alt,
    :context,
    semantic_context: :none,
    reaches_into_outer_context: 0,
    precedence_filter_suppressed: false,
    lexer_action_executor: nil,
    passed_through_non_greedy: false
  ]
end
