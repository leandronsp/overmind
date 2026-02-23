defmodule Overmind.ApplicationTest do
  use ExUnit.Case

  test "ETS table :overmind_missions exists and is public" do
    info = :ets.info(:overmind_missions)
    assert info != :undefined
    assert Keyword.get(info, :protection) == :public
    assert Keyword.get(info, :named_table) == true
  end

  test "MissionSupervisor is running" do
    assert Process.whereis(Overmind.MissionSupervisor) |> is_pid()
  end
end
