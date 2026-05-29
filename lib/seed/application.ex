defmodule Seed.Application do
  @moduledoc """
  The Seed OTP application.

  Starts the supervision tree, whose only child is `Seed.DFACache` — the
  owner of the ETS table that memoizes ATN-simulation decisions. The cache
  is optional for correctness (the simulators fall back to recomputation),
  but running it under supervision gives it a stable owner.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [Seed.DFACache]
    Supervisor.start_link(children, strategy: :one_for_one, name: Seed.Supervisor)
  end
end
