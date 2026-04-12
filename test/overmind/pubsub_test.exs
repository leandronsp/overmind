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
end
