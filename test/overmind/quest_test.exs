defmodule Overmind.QuestTest do
  use ExUnit.Case

  setup do
    :ets.delete_all_objects(:overmind_quests)
    Overmind.Test.MissionHelper.cleanup_missions()
    on_exit(fn -> Overmind.Test.MissionHelper.cleanup_missions() end)
    :ok
  end

  describe "run/2" do
    test "returns {:ok, quest_id}" do
      assert {:ok, quest_id} = Overmind.Quest.run("test-quest", "echo hello")
      assert is_binary(quest_id)
    end

    test "quest appears in list after run" do
      {:ok, quest_id} = Overmind.Quest.run("my-quest", "echo hello")

      quests = Overmind.Quest.list()
      assert Enum.any?(quests, fn q -> q.id == quest_id end)
    end

    test "quest has correct name and command" do
      {:ok, quest_id} = Overmind.Quest.run("named-quest", "echo hi")

      {:ok, quest} = Overmind.Quest.status(quest_id)
      assert quest.name == "named-quest"
      assert quest.command == "echo hi"
    end

    test "returns error for empty command" do
      assert {:error, :empty_command} = Overmind.Quest.run("bad-quest", "")
    end
  end

  describe "list/0" do
    test "returns empty list with no quests" do
      assert Overmind.Quest.list() == []
    end

    test "returns multiple quests" do
      {:ok, _} = Overmind.Quest.run("q1", "echo one")
      {:ok, _} = Overmind.Quest.run("q2", "echo two")

      quests = Overmind.Quest.list()
      assert length(quests) == 2
    end
  end

  describe "status/1" do
    test "returns quest with :running status for active mission" do
      {:ok, quest_id} = Overmind.Quest.run("running-quest", "sleep 60")

      assert {:ok, quest} = Overmind.Quest.status(quest_id)
      assert quest.status == :running
    end

    test "returns quest with :completed status after exit code 0" do
      {:ok, quest_id} = Overmind.Quest.run("done-quest", "echo done")

      {:ok, quest} = Overmind.Quest.status(quest_id)
      mission_id = quest.mission_id

      # Wait for mission to finish
      [{^mission_id, pid, _, _, _}] = :ets.lookup(:overmind_missions, mission_id)
      mission_ref = Process.monitor(pid)
      assert_receive {:DOWN, ^mission_ref, :process, ^pid, :normal}, 1000

      assert {:ok, finished} = Overmind.Quest.status(quest_id)
      assert finished.status == :completed
    end

    test "returns error for unknown quest" do
      assert {:error, :not_found} = Overmind.Quest.status("nonexistent")
    end
  end
end
