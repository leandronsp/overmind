defmodule Overmind.Mission.StoreTest do
  use ExUnit.Case

  alias Overmind.Mission.Store

  setup do
    :ets.delete_all_objects(:overmind_missions)
    :ok
  end

  describe "lookup/1" do
    test "returns :not_found for unknown id" do
      assert Store.lookup("unknown") == :not_found
    end

    test "returns {:running, pid, command, started_at} for running mission" do
      pid = self()
      Store.insert("abc", {pid, "sleep 60", :running, 1000})

      assert {:running, ^pid, "sleep 60", 1000} = Store.lookup("abc")
    end

    test "returns {:exited, status, command, started_at} for stopped mission" do
      Store.insert("abc", {self(), "echo hi", :stopped, 1000})

      assert {:exited, :stopped, "echo hi", 1000} = Store.lookup("abc")
    end

    test "returns {:exited, status, command, started_at} for crashed mission" do
      Store.insert("abc", {self(), "false", :crashed, 1000})

      assert {:exited, :crashed, "false", 1000} = Store.lookup("abc")
    end
  end

  describe "safe_call/2" do
    test "returns {:ok, value} on successful call" do
      {:ok, pid} = Agent.start_link(fn -> 42 end)
      assert {:ok, 42} = Store.safe_call(pid, {:get, & &1})
      Agent.stop(pid)
    end

    test "returns :dead when process is not alive" do
      {:ok, pid} = Agent.start_link(fn -> :ok end)
      Agent.stop(pid)
      Process.sleep(10)

      assert :dead = Store.safe_call(pid, {:get, & &1})
    end
  end

  describe "insert/2" do
    test "inserts mission tuple into ETS" do
      pid = self()
      Store.insert("m1", {pid, "echo hello", :running, 500})

      [{id, ^pid, cmd, status, started}] = :ets.lookup(:overmind_missions, "m1")
      assert id == "m1"
      assert cmd == "echo hello"
      assert status == :running
      assert started == 500
    end
  end

  describe "persist_after_exit/3" do
    test "stores logs and raw_events under tagged keys" do
      Store.persist_after_exit("m1", "some logs", [%{"type" => "result"}])

      assert Store.stored_logs("m1") == "some logs"
      assert Store.stored_raw_events("m1") == [%{"type" => "result"}]
    end
  end

  describe "stored_logs/1" do
    test "returns empty string when no logs persisted" do
      assert Store.stored_logs("nope") == ""
    end
  end

  describe "stored_raw_events/1" do
    test "returns empty list when no events persisted" do
      assert Store.stored_raw_events("nope") == []
    end
  end

  describe "cleanup/1" do
    test "removes mission and associated data" do
      Store.insert("m1", {self(), "cmd", :stopped, 100})
      Store.persist_after_exit("m1", "logs", [])

      Store.cleanup("m1")

      assert Store.lookup("m1") == :not_found
      assert Store.stored_logs("m1") == ""
      assert Store.stored_raw_events("m1") == []
    end
  end

  describe "list_all/0" do
    test "returns only mission tuples, not metadata" do
      pid = self()
      Store.insert("m1", {pid, "echo hi", :running, 100})
      Store.persist_after_exit("m1", "logs", [%{}])

      missions = Store.list_all()
      assert length(missions) == 1
      assert {"m1", ^pid, "echo hi", :running, 100} = hd(missions)
    end

    test "returns empty list when no missions" do
      assert Store.list_all() == []
    end
  end
end
