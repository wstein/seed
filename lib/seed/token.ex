defmodule Seed.Token do
  @moduledoc """
  A lexical token produced by a lexer and consumed by a parser.

  A token records its integer `type`, the matched `text`, its position in
  the source (1-based `line`, 0-based `column`, and the 0-based inclusive
  character offsets `start`/`stop`), the `channel` it belongs to, and its
  `index` within the owning token stream.

  The well-known token-type and channel constants mirror the reference
  ANTLR4 runtime and are exposed as functions so they can be used from
  other modules:

      iex> Seed.Token.eof()
      -1

      iex> Seed.Token.default_channel()
      0
  """

  @eof -1
  @invalid_type 0
  @epsilon -2
  @min_user_token_type 1

  @default_channel 0
  @hidden_channel 1

  @type type :: integer()

  @type t :: %__MODULE__{
          type: type(),
          text: String.t() | nil,
          line: non_neg_integer(),
          column: integer(),
          channel: non_neg_integer(),
          start: integer(),
          stop: integer(),
          index: integer()
        }

  @enforce_keys [:type]
  defstruct type: nil,
            text: nil,
            line: 0,
            column: -1,
            channel: @default_channel,
            start: -1,
            stop: -1,
            index: -1

  @doc "The token type representing end of input."
  @spec eof() :: type()
  def eof, do: @eof

  @doc "The token type assigned to an invalid or uninitialized token."
  @spec invalid_type() :: type()
  def invalid_type, do: @invalid_type

  @doc "The pseudo token type used for epsilon (empty) transitions."
  @spec epsilon() :: type()
  def epsilon, do: @epsilon

  @doc "The smallest token type available to user-defined tokens."
  @spec min_user_token_type() :: type()
  def min_user_token_type, do: @min_user_token_type

  @doc "The channel on which tokens are delivered to the parser by default."
  @spec default_channel() :: non_neg_integer()
  def default_channel, do: @default_channel

  @doc "The conventional channel for hidden tokens such as whitespace."
  @spec hidden_channel() :: non_neg_integer()
  def hidden_channel, do: @hidden_channel

  @doc """
  Builds a token of `type` with the given options.

  Options map directly to struct fields: `:text`, `:line`, `:column`,
  `:channel`, `:start`, `:stop`, and `:index`.

      iex> Seed.Token.new(4, text: "if", line: 1, column: 0)
      %Seed.Token{type: 4, text: "if", line: 1, column: 0, channel: 0, start: -1, stop: -1, index: -1}
  """
  @spec new(type(), keyword()) :: t()
  def new(type, opts \\ []) when is_integer(type) and is_list(opts) do
    struct(%__MODULE__{type: type}, opts)
  end

  @doc """
  Builds an end-of-input token positioned at `start`.

  The token's `start` and `stop` are set to `start`, matching how the
  reference runtime emits EOF at the final input offset.

      iex> Seed.Token.eof_token(7)
      %Seed.Token{type: -1, text: nil, line: 0, column: -1, channel: 0, start: 7, stop: 7, index: -1}
  """
  @spec eof_token(integer()) :: t()
  def eof_token(start \\ -1) when is_integer(start) do
    %__MODULE__{type: @eof, start: start, stop: start}
  end

  @doc """
  Returns the token's text, or `nil` when it carries none.

  A lexer sets `:text` for every token it emits. A token created without
  text (for example a synthetic EOF) reports `nil`.

      iex> Seed.Token.text(Seed.Token.new(4, text: "if"))
      "if"

      iex> Seed.Token.text(Seed.Token.eof_token())
      nil
  """
  @spec text(t()) :: String.t() | nil
  def text(%__MODULE__{text: text}), do: text

  @doc """
  Returns `true` when the token marks end of input.

      iex> Seed.Token.eof?(Seed.Token.eof_token())
      true

      iex> Seed.Token.eof?(Seed.Token.new(4))
      false
  """
  @spec eof?(t()) :: boolean()
  def eof?(%__MODULE__{type: @eof}), do: true
  def eof?(%__MODULE__{}), do: false
end
