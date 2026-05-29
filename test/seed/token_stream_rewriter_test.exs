defmodule Seed.TokenStreamRewriterTest do
  use ExUnit.Case, async: true

  alias Seed.CharStream
  alias Seed.Interp
  alias Seed.Lexer
  alias Seed.TokenStream
  alias Seed.TokenStreamRewriter, as: Rewriter

  @interp_dir Path.expand("../fixtures/interp", __DIR__)

  # "x = 1 ;" -> tokens x(0) =(1) 1(2) ;(3) EOF(4); the lexer skips whitespace,
  # so it is not in the buffer and not reproduced.
  defp rewriter(input) do
    grammar = Interp.load!(Path.join(@interp_dir, "ExprLexer.interp"))
    {:ok, stream} = grammar.atn |> Lexer.new(CharStream.new(input)) |> TokenStream.from_lexer()
    Rewriter.new(stream)
  end

  test "renders the original tokens unchanged" do
    assert "x = 1 ;" |> rewriter() |> Rewriter.text() == "x=1;"
  end

  test "insert_before/3 and insert_after/3" do
    assert "x = 1 ;" |> rewriter() |> Rewriter.insert_before(0, "let ") |> Rewriter.text() ==
             "let x=1;"

    assert "x = 1 ;" |> rewriter() |> Rewriter.insert_after(3, " // c") |> Rewriter.text() ==
             "x=1; // c"
  end

  test "replace/3 and delete/2" do
    assert "x = 1 ;" |> rewriter() |> Rewriter.replace(2, "42") |> Rewriter.text() == "x=42;"
    assert "x = 1 ;" |> rewriter() |> Rewriter.delete(1) |> Rewriter.text() == "x1;"

    assert "x = 1 ;" |> rewriter() |> Rewriter.replace(0, 2, "y") |> Rewriter.text() == "y;"
  end

  test "composes multiple edits" do
    result =
      "x = 1 ;"
      |> rewriter()
      |> Rewriter.insert_before(0, "(")
      |> Rewriter.replace(2, "9")
      |> Rewriter.insert_after(3, " )")
      |> Rewriter.text()

    assert result == "(x=9; )"
  end

  test "an insert inside a replaced range is dropped" do
    result =
      "x = 1 ;"
      |> rewriter()
      |> Rewriter.replace(0, 2, "Z")
      |> Rewriter.insert_before(1, "ignored")
      |> Rewriter.text()

    assert result == "Z;"
  end

  test "overlapping replace ranges raise" do
    r = "x = 1 ;" |> rewriter() |> Rewriter.replace(0, 2, "a") |> Rewriter.replace(1, 3, "b")
    assert_raise ArgumentError, ~r/overlapping/, fn -> Rewriter.text(r) end
  end

  test "includes tokens on a non-default channel" do
    lexer = Interp.load!(Path.join(@interp_dir, "HiddenLexer.interp"))
    {:ok, stream} = lexer.atn |> Lexer.new(CharStream.new("a #c\nb")) |> TokenStream.from_lexer()

    # The hidden comment stays in the buffer, so the rewriter reproduces it
    # (the whitespace was skipped, so it is gone).
    assert stream |> Rewriter.new() |> Rewriter.text() == "a#cb"
  end
end
