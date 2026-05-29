defmodule Seed.TokenTest do
  use ExUnit.Case, async: true
  doctest Seed.Token

  alias Seed.Token

  describe "constants" do
    test "expose the reference token-type and channel values" do
      assert Token.eof() == -1
      assert Token.invalid_type() == 0
      assert Token.epsilon() == -2
      assert Token.min_user_token_type() == 1
      assert Token.default_channel() == 0
      assert Token.hidden_channel() == 1
    end
  end

  describe "new/2" do
    test "defaults match the reference runtime" do
      token = Token.new(5)

      assert token.type == 5
      assert token.text == nil
      assert token.line == 0
      assert token.column == -1
      assert token.channel == Token.default_channel()
      assert token.start == -1
      assert token.stop == -1
      assert token.index == -1
    end

    test "applies the given options" do
      token = Token.new(4, text: "if", line: 2, column: 3, start: 10, stop: 11, index: 7)

      assert token.text == "if"
      assert token.line == 2
      assert token.column == 3
      assert token.start == 10
      assert token.stop == 11
      assert token.index == 7
    end

    test "requires an integer type" do
      assert_raise FunctionClauseError, fn -> Token.new("not-an-int") end
    end
  end

  describe "eof_token/1" do
    test "marks the type as EOF and positions start/stop" do
      token = Token.eof_token(42)

      assert token.type == Token.eof()
      assert token.start == 42
      assert token.stop == 42
      assert Token.eof?(token)
    end

    test "defaults the position to -1" do
      assert Token.eof_token().start == -1
    end
  end

  describe "text/1" do
    test "returns the stored text" do
      assert Token.text(Token.new(4, text: "while")) == "while"
    end

    test "returns nil when no text is present" do
      assert Token.text(Token.new(4)) == nil
    end
  end

  describe "eof?/1" do
    test "is true only for EOF tokens" do
      assert Token.eof?(Token.eof_token())
      refute Token.eof?(Token.new(Token.min_user_token_type()))
    end
  end
end
