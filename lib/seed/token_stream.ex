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

      iex> tokens = [Seed.Token.new(4, text: "if"), Seed.Token.eof_token()]
      iex> s = Seed.TokenStream.new(tokens)
      iex> Seed.TokenStream.la(s, 1)
      4
      iex> s = Seed.TokenStream.consume(s)
      iex> Seed.TokenStream.la(s, 1)
      -1
  """

  alias Seed.Token

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
    %__MODULE__{tokens: buffer, size: tuple_size(buffer), index: 0}
  end

  @doc """
  Builds a token stream by running `lexer` to completion.

  Tokenizes the lexer's entire input (the resulting list ends with EOF) and
  buffers it, giving a lexer-to-parser pipeline. Skipped tokens never reach
  the stream because the lexer drops them while matching.
  """
  @spec from_lexer(Seed.Lexer.t()) :: t()
  def from_lexer(%Seed.Lexer{} = lexer), do: lexer |> Seed.Lexer.tokenize() |> new()

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

  def lt(%__MODULE__{index: index} = stream, k) when is_integer(k) and k < 0 do
    pos = index + k
    if pos < 0, do: nil, else: get(stream, pos)
  end

  def lt(%__MODULE__{index: index, size: size} = stream, k) when is_integer(k) and k > 0 do
    pos = index + k - 1
    if pos >= size, do: eof_token(stream), else: get(stream, pos)
  end

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

  def consume(%__MODULE__{index: index} = stream) do
    %{stream | index: index + 1}
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
