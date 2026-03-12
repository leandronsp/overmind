defmodule Overmind.Isolation.PortRegistryTest do
  use ExUnit.Case

  alias Overmind.Isolation.PortRegistry

  setup do
    :ets.delete_all_objects(:port_registry)
    :ok
  end

  describe "allocate/3" do
    test "allocates a port in the 3100-3999 range" do
      assert {:ok, port} = PortRegistry.allocate("m1", "db", 5432)
      assert port >= 3100
      assert port <= 3999
    end

    test "allocates different ports for different services of the same mission" do
      assert {:ok, port1} = PortRegistry.allocate("m1", "db", 5432)
      assert {:ok, port2} = PortRegistry.allocate("m1", "cache", 6379)
      assert port1 != port2
    end

    test "allocates different ports for the same service across different missions" do
      assert {:ok, port1} = PortRegistry.allocate("m1", "db", 5432)
      assert {:ok, port2} = PortRegistry.allocate("m2", "db", 5432)
      assert port1 != port2
    end

    test "always starts from the lowest available port" do
      assert {:ok, 3100} = PortRegistry.allocate("m1", "db", 5432)
      assert {:ok, 3101} = PortRegistry.allocate("m2", "db", 5432)
    end

    test "returns {:error, :exhausted} when range is full" do
      # Fill up the entire range (3100..3999 = 900 ports) — skip for speed
      # Instead, fill 3100-3999 by pre-inserting all ports
      Enum.each(3100..3999, fn port ->
        :ets.insert(:port_registry, {port, "blocker", "svc", 0})
      end)

      assert {:error, :exhausted} = PortRegistry.allocate("new", "db", 5432)
    end
  end

  describe "release/1" do
    test "removes all ports allocated to a mission" do
      PortRegistry.allocate("m1", "db", 5432)
      PortRegistry.allocate("m1", "cache", 6379)

      assert length(PortRegistry.list()) == 2

      PortRegistry.release("m1")

      assert PortRegistry.list() == []
    end

    test "only removes ports for the specified mission" do
      PortRegistry.allocate("m1", "db", 5432)
      PortRegistry.allocate("m2", "db", 5432)

      PortRegistry.release("m1")

      remaining = PortRegistry.list()
      assert length(remaining) == 1
      [{_, mission_id, _, _}] = remaining
      assert mission_id == "m2"
    end

    test "is idempotent for unknown mission" do
      assert :ok = PortRegistry.release("nonexistent")
    end
  end

  describe "list/0" do
    test "returns empty list when nothing allocated" do
      assert PortRegistry.list() == []
    end

    test "returns tuples of {port, mission_id, service_name, allocated_at}" do
      PortRegistry.allocate("m1", "db", 5432)

      [{port, mission_id, service_name, allocated_at}] = PortRegistry.list()
      assert port == 3100
      assert mission_id == "m1"
      assert service_name == "db"
      assert is_integer(allocated_at)
    end

    test "returns all allocations across missions" do
      PortRegistry.allocate("m1", "db", 5432)
      PortRegistry.allocate("m2", "cache", 6379)

      assert length(PortRegistry.list()) == 2
    end
  end
end
