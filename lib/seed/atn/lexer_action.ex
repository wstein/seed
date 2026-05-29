defmodule Seed.ATN.LexerAction do
  @moduledoc """
  An action a lexer performs while or after matching a token.

  Lexer ATNs carry a table of these actions; action transitions reference
  them by index. Each action is one struct discriminated by `:type`:

    * `:channel` — `:data1` is the target channel.
    * `:custom` — `:data1` is the rule index, `:data2` the action index.
    * `:mode` / `:push_mode` — `:data1` is the lexer mode.
    * `:type` — `:data1` is the token type.
    * `:more` / `:pop_mode` / `:skip` — no data.

  The `:data1`/`:data2` fields are kept verbatim from the serialized form,
  matching the reference runtime's action ordinals.
  """

  @type action_type ::
          :channel
          | :custom
          | :mode
          | :more
          | :pop_mode
          | :push_mode
          | :skip
          | :type

  @type t :: %__MODULE__{type: action_type(), data1: integer(), data2: integer()}

  @enforce_keys [:type]
  defstruct type: nil, data1: 0, data2: 0

  # Serialized lexer-action ordinals, mirroring LexerActionType.
  @type_by_id %{
    0 => :channel,
    1 => :custom,
    2 => :mode,
    3 => :more,
    4 => :pop_mode,
    5 => :push_mode,
    6 => :skip,
    7 => :type
  }

  @doc "Builds a lexer action from its serialized ordinal and data words."
  @spec from_serialized(integer(), integer(), integer()) :: t()
  def from_serialized(ordinal, data1, data2) when is_map_key(@type_by_id, ordinal) do
    %__MODULE__{type: @type_by_id[ordinal], data1: data1, data2: data2}
  end
end
