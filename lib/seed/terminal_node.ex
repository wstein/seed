defmodule Seed.TerminalNode do
  @moduledoc """
  A leaf in the parse tree, wrapping the matched `Seed.Token`.
  """

  alias Seed.Token

  @type t :: %__MODULE__{symbol: Token.t()}

  @enforce_keys [:symbol]
  defstruct [:symbol]

  @doc "Wraps `token` as a terminal node."
  @spec new(Token.t()) :: t()
  def new(%Token{} = token), do: %__MODULE__{symbol: token}
end
