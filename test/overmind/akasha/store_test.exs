defmodule Overmind.Akasha.StoreTest do
  use ExUnit.Case

  alias Overmind.Akasha.{Memory, Store}

  setup do
    Store.clear()
    :ok
  end

  describe "remember/3" do
    test "stores a new memory and returns it" do
      assert {:ok, %Memory{key: "test-key", content: "test content"}} =
               Store.remember("test-key", "test content")
    end

    test "assigns timestamps on creation" do
      before = System.system_time(:second)
      {:ok, memory} = Store.remember("ts-key", "content")
      assert memory.created_at >= before
      assert memory.updated_at >= before
    end

    test "upserts when key already exists" do
      {:ok, _} = Store.remember("dupe-key", "original")
      {:ok, updated} = Store.remember("dupe-key", "updated")
      assert updated.content == "updated"
    end

    test "preserves original created_at on upsert" do
      {:ok, original} = Store.remember("upsert-ts", "first")
      Process.sleep(1100)
      {:ok, updated} = Store.remember("upsert-ts", "second")
      assert updated.created_at == original.created_at
      assert updated.updated_at >= original.updated_at
    end

    test "stores tags as list" do
      {:ok, memory} = Store.remember("tagged", "content", ["ml", "elixir"])
      assert memory.tags == ["ml", "elixir"]
    end

    test "defaults to empty tags" do
      {:ok, memory} = Store.remember("no-tags", "content")
      assert memory.tags == []
    end
  end

  describe "recall/1" do
    test "retrieves memory by key" do
      {:ok, _} = Store.remember("recall-key", "the content")
      assert {:ok, %Memory{key: "recall-key", content: "the content"}} = Store.recall("recall-key")
    end

    test "returns tags correctly" do
      Store.remember("tagged-recall", "body", ["a", "b"])
      {:ok, memory} = Store.recall("tagged-recall")
      assert memory.tags == ["a", "b"]
    end

    test "returns :not_found for unknown key" do
      assert {:error, :not_found} = Store.recall("no-such-key")
    end
  end

  describe "forget/1" do
    test "deletes a memory" do
      {:ok, _} = Store.remember("to-delete", "content")
      assert :ok = Store.forget("to-delete")
      assert {:error, :not_found} = Store.recall("to-delete")
    end

    test "returns :not_found when key does not exist" do
      assert {:error, :not_found} = Store.forget("nonexistent")
    end
  end

  describe "search/1" do
    setup do
      Store.remember("elixir-intro", "Introduction to Elixir language", ["elixir", "programming"])
      Store.remember("otp-basics", "OTP supervision trees", ["elixir", "otp"])
      Store.remember("python-tips", "Python best practices", ["python"])
      :ok
    end

    test "finds memories matching key" do
      {:ok, results} = Store.search("elixir-intro")
      keys = Enum.map(results, & &1.key)
      assert "elixir-intro" in keys
    end

    test "finds memories matching content" do
      {:ok, results} = Store.search("supervision")
      keys = Enum.map(results, & &1.key)
      assert "otp-basics" in keys
    end

    test "finds memories matching tags" do
      {:ok, results} = Store.search("otp")
      keys = Enum.map(results, & &1.key)
      assert "otp-basics" in keys
    end

    test "returns all matching memories" do
      {:ok, results} = Store.search("elixir")
      keys = Enum.map(results, & &1.key)
      assert "elixir-intro" in keys
      assert "otp-basics" in keys
    end

    test "returns empty list when no match" do
      {:ok, results} = Store.search("nonexistent-xyz-123")
      assert results == []
    end
  end

  describe "clear/0" do
    test "removes all memories" do
      Store.remember("k1", "v1")
      Store.remember("k2", "v2")
      :ok = Store.clear()
      assert {:error, :not_found} = Store.recall("k1")
      assert {:error, :not_found} = Store.recall("k2")
    end
  end
end
