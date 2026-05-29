# Single-parse throughput baseline for the specialization ladder (ADR-008).
#
# Establishes how fast the *interpreter* lexes and parses a large document,
# split into the lexer and parser/prediction stages so we can see where the
# time goes. This is the number every later rung — a flattened table-driven
# interpreter, then staged Elixir-AST codegen — must beat, measured the same
# way. No optimization lands without a before/after from this harness.
#
# Run with:   mix run bench/parse_throughput.exs
# Size it:    N=20000 mix run bench/parse_throughput.exs   (records in the doc)

alias Seed.CharStream
alias Seed.Interp
alias Seed.Lexer
alias Seed.ParserInterpreter
alias Seed.TokenStream

interp = Path.expand("../test/fixtures/interp", __DIR__)
parser = Interp.load!(Path.join(interp, "JSON.interp"))
lexer = Interp.load!(Path.join(interp, "JSONLexer.interp"))

count = "N" |> System.get_env("5000") |> String.to_integer()
iterations = "ITER" |> System.get_env("20") |> String.to_integer()

record = fn i ->
  ~s({"id":#{i},"name":"item-#{i}","vals":[1,2.5,-3e2],"ok":true,"meta":{"a":null,"b":[#{i},#{i + 1}]}})
end

input = "[" <> Enum.map_join(1..count, ",", record) <> "]"
bytes = byte_size(input)

lex = fn ->
  {:ok, stream} = lexer.atn |> Lexer.new(CharStream.new(input)) |> TokenStream.from_lexer()
  stream
end

# Warm the DFA cache and capture the token count.
stream = lex.()
tokens = TokenStream.size(stream)
{:ok, _tree} = ParserInterpreter.parse(parser, stream, 0)

# Best (min) of `iterations` runs — peak steady-state throughput.
best = fn fun -> 1..iterations |> Enum.map(fn _ -> elem(:timer.tc(fun), 0) end) |> Enum.min() end

lex_us = best.(fn -> lex.() end)
parse_us = best.(fn -> {:ok, _} = ParserInterpreter.parse(parser, stream, 0) end)
total_us = lex_us + parse_us

ms = fn us -> us |> Kernel./(1000) |> Float.round(2) end
mb_per_s = fn us -> bytes |> Kernel./(us) |> Float.round(1) end
tok_per_s = fn us -> round(tokens * 1_000_000 / us) end

row = fn label, us ->
  "  #{String.pad_trailing(label, 7)} #{ms.(us)} ms\t#{mb_per_s.(us)} MB/s\t#{tok_per_s.(us)} tokens/s"
end

IO.puts("""
parse throughput baseline (JSON grammar, interpreter)
  schedulers:   #{System.schedulers_online()}, OTP #{System.otp_release()}
  document:     #{count} records, #{Float.round(bytes / 1024, 1)} KiB, #{tokens} tokens
  iterations:   #{iterations} (best time reported)

#{row.("lex", lex_us)}
#{row.("parse", parse_us)}
#{row.("total", total_us)}
""")
