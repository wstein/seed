defmodule Seed.Vocabulary do
  @moduledoc """
  Maps integer token types to human-readable names.

  A vocabulary carries up to three names per token type, mirroring the
  reference ANTLR4 runtime:

    * a *literal* name — the quoted text of a literal token, e.g. `"'if'"`;
    * a *symbolic* name — the rule or token identifier, e.g. `"IF"`;
    * a *display* name — what diagnostics show, derived from the literal
      name, then the symbolic name, then the numeric type.

  The tool emits names as arrays indexed by token type. `new/2` accepts
  those lists (with `nil` for absent entries) and indexes them for lookup.

      iex> vocab = Seed.Vocabulary.new([nil, "'if'"], [nil, "IF"])
      iex> Seed.Vocabulary.display_name(vocab, 1)
      "'if'"
      iex> Seed.Vocabulary.symbolic_name(vocab, 1)
      "IF"
  """

  @type t :: %__MODULE__{
          literal_names: %{integer() => String.t()},
          symbolic_names: %{integer() => String.t()},
          max_token_type: integer()
        }

  defstruct literal_names: %{}, symbolic_names: %{}, max_token_type: 0

  @doc """
  Builds a vocabulary from literal- and symbolic-name lists.

  Each list is indexed by token type starting at `0`; `nil` entries are
  ignored. `max_token_type/1` reports the largest index across both lists.
  """
  @spec new([String.t() | nil], [String.t() | nil]) :: t()
  def new(literal_names, symbolic_names)
      when is_list(literal_names) and is_list(symbolic_names) do
    literals = index_names(literal_names)
    symbolics = index_names(symbolic_names)
    max_type = max(length(literal_names), length(symbolic_names)) - 1

    %__MODULE__{
      literal_names: literals,
      symbolic_names: symbolics,
      max_token_type: max(max_type, 0)
    }
  end

  @doc "An empty vocabulary, used when no names are available."
  @spec empty() :: t()
  def empty, do: %__MODULE__{}

  @doc "The largest token type this vocabulary knows about."
  @spec max_token_type(t()) :: integer()
  def max_token_type(%__MODULE__{max_token_type: max}), do: max

  @doc "Returns the literal name for `type`, or `nil`."
  @spec literal_name(t(), integer()) :: String.t() | nil
  def literal_name(%__MODULE__{literal_names: names}, type) when is_integer(type) do
    Map.get(names, type)
  end

  @doc "Returns the symbolic name for `type`, or `nil`."
  @spec symbolic_name(t(), integer()) :: String.t() | nil
  def symbolic_name(%__MODULE__{symbolic_names: names}, type) when is_integer(type) do
    Map.get(names, type)
  end

  @doc """
  Returns the display name for `type`.

  Resolution follows the reference runtime: the literal name if present,
  otherwise the symbolic name, otherwise the numeric type as a string.

      iex> vocab = Seed.Vocabulary.new([], [nil, "IF"])
      iex> Seed.Vocabulary.display_name(vocab, 1)
      "IF"
      iex> Seed.Vocabulary.display_name(vocab, 99)
      "99"
  """
  @spec display_name(t(), integer()) :: String.t()
  def display_name(%__MODULE__{} = vocab, type) when is_integer(type) do
    literal_name(vocab, type) || symbolic_name(vocab, type) || Integer.to_string(type)
  end

  defp index_names(names) do
    names
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn
      {nil, _index}, acc -> acc
      {name, index}, acc -> Map.put(acc, index, name)
    end)
  end
end
