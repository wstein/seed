defmodule Seed.TokenStreamRewriter do
  @moduledoc """
  Programmatic edits to a token stream, rendered back to text.

  A faithful, immutable analogue of the reference `TokenStreamRewriter`: it
  records insert/replace/delete operations against token positions and
  `text/1` produces the edited source. Every operation returns an updated
  rewriter, so edits compose with the pipe operator:

      rewriter =
        stream
        |> Seed.TokenStreamRewriter.new()
        |> Seed.TokenStreamRewriter.replace(2, "42")
        |> Seed.TokenStreamRewriter.insert_before(0, "let ")

      Seed.TokenStreamRewriter.text(rewriter)

  Positions are absolute token indices into the stream (as `Seed.TokenStream`
  uses with `get/2`), so they address *every* buffered token — including ones
  on a non-default channel — and rendering preserves them. Tokens the lexer
  dropped with `skip` are not in the buffer and cannot be reproduced.

  Replace and delete ranges must be disjoint; overlapping ranges raise
  `ArgumentError`. Inserts at a position covered by a replace are dropped (the
  replacement text wins), matching the reference's resolution.
  """

  alias Seed.Token
  alias Seed.TokenStream

  @eof Token.eof()

  @type t :: %__MODULE__{stream: TokenStream.t(), ops: [operation()]}
  @typep operation ::
           {:insert, non_neg_integer(), iodata()}
           | {:replace, non_neg_integer(), non_neg_integer(), iodata()}

  @enforce_keys [:stream]
  defstruct stream: nil, ops: []

  @doc "Builds a rewriter over `stream`."
  @spec new(TokenStream.t()) :: t()
  def new(%TokenStream{} = stream), do: %__MODULE__{stream: stream}

  @doc "Inserts `text` immediately before the token at `index`."
  @spec insert_before(t(), non_neg_integer(), iodata()) :: t()
  def insert_before(%__MODULE__{} = rewriter, index, text)
      when is_integer(index) and index >= 0 do
    add(rewriter, {:insert, index, text})
  end

  @doc "Inserts `text` immediately after the token at `index`."
  @spec insert_after(t(), non_neg_integer(), iodata()) :: t()
  def insert_after(%__MODULE__{} = rewriter, index, text) when is_integer(index) and index >= 0 do
    add(rewriter, {:insert, index + 1, text})
  end

  @doc "Replaces the tokens in `from..to` (inclusive) with `text`."
  @spec replace(t(), non_neg_integer(), non_neg_integer(), iodata()) :: t()
  def replace(%__MODULE__{} = rewriter, from, to, text)
      when is_integer(from) and is_integer(to) and from >= 0 and from <= to do
    add(rewriter, {:replace, from, to, text})
  end

  @doc "Replaces the single token at `index` with `text`."
  @spec replace(t(), non_neg_integer(), iodata()) :: t()
  def replace(%__MODULE__{} = rewriter, index, text) when is_integer(index) do
    replace(rewriter, index, index, text)
  end

  @doc "Deletes the tokens in `from..to` (inclusive)."
  @spec delete(t(), non_neg_integer(), non_neg_integer()) :: t()
  def delete(%__MODULE__{} = rewriter, from, to), do: replace(rewriter, from, to, "")

  @doc "Deletes the single token at `index`."
  @spec delete(t(), non_neg_integer()) :: t()
  def delete(%__MODULE__{} = rewriter, index) when is_integer(index),
    do: delete(rewriter, index, index)

  @doc "Renders the stream with every recorded edit applied."
  @spec text(t()) :: binary()
  def text(%__MODULE__{stream: stream, ops: ops}) do
    size = TokenStream.size(stream)
    inserts = collect_inserts(ops)
    replaces = collect_replaces(ops)

    0
    |> render(size, stream, inserts, replaces, [])
    |> IO.iodata_to_binary()
  end

  defp add(%__MODULE__{ops: ops} = rewriter, op), do: %{rewriter | ops: ops ++ [op]}

  # Each index maps to the texts inserted before it, in the order added.
  defp collect_inserts(ops) do
    Enum.reduce(ops, %{}, fn
      {:insert, index, text}, acc -> Map.update(acc, index, [text], &(&1 ++ [text]))
      _replace, acc -> acc
    end)
  end

  # Each range's start maps to its end and replacement text (a later replace at
  # the same start wins). Ranges must be disjoint.
  defp collect_replaces(ops) do
    replaces =
      Enum.reduce(ops, %{}, fn
        {:replace, from, to, text}, acc -> Map.put(acc, from, {to, text})
        _insert, acc -> acc
      end)

    if overlapping?(replaces) do
      raise ArgumentError, "overlapping replace/delete operations"
    end

    replaces
  end

  defp overlapping?(replaces) do
    replaces
    |> Enum.map(fn {from, {to, _text}} -> {from, to} end)
    |> Enum.sort()
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(fn [{_from1, to1}, {from2, _to2}] -> from2 <= to1 end)
  end

  defp render(index, size, _stream, inserts, _replaces, acc) when index >= size do
    [acc | List.wrap(Map.get(inserts, index, []))]
  end

  defp render(index, size, stream, inserts, replaces, acc) do
    acc = [acc, Map.get(inserts, index, [])]

    case Map.get(replaces, index) do
      {to, text} ->
        # Jump past the replaced span, dropping any inserts inside it.
        render(to + 1, size, stream, inserts, replaces, [acc, text])

      nil ->
        token = TokenStream.get(stream, index)
        render(index + 1, size, stream, inserts, replaces, [acc, token_text(token)])
    end
  end

  # The EOF token carries a "<EOF>" sentinel text but contributes nothing to
  # the rendered source.
  defp token_text(%Token{type: @eof}), do: ""
  defp token_text(%Token{text: text}), do: text || ""
end
