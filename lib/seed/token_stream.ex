defmodule Seed.TokenStream do
  @moduledoc """
  An in-memory buffer of tokens with positional lookahead.

  A token stream is the bridge between a lexer's output and a parser's
  input: it holds an ordered list of `Seed.Token` values and a current
  position. `lt/2` returns the token at a lookahead offset, `la/2` returns
  that token's type, and `consume/1` advances the position.

  Lookahead conventions follow the reference ANTLR4 runtime: `lt(s, 1)` is
  the current token, `lt(s, -1)` is the previous one, and `lt(s, 0)` is
  `nil`. Reading forward past the end yields the EOF token.

  Like the reference `CommonTokenStream`, navigation is *channel-aware*:
  `lt/2`, `la/2`, and `consume/1` skip tokens that are not on the default
  channel (those a grammar routes elsewhere with `channel(...)`, e.g.
  comments or whitespace sent to `HIDDEN` instead of being `skip`-ed). The
  off-channel tokens remain in the buffer, addressable by absolute position
  with `get/2`, so tooling can still see them.

      iex> tokens = [Seed.Token.new(4, text: "if"), Seed.Token.eof_token()]
      iex> s = Seed.TokenStream.new(tokens)
      iex> Seed.TokenStream.la(s, 1)
      4
      iex> s = Seed.TokenStream.consume(s)
      iex> Seed.TokenStream.la(s, 1)
      -1
  """

  alias Seed.Token

  @eof Token.eof()
  @default_channel Token.default_channel()

  @type t :: %__MODULE__{
          tokens: tuple(),
          size: non_neg_integer(),
          index: non_neg_integer()
        }

  defstruct tokens: {}, size: 0, index: 0

  @doc "Builds a token stream from a list of `Seed.Token` values."
  @spec new([Token.t()]) :: t()
  def new(tokens) when is_list(tokens) do
    buffer = List.to_tuple(tokens)
    stream = %__MODULE__{tokens: buffer, size: tuple_size(buffer), index: 0}
    # Position on the first on-channel token, as the parser only ever sees
    # on-channel tokens.
    %{stream | index: next_on_channel(stream, 0)}
  end

  @doc """
  Builds a token stream by running `lexer` to completion.

  Returns `{:ok, stream}` over the lexer's tokens (skipped tokens never
  reach the stream), or `{:error, [Seed.Diagnostic.t()]}` if lexing fails.
  """
  @spec from_lexer(Seed.Lexer.t()) :: {:ok, t()} | {:error, [Seed.Diagnostic.t()]}
  def from_lexer(%Seed.Lexer{} = lexer) do
    with {:ok, tokens} <- Seed.Lexer.tokenize(lexer), do: {:ok, new(tokens)}
  end

  @doc "The current 0-based position in the stream."
  @spec index(t()) :: non_neg_integer()
  def index(%__MODULE__{index: index}), do: index

  @doc "The total number of tokens in the stream."
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{size: size}), do: size

  @doc """
  Returns the token at absolute position `i`.

  Raises when `i` is out of range; use `lt/2` for relative, EOF-tolerant
  lookahead.
  """
  @spec get(t(), non_neg_integer()) :: Token.t()
  def get(%__MODULE__{tokens: tokens, size: size}, i)
      when is_integer(i) and i >= 0 and i < size do
    elem(tokens, i)
  end

  @doc """
  Returns the token at lookahead offset `k`.

  `k > 0` looks ahead, `k < 0` looks back, and `k == 0` returns `nil`.
  Looking forward past the last token returns the EOF token; looking back
  before the start returns `nil`.
  """
  @spec lt(t(), integer()) :: Token.t() | nil
  def lt(%__MODULE__{}, 0), do: nil

  def lt(%__MODULE__{} = stream, k) when is_integer(k) and k < 0 do
    case step_back(stream, stream.index, -k) do
      pos when pos < 0 -> nil
      pos -> get(stream, pos)
    end
  end

  def lt(%__MODULE__{size: size} = stream, k) when is_integer(k) and k > 0 do
    case step_forward(stream, stream.index, k - 1) do
      pos when pos >= size -> eof_token(stream)
      pos -> get(stream, pos)
    end
  end

  # Walks `n` on-channel tokens forward from `pos` (which is itself
  # on-channel). Landing past the end stays past the end (EOF).
  defp step_forward(_stream, pos, 0), do: pos

  defp step_forward(stream, pos, n),
    do: step_forward(stream, next_on_channel(stream, pos + 1), n - 1)

  # Walks `n` on-channel tokens back from `pos`; a negative result means there
  # is no such token.
  defp step_back(_stream, pos, 0), do: pos

  defp step_back(stream, pos, n),
    do: step_back(stream, previous_on_channel(stream, pos - 1), n - 1)

  @doc """
  Returns the type of the token at lookahead offset `k`.

  Returns `Seed.Token.eof/0` when there is no token at that offset.
  """
  @spec la(t(), integer()) :: Token.type()
  def la(%__MODULE__{} = stream, k) when is_integer(k) do
    case lt(stream, k) do
      nil -> Token.eof()
      %Token{type: type} -> type
    end
  end

  @doc """
  Advances the position by one and returns the updated stream.

  Raises when already positioned at end of input, mirroring the reference
  runtime's refusal to consume past EOF.
  """
  @spec consume(t()) :: t()
  def consume(%__MODULE__{index: index, size: size}) when index >= size do
    raise ArgumentError, "cannot consume EOF"
  end

  def consume(%__MODULE__{} = stream) do
    %{stream | index: next_on_channel(stream, stream.index + 1)}
  end

  @doc "Returns a marker for the current position (the current index)."
  @spec mark(t()) :: non_neg_integer()
  def mark(%__MODULE__{index: index}), do: index

  @doc "Releases a marker. The stream is a value, so this is a no-op."
  @spec release(t(), non_neg_integer()) :: t()
  def release(%__MODULE__{} = stream, _marker), do: stream

  @doc "Moves the position to `pos`, clamped to `[0, size]`."
  @spec seek(t(), integer()) :: t()
  def seek(%__MODULE__{size: size} = stream, pos) when is_integer(pos) do
    %{stream | index: pos |> max(0) |> min(size)}
  end

  # The position of the first on-channel token at or after `pos`, or `size`
  # when none remains. EOF is always on-channel, so a non-empty stream always
  # resolves to a real position.
  defp next_on_channel(%__MODULE__{size: size}, pos) when pos >= size, do: size

  defp next_on_channel(%__MODULE__{} = stream, pos) do
    if on_channel?(get(stream, pos)), do: pos, else: next_on_channel(stream, pos + 1)
  end

  # The position of the last on-channel token at or before `pos`, or `-1`.
  defp previous_on_channel(%__MODULE__{}, pos) when pos < 0, do: -1

  defp previous_on_channel(%__MODULE__{} = stream, pos) do
    if on_channel?(get(stream, pos)), do: pos, else: previous_on_channel(stream, pos - 1)
  end

  defp on_channel?(%Token{type: @eof}), do: true
  defp on_channel?(%Token{channel: channel}), do: channel == @default_channel

  # Returns the buffer's trailing EOF token when present, otherwise a
  # synthetic one, so forward lookahead past the end is well defined.
  defp eof_token(%__MODULE__{tokens: {}}), do: Token.eof_token()

  defp eof_token(%__MODULE__{tokens: tokens, size: size}) do
    case elem(tokens, size - 1) do
      %Token{type: -1} = last -> last
      _other -> Token.eof_token()
    end
  end
end
