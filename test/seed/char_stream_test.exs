defmodule Seed.CharStreamTest do
  use ExUnit.Case, async: true
  doctest Seed.CharStream

  alias Seed.CharStream
  alias Seed.Token

  describe "new/2" do
    test "records size and starts at index 0" do
      stream = CharStream.new("hello")

      assert CharStream.size(stream) == 5
      assert CharStream.index(stream) == 0
      assert CharStream.name(stream) == "<unknown>"
    end

    test "counts unicode code points, not bytes" do
      assert CharStream.size(CharStream.new("héllo")) == 5
    end

    test "accepts a source name" do
      assert CharStream.name(CharStream.new("x", name: "input.g4")) == "input.g4"
    end

    test "handles the empty stream" do
      stream = CharStream.new("")

      assert CharStream.size(stream) == 0
      assert CharStream.la(stream, 1) == Token.eof()
      assert CharStream.text(stream) == ""
    end
  end

  describe "la/2" do
    setup do
      %{stream: CharStream.new("abc")}
    end

    test "looks ahead from the current position", %{stream: stream} do
      assert CharStream.la(stream, 1) == ?a
      assert CharStream.la(stream, 2) == ?b
      assert CharStream.la(stream, 3) == ?c
    end

    test "returns EOF past the end", %{stream: stream} do
      assert CharStream.la(stream, 4) == Token.eof()
    end

    test "la(_, 0) is undefined and returns 0", %{stream: stream} do
      assert CharStream.la(stream, 0) == 0
    end

    test "looks backward after consuming", %{stream: stream} do
      stream = stream |> CharStream.consume() |> CharStream.consume()

      assert CharStream.la(stream, -1) == ?b
      assert CharStream.la(stream, -2) == ?a
    end

    test "returns EOF before the start", %{stream: stream} do
      assert CharStream.la(stream, -1) == Token.eof()
    end
  end

  describe "consume/1" do
    test "advances the position" do
      stream = CharStream.new("ab") |> CharStream.consume()
      assert CharStream.index(stream) == 1
    end

    test "raises at end of input" do
      stream = CharStream.new("a") |> CharStream.consume()
      assert_raise ArgumentError, "cannot consume EOF", fn -> CharStream.consume(stream) end
    end
  end

  describe "mark/1, release/2 and seek/2" do
    test "round-trips a position via a marker" do
      stream = CharStream.new("abc")
      marker = CharStream.mark(stream)
      moved = stream |> CharStream.consume() |> CharStream.consume()

      assert CharStream.la(moved, 1) == ?c

      restored = moved |> CharStream.release(marker) |> CharStream.seek(marker)
      assert CharStream.la(restored, 1) == ?a
    end

    test "clamps seek to the stream bounds" do
      stream = CharStream.new("abc")

      assert CharStream.index(CharStream.seek(stream, -5)) == 0
      assert CharStream.index(CharStream.seek(stream, 99)) == 3
    end
  end

  describe "text/3" do
    setup do
      %{stream: CharStream.new("hello")}
    end

    test "returns an inclusive interval", %{stream: stream} do
      assert CharStream.text(stream, 1, 3) == "ell"
    end

    test "clamps stop to the last index", %{stream: stream} do
      assert CharStream.text(stream, 3, 99) == "lo"
    end

    test "returns empty for an out-of-range or inverted interval", %{stream: stream} do
      assert CharStream.text(stream, 99, 100) == ""
      assert CharStream.text(stream, 3, 1) == ""
    end
  end

  describe "text/1" do
    test "returns the whole stream regardless of position" do
      stream = CharStream.new("hello") |> CharStream.consume()
      assert CharStream.text(stream) == "hello"
    end
  end
end
