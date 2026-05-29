defmodule Seed.CharStream do
  @moduledoc """
  An immutable character input stream over a UTF-8 binary.

  The stream is a sequence of Unicode code points with a current position.
  Lookahead (`la/2`) inspects code points relative to the position without
  moving it; `consume/1` advances the position and returns the updated
  stream. Because the stream is a value, `mark/1` is simply the current
  index and `seek/2` returns to any earlier or later position — no marker
  bookkeeping is required.

  Lookahead and slicing use the same conventions as the reference ANTLR4
  runtime: `la/2` returns `Seed.Token.eof/0` past the ends, positions are
  0-based, and intervals are inclusive.

      iex> s = Seed.CharStream.new("ab")
      iex> Seed.CharStream.la(s, 1)
      ?a
      iex> s = Seed.CharStream.consume(s)
      iex> Seed.CharStream.la(s, 1)
      ?b
      iex> Seed.CharStream.la(s, 2)
      -1

  Use `text/1` for the whole stream and `text/3` for an interval.
  """

  alias Seed.Token

  @type t :: %__MODULE__{
          data: tuple(),
          size: non_neg_integer(),
          index: non_neg_integer(),
          name: String.t()
        }

  defstruct data: {}, size: 0, index: 0, name: "<unknown>"

  @doc """
  Builds a stream from a UTF-8 `binary`.

  Supported options:

    * `:name` — a source name used in diagnostics (default `"<unknown>"`).
  """
  @spec new(binary(), keyword()) :: t()
  def new(binary, opts \\ []) when is_binary(binary) and is_list(opts) do
    data = binary |> String.to_charlist() |> List.to_tuple()

    %__MODULE__{
      data: data,
      size: tuple_size(data),
      index: 0,
      name: Keyword.get(opts, :name, "<unknown>")
    }
  end

  @doc "The current 0-based position in the stream."
  @spec index(t()) :: non_neg_integer()
  def index(%__MODULE__{index: index}), do: index

  @doc "The total number of code points in the stream."
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{size: size}), do: size

  @doc "The source name of the stream."
  @spec name(t()) :: String.t()
  def name(%__MODULE__{name: name}), do: name

  @doc """
  Returns the code point at lookahead offset `i` without moving.

  `i > 0` looks ahead (`la(s, 1)` is the current code point), `i < 0`
  looks back (`la(s, -1)` is the previous code point). `la(s, 0)` is
  undefined and returns `0`. Reading past either end returns
  `Seed.Token.eof/0`.
  """
  @spec la(t(), integer()) :: integer()
  def la(%__MODULE__{}, 0), do: 0

  def la(%__MODULE__{data: data, size: size, index: index}, i) when is_integer(i) do
    offset = if i < 0, do: i + 1, else: i
    pos = index + offset - 1

    if pos < 0 or pos >= size do
      Token.eof()
    else
      elem(data, pos)
    end
  end

  @doc """
  Advances the position by one and returns the updated stream.

  Raises if the stream is already at end of input, mirroring the reference
  runtime's refusal to consume past EOF.
  """
  @spec consume(t()) :: t()
  def consume(%__MODULE__{index: index, size: size}) when index >= size do
    raise ArgumentError, "cannot consume EOF"
  end

  def consume(%__MODULE__{index: index} = stream) do
    %{stream | index: index + 1}
  end

  @doc """
  Returns a marker for the current position.

  The marker is the current index; pass it to `release/2` (a no-op that
  returns the stream unchanged) or to `seek/2` to return to it.
  """
  @spec mark(t()) :: non_neg_integer()
  def mark(%__MODULE__{index: index}), do: index

  @doc "Releases a marker. The stream is a value, so this is a no-op."
  @spec release(t(), non_neg_integer()) :: t()
  def release(%__MODULE__{} = stream, _marker), do: stream

  @doc """
  Moves the position to `pos`, clamped to `[0, size]`.

      iex> s = Seed.CharStream.new("abc")
      iex> s = Seed.CharStream.seek(s, 2)
      iex> Seed.CharStream.la(s, 1)
      ?c
  """
  @spec seek(t(), integer()) :: t()
  def seek(%__MODULE__{size: size} = stream, pos) when is_integer(pos) do
    %{stream | index: pos |> max(0) |> min(size)}
  end

  @doc """
  Returns the text between the inclusive 0-based offsets `start` and `stop`.

  `stop` is clamped to the last index. An empty or out-of-range interval
  yields `""`, matching the reference runtime.

      iex> s = Seed.CharStream.new("hello")
      iex> Seed.CharStream.text(s, 1, 3)
      "ell"
  """
  @spec text(t(), integer(), integer()) :: binary()
  def text(%__MODULE__{data: data, size: size}, start, stop)
      when is_integer(start) and is_integer(stop) do
    stop = min(stop, size - 1)

    if start >= size or start > stop do
      ""
    else
      start..stop
      |> Enum.map(&elem(data, &1))
      |> List.to_string()
    end
  end

  @doc "Returns the entire stream contents as a binary."
  @spec text(t()) :: binary()
  def text(%__MODULE__{size: 0}), do: ""
  def text(%__MODULE__{size: size} = stream), do: text(stream, 0, size - 1)
end
