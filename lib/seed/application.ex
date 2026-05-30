defmodule Seed.Application do
  @moduledoc """
  The Seed OTP application.

  Starts the supervision tree, whose only child is `Seed.DFACache` — the
  owner of the ETS table that memoizes ATN-simulation decisions. The cache
  is optional for correctness (the simulators fall back to recomputation),
  but running it under supervision gives it a stable owner.

  When `config :seed, :resource_guard` is set it also caps the VM at boot —
  a per-process heap limit and a scheduler cap. This is opt-in and only this
  project enables it (a dependency does not load this app's config), so it
  never constrains a host application that merely depends on `seed`.
  """

  use Application

  @impl true
  def start(_type, _args) do
    apply_resource_guard(Application.get_env(:seed, :resource_guard))
    children = [Seed.DFACache]
    Supervisor.start_link(children, strategy: :one_for_one, name: Seed.Supervisor)
  end

  defp apply_resource_guard(nil), do: :ok

  defp apply_resource_guard(guard) do
    cap_heap(guard[:max_heap_words])
    cap_schedulers(guard[:cap_schedulers_to])
    :ok
  end

  defp cap_heap(nil), do: :ok

  defp cap_heap(words) when is_integer(words) do
    _ = :erlang.system_flag(:max_heap_size, %{size: words, kill: true, error_logger: true})
    :ok
  end

  defp cap_schedulers(nil), do: :ok

  defp cap_schedulers(:half) do
    cap_schedulers(max(1, div(:erlang.system_info(:schedulers), 2)))
  end

  defp cap_schedulers(n) when is_integer(n) do
    _ = :erlang.system_flag(:schedulers_online, max(1, min(n, :erlang.system_info(:schedulers))))
    :ok
  end
end
