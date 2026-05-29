defmodule Seed.Diagnostic do
  @moduledoc """
  A structured problem reported while lexing or parsing.

  Instead of raising strings, Seed surfaces failures as `Seed.Diagnostic`
  values carrying a machine-readable `code`, a `severity`, the source
  position (`line`, 1-based; `column`, 0-based), and a human-readable
  `message`. The lexer and parser return `{:error, [t()]}` at their public
  boundaries, which suits tooling (editors, language servers) and pairs with
  error recovery later.
  """

  @type severity :: :error | :warning | :info

  @type code ::
          :token_mismatch
          | :input_mismatch
          | :extraneous_input
          | :missing_token
          | :no_viable_alternative
          | :no_viable_token

  @type t :: %__MODULE__{
          code: code(),
          severity: severity(),
          line: pos_integer() | nil,
          column: non_neg_integer() | nil,
          message: String.t()
        }

  @enforce_keys [:code, :severity, :message]
  defstruct [:code, :severity, :line, :column, :message]

  @doc """
  Builds an `:error`-severity diagnostic.

  Options set the source position: `:line` and `:column`.

      iex> d = Seed.Diagnostic.error(:token_mismatch, "expected ';'", line: 2, column: 4)
      iex> {d.code, d.severity, d.line, d.column}
      {:token_mismatch, :error, 2, 4}
  """
  @spec error(code(), String.t(), keyword()) :: t()
  def error(code, message, opts \\ []) do
    %__MODULE__{
      code: code,
      severity: :error,
      message: message,
      line: Keyword.get(opts, :line),
      column: Keyword.get(opts, :column)
    }
  end
end
