defmodule Seed.ATN.LexerActionExecutor do
  @moduledoc """
  An ordered list of lexer actions accumulated while matching a token.

  During ATN simulation, action transitions append `Seed.ATN.LexerAction`
  values to a config's executor. When the token is accepted, the lexer
  runs the actions in order (see `Seed.Lexer`), which is how commands like
  `skip`, `channel(HIDDEN)`, and `type(X)` take effect.

  The executor is an immutable value; `append/2` returns a new one.
  """

  alias Seed.ATN.LexerAction

  @type t :: %__MODULE__{actions: [LexerAction.t()]}

  defstruct actions: []

  @doc "An executor with no actions."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Returns a new executor with `action` appended.

  Accepts `nil` as the starting executor for the common case of a config
  that has not yet accumulated any actions.
  """
  @spec append(t() | nil, LexerAction.t()) :: t()
  def append(nil, %LexerAction{} = action), do: %__MODULE__{actions: [action]}

  def append(%__MODULE__{actions: actions}, %LexerAction{} = action) do
    %__MODULE__{actions: actions ++ [action]}
  end

  @doc "Returns the actions in execution order."
  @spec actions(t() | nil) :: [LexerAction.t()]
  def actions(nil), do: []
  def actions(%__MODULE__{actions: actions}), do: actions
end
