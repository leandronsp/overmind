defmodule Overmind.Blueprint.DAGTest do
  use ExUnit.Case

  alias Overmind.Blueprint.DAG

  defp spec(name, deps \\ []) do
    %{name: name, command: "echo #{name}", depends_on: deps}
  end

  describe "topo_sort/1" do
    test "linear chain A→B→C" do
      specs = [spec("A"), spec("B", ["A"]), spec("C", ["B"])]
      assert {:ok, sorted} = DAG.topo_sort(specs)
      names = Enum.map(sorted, & &1.name)
      assert names == ["A", "B", "C"]
    end

    test "no dependencies returns all specs" do
      specs = [spec("X"), spec("Y"), spec("Z")]
      assert {:ok, sorted} = DAG.topo_sort(specs)
      assert length(sorted) == 3
    end

    test "cycle A→B→A returns error" do
      specs = [spec("A", ["B"]), spec("B", ["A"])]
      assert {:error, :cycle} = DAG.topo_sort(specs)
    end

    test "diamond A→[B,C]→D" do
      specs = [
        spec("A"),
        spec("B", ["A"]),
        spec("C", ["A"]),
        spec("D", ["B", "C"])
      ]

      assert {:ok, sorted} = DAG.topo_sort(specs)
      names = Enum.map(sorted, & &1.name)

      # A must be first, D must be last
      assert hd(names) == "A"
      assert List.last(names) == "D"

      # B and C before D
      assert Enum.find_index(names, &(&1 == "B")) < Enum.find_index(names, &(&1 == "D"))
      assert Enum.find_index(names, &(&1 == "C")) < Enum.find_index(names, &(&1 == "D"))
    end

    test "single node" do
      assert {:ok, [spec]} = DAG.topo_sort([spec("solo")])
      assert spec.name == "solo"
    end
  end
end
