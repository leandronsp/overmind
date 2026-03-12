defmodule Overmind.AkashaTest do
  use ExUnit.Case

  alias Overmind.Akasha
  alias Overmind.Akasha.{Memory, Store}

  setup do
    Store.clear()
    :ok
  end

  describe "remember/3" do
    test "stores and returns memory" do
      assert {:ok, %Memory{key: "k1", content: "v1"}} = Akasha.remember("k1", "v1")
    end

    test "defaults to empty tags" do
      {:ok, memory} = Akasha.remember("k2", "v2")
      assert memory.tags == []
    end

    test "accepts tags as third argument" do
      {:ok, memory} = Akasha.remember("k3", "v3", ["tag1", "tag2"])
      assert memory.tags == ["tag1", "tag2"]
    end

    test "upserts on duplicate key" do
      Akasha.remember("dup", "first")
      {:ok, m} = Akasha.remember("dup", "second")
      assert m.content == "second"
    end
  end

  describe "recall/1" do
    test "retrieves stored memory" do
      Akasha.remember("r1", "content")
      assert {:ok, %Memory{key: "r1", content: "content"}} = Akasha.recall("r1")
    end

    test "returns error for unknown key" do
      assert {:error, :not_found} = Akasha.recall("missing")
    end
  end

  describe "forget/1" do
    test "removes memory" do
      Akasha.remember("del", "content")
      assert :ok = Akasha.forget("del")
      assert {:error, :not_found} = Akasha.recall("del")
    end

    test "returns error for unknown key" do
      assert {:error, :not_found} = Akasha.forget("missing")
    end
  end

  describe "search/1" do
    test "finds relevant memories by content" do
      Akasha.remember("ai-notes", "machine learning tips")
      {:ok, results} = Akasha.search("machine")
      assert Enum.any?(results, &(&1.key == "ai-notes"))
    end

    test "returns empty list for no match" do
      {:ok, results} = Akasha.search("zzz-no-match-xyz")
      assert results == []
    end

    test "returns multiple matches" do
      Akasha.remember("m1", "elixir patterns")
      Akasha.remember("m2", "elixir tips")
      Akasha.remember("m3", "python notes")
      {:ok, results} = Akasha.search("elixir")
      keys = Enum.map(results, & &1.key)
      assert "m1" in keys
      assert "m2" in keys
      refute "m3" in keys
    end
  end
end
