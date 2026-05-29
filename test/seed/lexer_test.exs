defmodule Seed.LexerTest do
  use ExUnit.Case, async: true

  alias Seed.ATNDeserializer
  alias Seed.CharStream
  alias Seed.Lexer
  alias Seed.Token
  alias Seed.TokenStream

  @atn_dir Path.expand("../fixtures/atn", __DIR__)
  @lex_dir Path.expand("../fixtures/lex", __DIR__)
  @fixtures ~w(hello expr cover)

  # Each grammar's lexer tokenizes its sample input to exactly the token
  # stream the canonical ANTLR4 lexer produces (see test/fixtures/lex).
  for name <- @fixtures do
    test "#{name}: tokenization matches the reference lexer" do
      name = unquote(name)
      assert Enum.map(tokenize(name), &token_map/1) == oracle(name)
    end
  end

  test "next_token/1 keeps returning EOF past the end" do
    lexer = build_lexer("hello")
    tokens = Stream.iterate(Lexer.next_token(lexer), fn {_t, l} -> Lexer.next_token(l) end)

    eofs =
      tokens
      |> Stream.map(fn {token, _lexer} -> token end)
      |> Stream.drop_while(&(&1.type != Seed.Token.eof()))
      |> Enum.take(3)

    assert Enum.all?(eofs, &(&1.type == Seed.Token.eof()))
  end

  test "TokenStream.from_lexer/1 builds a parser-ready stream" do
    # hello.input is "hello world\nhello abc" -> hello, world, hello, abc, EOF
    stream = "hello" |> build_lexer() |> TokenStream.from_lexer()

    assert TokenStream.size(stream) == 5
    assert TokenStream.la(stream, 1) == 1
    assert TokenStream.lt(stream, 2).text == "world"
    assert TokenStream.get(stream, TokenStream.size(stream) - 1).type == Token.eof()
  end

  defp tokenize(name), do: name |> build_lexer() |> Lexer.tokenize()

  defp build_lexer(name) do
    Lexer.new(load_lexer_atn(name), load_input(name))
  end

  defp load_lexer_atn(name) do
    @atn_dir
    |> Path.join(name <> "_lexer.atn")
    |> File.read!()
    |> String.trim()
    |> String.split(",")
    |> Enum.map(&String.to_integer/1)
    |> ATNDeserializer.deserialize!()
  end

  defp load_input(name) do
    @lex_dir |> Path.join(name <> ".input") |> File.read!() |> CharStream.new()
  end

  defp oracle(name) do
    @lex_dir |> Path.join(name <> ".tokens.json") |> File.read!() |> JSON.decode!()
  end

  defp token_map(token) do
    %{
      "type" => token.type,
      "text" => token.text,
      "line" => token.line,
      "column" => token.column,
      "start" => token.start,
      "stop" => token.stop,
      "channel" => token.channel
    }
  end
end
