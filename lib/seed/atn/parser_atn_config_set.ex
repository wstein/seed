defmodule Seed.ATN.ParserATNConfigSet do
  @moduledoc """
  A configuration set for parser prediction that merges contexts on
  collision.

  Unlike the lexer's set (which deduplicates by full equality), the parser
  keys configurations on `(state, alt, semantic_context)` and merges the
  prediction contexts of colliding configurations — this is what keeps the
  configuration set finite during adaptive prediction. `full_ctx`
  distinguishes full-LL merges (`true`) from SLL wildcard merges (`false`).
  """

  alias Seed.ATN.ATNConfig
  alias Seed.ATN.PredictionContext

  @type t :: %__MODULE__{
          lookup: %{optional(tuple()) => ATNConfig.t()},
          order: [tuple()],
          full_ctx: boolean(),
          dips_into_outer_context: boolean()
        }

  defstruct lookup: %{}, order: [], full_ctx: false, dips_into_outer_context: false

  @doc "An empty configuration set; `full_ctx` selects full-LL vs SLL merge."
  @spec new(boolean()) :: t()
  def new(full_ctx \\ false), do: %__MODULE__{full_ctx: full_ctx}

  @doc """
  Adds `config`, merging its context into an existing config with the same
  `(state, alt, semantic_context)` key.
  """
  @spec add(t(), ATNConfig.t()) :: t()
  def add(%__MODULE__{} = set, %ATNConfig{} = config) do
    key = {config.state, config.alt, config.semantic_context}

    set = %{
      set
      | dips_into_outer_context:
          set.dips_into_outer_context or config.reaches_into_outer_context > 0
    }

    case Map.get(set.lookup, key) do
      nil ->
        %{set | lookup: Map.put(set.lookup, key, config), order: set.order ++ [key]}

      existing ->
        %{set | lookup: Map.put(set.lookup, key, merge_into(existing, config, set.full_ctx))}
    end
  end

  @doc "The configurations in insertion order."
  @spec configs(t()) :: [ATNConfig.t()]
  def configs(%__MODULE__{lookup: lookup, order: order}),
    do: Enum.map(order, &Map.fetch!(lookup, &1))

  @doc "Returns `true` when the set holds no configurations."
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{order: []}), do: true
  def empty?(%__MODULE__{}), do: false

  @doc "The number of distinct configurations in the set (O(1))."
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{lookup: lookup}), do: map_size(lookup)

  defp merge_into(existing, config, full_ctx) do
    %{
      existing
      | context: PredictionContext.merge(existing.context, config.context, not full_ctx),
        reaches_into_outer_context:
          max(existing.reaches_into_outer_context, config.reaches_into_outer_context),
        precedence_filter_suppressed:
          existing.precedence_filter_suppressed or config.precedence_filter_suppressed
    }
  end
end
