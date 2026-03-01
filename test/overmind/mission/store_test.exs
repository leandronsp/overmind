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

  describe "insert_type/2 and lookup_type/1" do
    test "stores and retrieves mission type" do
      Store.insert_type("m1", :session)
      assert Store.lookup_type("m1") == :session
    end

    test "returns :task as default for unknown id" do
      assert Store.lookup_type("nope") == :task
    end
  end

  describe "insert_session_id/2 and lookup_session_id/1" do
    test "stores and retrieves session_id" do
      Store.insert_session_id("m1", "sess-abc")
      assert Store.lookup_session_id("m1") == "sess-abc"
    end

    test "returns nil for unknown id" do
      assert Store.lookup_session_id("nope") == nil
    end
  end

  describe "insert_attached/2 and lookup_attached/1" do
    test "stores and retrieves attached flag" do
      Store.insert_attached("m1", true)
      assert Store.lookup_attached("m1") == true
    end

    test "returns false for unknown id" do
      assert Store.lookup_attached("nope") == false
    end
  end

  describe "insert_name/2 and lookup_name/1" do
    test "stores and retrieves name" do
      Store.insert_name("m1", "bold-arc")
      assert Store.lookup_name("m1") == "bold-arc"
    end

    test "returns nil for unknown id" do
      assert Store.lookup_name("nope") == nil
    end
  end

  describe "find_by_name/1" do
    test "finds id by name" do
      Store.insert_name("m1", "bold-arc")
      assert Store.find_by_name("bold-arc") == "m1"
    end

    test "returns nil for unknown name" do
      assert Store.find_by_name("nonexist") == nil
    end
  end

  describe "resolve_id/1" do
    test "returns id when mission exists by id" do
      Store.insert("m1", {self(), "cmd", :running, 100})
      assert Store.resolve_id("m1") == "m1"
    end

    test "resolves name to id" do
      Store.insert("m1", {self(), "cmd", :running, 100})
      Store.insert_name("m1", "bold-arc")
      assert Store.resolve_id("bold-arc") == "m1"
    end

    test "returns input when neither id nor name found" do
      assert Store.resolve_id("unknown") == "unknown"
    end
  end

  describe "insert_cwd/2 and lookup_cwd/1" do
    test "stores and retrieves cwd" do
      Store.insert_cwd("m1", "/tmp")
      assert Store.lookup_cwd("m1") == "/tmp"
    end

    test "returns nil for unknown id" do
      assert Store.lookup_cwd("nope") == nil
    end
  end

  describe "lookup/1 with :restarting status" do
    test "returns {:restarting, pid, command, started_at} when process alive" do
      pid = self()
      Store.insert("abc", {pid, "false", :restarting, 1000})

      assert {:restarting, ^pid, "false", 1000} = Store.lookup("abc")
    end

    test "returns {:exited, :restarting, command, started_at} when process dead" do
      {:ok, pid} = Agent.start_link(fn -> :ok end)
      Agent.stop(pid)
      Process.sleep(10)
      Store.insert("abc", {pid, "false", :restarting, 1000})

      assert {:exited, :restarting, "false", 1000} = Store.lookup("abc")
    end
  end

  describe "insert_restart_policy/2 and lookup_restart_policy/1" do
    test "stores and retrieves restart policy" do
      Store.insert_restart_policy("m1", :on_failure)
      assert Store.lookup_restart_policy("m1") == :on_failure
    end

    test "returns :never as default" do
      assert Store.lookup_restart_policy("nope") == :never
    end
  end

  describe "insert_restart_count/2 and lookup_restart_count/1" do
    test "stores and retrieves restart count" do
      Store.insert_restart_count("m1", 3)
      assert Store.lookup_restart_count("m1") == 3
    end

    test "returns 0 as default" do
      assert Store.lookup_restart_count("nope") == 0
    end
  end

  describe "insert_parent/2 and lookup_parent/1" do
    test "stores and retrieves parent id" do
      Store.insert_parent("child1", "parent1")
      assert Store.lookup_parent("child1") == "parent1"
    end

    test "returns nil for unknown id" do
      assert Store.lookup_parent("nope") == nil
    end
  end

  describe "find_children/1" do
    test "returns child ids for a parent" do
      Store.insert_parent("child1", "parent1")
      Store.insert_parent("child2", "parent1")

      children = Store.find_children("parent1")
      assert Enum.sort(children) == ["child1", "child2"]
    end

    test "returns empty list for no children" do
      assert Store.find_children("nope") == []
    end
  end

  describe "insert_exit_code/2 and lookup_exit_code/1" do
    test "stores and retrieves exit code" do
      Store.insert_exit_code("m1", 42)
      assert Store.lookup_exit_code("m1") == 42
    end

    test "returns nil for unknown id" do
      assert Store.lookup_exit_code("nope") == nil
    end
  end

  describe "insert_last_activity/2 and lookup_last_activity/1" do
    test "stores and retrieves last activity timestamp" do
      Store.insert_last_activity("m1", 1_709_000_000)
      assert Store.lookup_last_activity("m1") == 1_709_000_000
    end

    test "returns nil as default" do
      assert Store.lookup_last_activity("nope") == nil
    end
  end

  describe "cleanup/1 with all metadata" do
    test "removes all metadata entries" do
      Store.insert("m1", {self(), "cmd", :stopped, 100})
      Store.insert_type("m1", :session)
      Store.insert_session_id("m1", "sess-abc")
      Store.insert_attached("m1", true)
      Store.insert_cwd("m1", "/tmp")
      Store.insert_name("m1", "bold-arc")
      Store.insert_restart_policy("m1", :on_failure)
      Store.insert_restart_count("m1", 2)
      Store.insert_last_activity("m1", 1_000_000)
      Store.insert_exit_code("m1", 1)
      Store.insert_parent("m1", "p1")
      Store.persist_after_exit("m1", "logs", [])

      Store.cleanup("m1")

      assert Store.lookup_type("m1") == :task
      assert Store.lookup_session_id("m1") == nil
      assert Store.lookup_attached("m1") == false
      assert Store.lookup_cwd("m1") == nil
      assert Store.lookup_name("m1") == nil
      assert Store.lookup_restart_policy("m1") == :never
      assert Store.lookup_restart_count("m1") == 0
      assert Store.lookup_last_activity("m1") == nil
      assert Store.lookup_exit_code("m1") == nil
      assert Store.lookup_parent("m1") == nil
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
