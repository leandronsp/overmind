defmodule Overmind.Blueprint.DAGTest do
  use ExUnit.Case

  alias Overmind.Blueprint.DAG

  defp spec(name, depends_on \\ []) do
    %{name: name, command: "echo #{name}", depends_on: depends_on}
  end

  describe "topo_sort/1" do
    test "empty list returns empty list" do
      assert {:ok, []} = DAG.topo_sort([])
    end

    test "single agent with no deps" do
      assert {:ok, [s]} = DAG.topo_sort([spec("a")])
      assert s.name == "a"
    end

    test "linear chain: a -> b -> c returns [a, b, c]" do
      specs = [spec("c", ["b"]), spec("b", ["a"]), spec("a")]
      {:ok, ordered} = DAG.topo_sort(specs)
      names = Enum.map(ordered, & &1.name)
      assert Enum.find_index(names, &(&1 == "a")) < Enum.find_index(names, &(&1 == "b"))
      assert Enum.find_index(names, &(&1 == "b")) < Enum.find_index(names, &(&1 == "c"))
    end

    test "parallel agents: a and b both independent" do
      specs = [spec("a"), spec("b")]
      {:ok, ordered} = DAG.topo_sort(specs)
      names = Enum.map(ordered, & &1.name) |> Enum.sort()
      assert names == ["a", "b"]
    end

    test "diamond: a -> b, a -> c, b -> d, c -> d" do
      specs = [spec("d", ["b", "c"]), spec("b", ["a"]), spec("c", ["a"]), spec("a")]
      {:ok, ordered} = DAG.topo_sort(specs)
      names = Enum.map(ordered, & &1.name)
      a_idx = Enum.find_index(names, &(&1 == "a"))
      b_idx = Enum.find_index(names, &(&1 == "b"))
      c_idx = Enum.find_index(names, &(&1 == "c"))
      d_idx = Enum.find_index(names, &(&1 == "d"))
      assert a_idx < b_idx
      assert a_idx < c_idx
      assert b_idx < d_idx
      assert c_idx < d_idx
    end

    test "detects cycle: a -> b -> a" do
      specs = [spec("a", ["b"]), spec("b", ["a"])]
      assert {:error, :cycle} = DAG.topo_sort(specs)
    end

    test "detects self-loop: a -> a" do
      specs = [spec("a", ["a"])]
      assert {:error, :cycle} = DAG.topo_sort(specs)
    end

    test "detects three-node cycle: a -> b -> c -> a" do
      specs = [spec("a", ["c"]), spec("b", ["a"]), spec("c", ["b"])]
      assert {:error, :cycle} = DAG.topo_sort(specs)
    end
  end
end
