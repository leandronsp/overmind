defmodule Overmind.RitualTest do
  use ExUnit.Case

  setup do
    :ets.delete_all_objects(:overmind_rituals)
    :ok
  end

  describe "create/3" do
    test "returns {:ok, id} for valid cron expression" do
      assert {:ok, id} = Overmind.Ritual.create("nightly", "0 2 * * *", "cleanup.sh")
      assert is_binary(id)
    end

    test "rejects cron with fewer than 5 fields" do
      assert {:error, :invalid_cron} = Overmind.Ritual.create("bad", "invalid", "cmd")
    end

    test "rejects cron with more than 5 fields" do
      assert {:error, :invalid_cron} = Overmind.Ritual.create("bad", "1 2 3 4 5 6", "cmd")
    end

    test "accepts wildcard-only cron" do
      assert {:ok, _} = Overmind.Ritual.create("always", "* * * * *", "echo hi")
    end
  end

  describe "list/0" do
    test "returns empty list with no rituals" do
      assert Overmind.Ritual.list() == []
    end

    test "includes created ritual with correct fields" do
      {:ok, id} = Overmind.Ritual.create("daily", "0 9 * * *", "run.sh")

      rituals = Overmind.Ritual.list()
      assert length(rituals) == 1
      [ritual] = rituals
      assert ritual.id == id
      assert ritual.name == "daily"
      assert ritual.cron_expr == "0 9 * * *"
      assert ritual.command == "run.sh"
      assert is_integer(ritual.created_at)
      assert ritual.last_run_at == nil
    end

    test "returns all created rituals" do
      {:ok, _} = Overmind.Ritual.create("r1", "0 1 * * *", "cmd1")
      {:ok, _} = Overmind.Ritual.create("r2", "0 2 * * *", "cmd2")

      assert length(Overmind.Ritual.list()) == 2
    end
  end

  describe "delete/1" do
    test "deletes an existing ritual by name" do
      {:ok, _} = Overmind.Ritual.create("temp", "* * * * *", "echo hi")
      assert :ok = Overmind.Ritual.delete("temp")
      assert Overmind.Ritual.list() == []
    end

    test "returns error for unknown ritual name" do
      assert {:error, :not_found} = Overmind.Ritual.delete("nonexistent")
    end

    test "only deletes the named ritual, leaves others intact" do
      {:ok, _} = Overmind.Ritual.create("keep", "0 1 * * *", "a")
      {:ok, _} = Overmind.Ritual.create("remove", "0 2 * * *", "b")

      assert :ok = Overmind.Ritual.delete("remove")
      rituals = Overmind.Ritual.list()
      assert length(rituals) == 1
      assert hd(rituals).name == "keep"
    end
  end

  describe "update_last_run/2" do
    test "updates last_run_at for existing ritual" do
      {:ok, id} = Overmind.Ritual.create("ticker", "* * * * *", "tick")
      assert :ok = Overmind.Ritual.update_last_run(id, 1_700_000_000)

      [ritual] = Overmind.Ritual.list()
      assert ritual.last_run_at == 1_700_000_000
    end

    test "is a no-op for unknown id" do
      assert :ok = Overmind.Ritual.update_last_run("unknown", 12345)
    end
  end
end
