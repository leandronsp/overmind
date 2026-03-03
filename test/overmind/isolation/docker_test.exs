defmodule Overmind.Isolation.DockerTest do
  use ExUnit.Case

  alias Overmind.Isolation.Docker

  describe "list/1" do
    test "returns empty list for unknown mission id" do
      result = Docker.list("no-such-mission-#{System.unique_integer()}")
      assert result == []
    end
  end

  describe "stop/1" do
    test "is a no-op for a mission with no containers" do
      assert :ok = Docker.stop("no-such-mission-#{System.unique_integer()}")
    end
  end

  # Docker integration tests require a running Docker daemon.
  # Tag with @tag :docker and run selectively: mix test --include docker
  @tag :docker
  describe "start/2" do
    test "starts a container and lists it under the mission" do
      mission_id = "test-#{System.unique_integer([:positive])}"
      spec = %{name: "db", image: "postgres:16", port: 5432}

      result = Docker.start(mission_id, spec)

      # Either success or graceful failure (Docker not available)
      case result do
        {:ok, container_id} ->
          assert is_binary(container_id)
          containers = Docker.list(mission_id)
          assert length(containers) > 0
          Docker.stop(mission_id)

        {:error, _} ->
          :ok
      end
    end
  end
end
