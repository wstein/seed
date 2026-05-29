# Concurrent-parse benchmark: ATN passed by value vs held in :persistent_term.
#
# ADR-005 lists holding the static ATN in `:persistent_term` (zero-copy
# shared reads) as a possible optimization. This measures whether it is
# justified: it parses the same input across many concurrent processes two
# ways and reports throughput, plus the ATN term's in-memory size (the cost
# that would be copied per process under the by-value approach).
#
# Run with: mix run bench/parse_bench.exs

alias Seed.Interp

interp = Path.expand("../test/fixtures/interp", __DIR__)
parser = Interp.load!(Path.join(interp, "Expr.interp"))
lexer = Interp.load!(Path.join(interp, "ExprLexer.interp"))
input = "x = 1 + 2 * 3; y = (a - b) / c; z = a + b + c + d;"

atn_words = :erts_debug.flat_size(parser.atn)

# Runs `total` parses spread over tasks of `per_task` parses each. `fetch`
# obtains the grammar inside each task (closing over it copies the ATN;
# reading persistent_term does not).
run = fn fetch, per_task, total ->
  tasks = div(total, per_task)

  {micros, :ok} =
    :timer.tc(fn ->
      1..tasks
      |> Enum.map(fn _ ->
        Task.async(fn ->
          grammar = fetch.()
          Enum.each(1..per_task, fn _ -> {:ok, _} = Seed.parse(grammar, lexer, input, 0) end)
        end)
      end)
      |> Enum.each(&Task.await(&1, :infinity))

      :ok
    end)

  "#{Float.round(micros / 1000, 1)} ms (#{round(total * 1_000_000 / micros)} parses/s)"
end

:persistent_term.put({__MODULE__, :atn}, parser)
by_value = fn -> parser end
shared = fn -> :persistent_term.get({__MODULE__, :atn}) end

# Amortized: long-lived workers (ATN copied once, reused for many parses).
amortized_value = run.(by_value, 2_000, 96_000)
amortized_pt = run.(shared, 2_000, 96_000)

# Unamortized: one parse per process (worst case for the by-value copy).
oneshot_value = run.(by_value, 1, 20_000)
oneshot_pt = run.(shared, 1, 20_000)

:persistent_term.erase({__MODULE__, :atn})

IO.puts("""
parse benchmark (Expr grammar)
  schedulers:     #{System.schedulers_online()}
  ATN flat size:  #{atn_words} words (~#{Float.round(atn_words * :erlang.system_info(:wordsize) / 1024, 1)} KiB)

  amortized (2000 parses/process, 96000 total)
    by value:         #{amortized_value}
    persistent_term:  #{amortized_pt}

  one parse/process (20000 total)
    by value:         #{oneshot_value}
    persistent_term:  #{oneshot_pt}
""")
