defmodule Seed.TokenStreamTest do
  use ExUnit.Case, async: true
  doctest Seed.TokenStream

  alias Seed.Token
  alias Seed.TokenStream

  defp sample_stream do
    tokens = [
      Token.new(4, text: "if", index: 0),
      Token.new(5, text: "x", index: 1),
      Token.eof_token(2)
    ]

    {TokenStream.new(tokens), tokens}
  end

  describe "new/1" do
    test "records size and starts at index 0" do
      {stream, tokens} = sample_stream()

      assert TokenStream.size(stream) == length(tokens)
      assert TokenStream.index(stream) == 0
    end
  end

  describe "lt/2 and la/2" do
    setup do
      {stream, _tokens} = sample_stream()
      %{stream: stream}
    end

    test "lt(_, 1) is the current token", %{stream: stream} do
      assert %Token{type: 4, text: "if"} = TokenStream.lt(stream, 1)
      assert TokenStream.la(stream, 1) == 4
    end

    test "looks ahead", %{stream: stream} do
      assert TokenStream.la(stream, 2) == 5
    end

    test "lt(_, 0) is nil and la(_, 0) is EOF", %{stream: stream} do
      assert TokenStream.lt(stream, 0) == nil
      assert TokenStream.la(stream, 0) == Token.eof()
    end

    test "looks back after consuming", %{stream: stream} do
      stream = TokenStream.consume(stream)

      assert %Token{type: 4} = TokenStream.lt(stream, -1)
      assert TokenStream.la(stream, -1) == 4
    end

    test "returns nil/EOF looking back before the start", %{stream: stream} do
      assert TokenStream.lt(stream, -1) == nil
      assert TokenStream.la(stream, -1) == Token.eof()
    end

    test "returns the buffered EOF token past the end", %{stream: stream} do
      eof = TokenStream.lt(stream, 4)

      assert eof.type == Token.eof()
      assert eof.start == 2
      assert TokenStream.la(stream, 4) == Token.eof()
    end

    test "synthesizes EOF when the buffer has no trailing EOF" do
      stream = TokenStream.new([Token.new(4)])
      assert TokenStream.la(stream, 2) == Token.eof()
    end
  end

  describe "get/2" do
    test "returns the token at an absolute position" do
      {stream, _tokens} = sample_stream()
      assert %Token{type: 5, text: "x"} = TokenStream.get(stream, 1)
    end

    test "raises out of range" do
      {stream, _tokens} = sample_stream()
      assert_raise FunctionClauseError, fn -> TokenStream.get(stream, 99) end
    end
  end

  describe "consume/1" do
    test "advances the position" do
      {stream, _tokens} = sample_stream()
      assert TokenStream.index(TokenStream.consume(stream)) == 1
    end

    test "raises once past the last token" do
      stream = TokenStream.new([Token.new(4)]) |> TokenStream.consume()
      assert_raise ArgumentError, "cannot consume EOF", fn -> TokenStream.consume(stream) end
    end
  end

  describe "mark/1, release/2 and seek/2" do
    test "round-trips a position" do
      {stream, _tokens} = sample_stream()
      marker = TokenStream.mark(stream)
      moved = TokenStream.consume(stream)

      assert TokenStream.la(moved, 1) == 5

      restored = moved |> TokenStream.release(marker) |> TokenStream.seek(marker)
      assert TokenStream.la(restored, 1) == 4
    end

    test "clamps seek to the stream bounds" do
      {stream, _tokens} = sample_stream()

      assert TokenStream.index(TokenStream.seek(stream, -5)) == 0
      assert TokenStream.index(TokenStream.seek(stream, 99)) == 3
    end
  end
end
