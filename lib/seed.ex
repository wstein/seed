defmodule Seed do
  @moduledoc """
  Seed is an ANTLR4 parser runtime for the BEAM, written in idiomatic Elixir.

  The runtime is built bottom-up. The currently available building blocks
  are the lexical primitives:

    * `Seed.Token` — a lexical token and the well-known token-type constants.
    * `Seed.Vocabulary` — the mapping from token types to readable names.
    * `Seed.CharStream` — an immutable character input stream.
    * `Seed.TokenStream` — an in-memory token buffer with lookahead.

  See the architecture documentation under `docs/` for the design and the
  roadmap toward the ATN simulators and code generation.
  """

  @version Mix.Project.config()[:version]

  @doc """
  Returns the Seed version string.

      iex> Seed.version() |> is_binary()
      true
  """
  @spec version() :: String.t()
  def version, do: @version
end
