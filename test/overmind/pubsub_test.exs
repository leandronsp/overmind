defmodule Overmind.PubSubTest do
  use ExUnit.Case, async: true

  alias Overmind.PubSub

  describe "subscribe/1 and broadcast/2" do
    test "subscriber receives broadcasted mission events" do
      mission_id = "pubsub-test-#{System.unique_integer([:positive])}"
      PubSub.subscribe(mission_id)

      PubSub.broadcast(mission_id, {:mission_event, mission_id, {:text, "hello"}, %{"type" => "text"}})

      assert_receive {:mission_event, ^mission_id, {:text, "hello"}, %{"type" => "text"}}
    end
  end

  describe "mission integration" do
    setup do
      Overmind.Test.MissionHelper.cleanup_missions()
      :ok
    end

    test "mission broadcasts parsed events to subscribers" do
      script = ~s(sh -c 'echo "{\\\"type\\\":\\\"assistant\\\",\\\"message\\\":{\\\"content\\\":[{\\\"type\\\":\\\"text\\\",\\\"text\\\":\\\"hello world\\\"}]}}"')

      id = Overmind.Mission.generate_id()
      PubSub.subscribe(id)

      {:ok, pid} = Overmind.Mission.start_link(id: id, command: script, provider: Overmind.Provider.TestClaude)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000

      assert_receive {:mission_event, ^id, {:text, "hello world"}, %{"type" => "assistant"}}, 500
    end

    test "mission broadcasts exit event on port close" do
      id = Overmind.Mission.generate_id()
      PubSub.subscribe(id)

      {:ok, pid} = Overmind.Mission.start_link(id: id, command: "true")
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000

      assert_receive {:mission_exit, ^id, :stopped, 0}, 500
    end
  end
end
