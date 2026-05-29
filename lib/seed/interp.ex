defmodule Seed.Interp do
  @moduledoc """
  Loads an ANTLR `.interp` file into a `Seed.Grammar`.

  The ANTLR tool emits a `<Grammar>.interp` file per recognizer next to the
  generated code. It is a sequence of headed sections — token literal names,
  token symbolic names, rule names, optional channel and mode names, and the
  serialized ATN as a bracketed integer array. Reading it gives Seed
  everything needed to parse a grammar at run time without any code
  generation:

      grammar = Seed.Interp.load!("Expr.interp")
      grammar.rule_names                                   # ["prog", "stat", "expr"]
      Seed.Vocabulary.display_name(grammar.vocabulary, 9)  # "ID"
  """

  alias Seed.ATNDeserializer
  alias Seed.Grammar
  alias Seed.Vocabulary

  @headers [
    "token literal names",
    "token symbolic names",
    "rule names",
    "channel names",
    "mode names",
    "atn"
  ]

  defmodule Error do
    @moduledoc "Raised when a `.interp` file cannot be parsed."
    defexception [:message]
  end

  @doc "Loads the `.interp` file at `path` into a `Seed.Grammar`."
  @spec load!(Path.t()) :: Grammar.t()
  def load!(path) do
    case File.read(path) do
      {:ok, content} ->
        parse!(content)

      {:error, reason} ->
        raise Error, message: "cannot read #{path}: #{:file.format_error(reason)}"
    end
  end

  @doc "Parses the contents of a `.interp` file into a `Seed.Grammar`."
  @spec parse!(binary()) :: Grammar.t()
  def parse!(content) when is_binary(content) do
    sections = content |> String.split("\n") |> collect_sections(nil, %{})

    %Grammar{
      atn: sections |> fetch_atn!() |> parse_atn() |> ATNDeserializer.deserialize!(),
      vocabulary:
        Vocabulary.new(
          names(sections, "token literal names"),
          names(sections, "token symbolic names")
        ),
      rule_names: section(sections, "rule names"),
      channel_names: section(sections, "channel names"),
      mode_names: section(sections, "mode names")
    }
  end

  # Splits the file into header => content-lines, keyed by header text.
  defp collect_sections([], _current, acc), do: acc

  defp collect_sections([line | rest], current, acc) do
    cond do
      header?(line) ->
        header = String.trim_trailing(line, ":")
        collect_sections(rest, header, Map.put_new(acc, header, []))

      line == "" ->
        collect_sections(rest, nil, acc)

      current == nil ->
        collect_sections(rest, current, acc)

      true ->
        collect_sections(rest, current, Map.update!(acc, current, &(&1 ++ [line])))
    end
  end

  defp header?(line),
    do: String.ends_with?(line, ":") and String.trim_trailing(line, ":") in @headers

  defp section(sections, header), do: Map.get(sections, header, [])

  defp names(sections, header) do
    sections
    |> section(header)
    |> Enum.map(fn
      "null" -> nil
      name -> name
    end)
  end

  defp fetch_atn!(sections) do
    case section(sections, "atn") do
      [line | _] -> line
      [] -> raise Error, message: "missing atn section"
    end
  end

  defp parse_atn(line) do
    line
    |> String.trim()
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
    |> String.split(",")
    |> Enum.map(&(&1 |> String.trim() |> String.to_integer()))
  rescue
    ArgumentError -> reraise Error, [message: "malformed atn section"], __STACKTRACE__
  end
end
