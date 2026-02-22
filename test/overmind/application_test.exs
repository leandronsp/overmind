defmodule Overmind.ApplicationTest do
  use ExUnit.Case

  test "ETS table :overmind_sessions exists and is public" do
    info = :ets.info(:overmind_sessions)
    assert info != :undefined
    assert Keyword.get(info, :protection) == :public
    assert Keyword.get(info, :named_table) == true
  end

  test "SessionSupervisor is running" do
    assert Process.whereis(Overmind.SessionSupervisor) |> is_pid()
  end
end
