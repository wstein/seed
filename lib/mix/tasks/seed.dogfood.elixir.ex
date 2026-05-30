defmodule Mix.Tasks.Seed.Dogfood.Elixir do
  @shortdoc "Parse Elixir source with the vendored Elixir grammar via Seed"

  @moduledoc """
  Runs Seed over Elixir source files using the vendored ANTLR Elixir grammar
  (`test/fixtures/interp/Elixir{Parser,Lexer}.interp`), reporting how many
  parse cleanly. By default it dogfoods Seed on its *own* runtime
  (`lib/**/*.ex`).

      mix seed.dogfood.elixir              # parse lib/**/*.ex
      mix seed.dogfood.elixir "test/**/*.exs"

  This is a development/conformance utility, not a product CLI: the
  grammar-to-parser tool and any user-facing CLI belong in `seed_codegen`
  (xref ADR-009). The vendored Elixir grammar is a *subset* of the language,
  so errors are expected on advanced syntax — the value is exercising Seed's
  lexer and parser on real Elixir at scale, and showing where the grammar (or
  Seed) stops short of full Elixir.
  """

  use Mix.Task

  @interp_dir "test/fixtures/interp"
  @default_glob "lib/**/*.ex"
  @max_listed 12
  @file_timeout 12_000

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    glob = List.first(args) || @default_glob
    parser = load!("ElixirParser")
    lexer = load!("ElixirLexer")
    files = Path.wildcard(glob)

    if files == [] do
      Mix.shell().info("No files matched #{inspect(glob)}.")
    else
      report(files, parser, lexer, glob)
    end
  end

  defp report(files, parser, lexer, glob) do
    results = Enum.map(files, &{&1, parse_file(&1, parser, lexer)})
    {clean, errored} = Enum.split_with(results, fn {_f, r} -> r == :ok end)

    Mix.shell().info("""

    Parsed #{length(files)} files matching #{inspect(glob)} with the vendored Elixir grammar:
      clean:  #{length(clean)}
      errors: #{length(errored)}
    """)

    unless errored == [] do
      Mix.shell().info("First #{min(@max_listed, length(errored))} with diagnostics:")

      errored
      |> Enum.take(@max_listed)
      |> Enum.each(fn {file, {:error, diagnostic}} ->
        Mix.shell().info(
          "  #{file}:#{diagnostic.line}:#{diagnostic.column}  #{diagnostic.message}"
        )
      end)
    end
  end

  # `parse` is rule 0. Each parse runs in its own task with a timeout, so a
  # pathological file (the parser's prediction guard normally fails fast, but
  # the per-process heap cap may also fire) is contained, not fatal.
  defp parse_file(file, parser, lexer) do
    task = Task.async(fn -> Seed.parse(parser, lexer, File.read!(file), 0) end)

    case Task.yield(task, @file_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, _tree}} -> :ok
      {:ok, {:error, [diagnostic | _]}} -> {:error, diagnostic}
      {:ok, {:error, [diagnostic | _], _tree}} -> {:error, diagnostic}
      nil -> failure("timed out after #{@file_timeout} ms")
      {:exit, reason} -> failure("crashed: #{inspect(reason)}")
    end
  end

  defp failure(message), do: {:error, %{line: 0, column: 0, message: message}}

  defp load!(grammar) do
    path = Path.join(@interp_dir, grammar <> ".interp")

    unless File.exists?(path) do
      Mix.raise("#{path} not found; generate it with scripts/gen_interp_fixtures.sh")
    end

    Seed.Interp.load!(path)
  end
end
