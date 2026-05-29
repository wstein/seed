defmodule Seed.ATN.ATNConfigSet do
  @moduledoc """
  An ordered, deduplicated set of `Seed.ATN.ATNConfig` values.

  The lexer deduplicates configurations by full equality (state, alt,
  context, executor, and non-greedy flag), so this set keys on the whole
  config struct. Insertion order is preserved because it determines lexer
  rule priority: when several rules match the same text, the earliest rule
  (lowest alt, added first) wins.
  """

  alias Seed.ATN.ATNConfig

  @type t :: %__MODULE__{configs: [ATNConfig.t()], seen: %{optional(ATNConfig.t()) => true}}

  defstruct configs: [], seen: %{}

  @doc "An empty configuration set."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Adds `config`, ignoring it if an equal config is already present.

  Returns the set unchanged on a duplicate, preserving the position of the
  first occurrence.
  """
  @spec add(t(), ATNConfig.t()) :: t()
  def add(%__MODULE__{seen: seen} = set, %ATNConfig{} = config) do
    if Map.has_key?(seen, config) do
      set
    else
      %{set | configs: set.configs ++ [config], seen: Map.put(seen, config, true)}
    end
  end

  @doc "Returns the configurations in insertion order."
  @spec configs(t()) :: [ATNConfig.t()]
  def configs(%__MODULE__{configs: configs}), do: configs

  @doc "Returns `true` when the set holds no configurations."
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{configs: []}), do: true
  def empty?(%__MODULE__{}), do: false
end
