defmodule Seed.LexerTest do
  use ExUnit.Case, async: true

  alias Seed.ATNDeserializer
  alias Seed.CharStream
  alias Seed.Interp
  alias Seed.Lexer
  alias Seed.Token
  alias Seed.TokenStream
  alias Seed.Vocabulary

  @atn_dir Path.expand("../fixtures/atn", __DIR__)
  @interp_dir Path.expand("../fixtures/interp", __DIR__)
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
    assert {:ok, stream} = "hello" |> build_lexer() |> TokenStream.from_lexer()

    assert TokenStream.size(stream) == 5
    assert TokenStream.la(stream, 1) == 1
    assert TokenStream.lt(stream, 2).text == "world"
    assert TokenStream.get(stream, TokenStream.size(stream) - 1).type == Token.eof()
  end

  test "tokenize/1 returns a diagnostic for an unmatched character" do
    lexer = Lexer.new(load_lexer_atn("hello"), CharStream.new("@"))

    assert {:error, [%Seed.Diagnostic{code: :no_viable_token, severity: :error}]} =
             Lexer.tokenize(lexer)
  end

  test "a lexer semantic predicate selects which rule wins" do
    grammar = Interp.load!(Path.join(@interp_dir, "LexPred.interp"))
    # KEYWORD and WORD both match "abc"; the `{keyword}?` predicate on KEYWORD
    # decides between them.
    first_token = fn lexer ->
      {:ok, [token | _]} = Lexer.tokenize(lexer)
      Vocabulary.display_name(grammar.vocabulary, token.type)
    end

    # Default: the predicate is satisfied, so KEYWORD (the earlier rule) wins.
    assert first_token.(Lexer.new(grammar.atn, CharStream.new("abc"))) == "KEYWORD"

    # A false predicate prunes KEYWORD, leaving WORD.
    pruned = Lexer.new(grammar.atn, CharStream.new("abc"), fn _rule, _pred -> false end)
    assert first_token.(pruned) == "WORD"
  end

  defp tokenize(name) do
    {:ok, tokens} = name |> build_lexer() |> Lexer.tokenize()
    tokens
  end

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
