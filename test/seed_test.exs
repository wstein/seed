defmodule SeedTest do
  use ExUnit.Case, async: true
  doctest Seed

  test "version/0 returns the configured project version" do
    assert Seed.version() == Mix.Project.config()[:version]
    assert is_binary(Seed.version())
  end
end
