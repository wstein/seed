defmodule Seed.ErrorNode do
  @moduledoc """
  A parse-tree leaf marking a token involved in error recovery.

  Like `Seed.TerminalNode` it wraps a `Seed.Token`, but it records that the
  token was *not* a clean match: an extraneous token that was deleted, a
  token discarded during panic-mode resynchronization, or a fabricated
  `<missing …>` token standing in for one that was inserted. Keeping these in
  the tree mirrors ANTLR's `ErrorNode`, so a recovered tree renders the same
  way the reference's `toStringTree` does.
  """

  alias Seed.Token

  @type t :: %__MODULE__{symbol: Token.t()}

  @enforce_keys [:symbol]
  defstruct [:symbol]

  @doc "Wraps `token` as an error node."
  @spec new(Token.t()) :: t()
  def new(%Token{} = token), do: %__MODULE__{symbol: token}
end
