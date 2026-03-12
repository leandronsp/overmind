defmodule Overmind.Isolation.WorktreeTest do
  use ExUnit.Case

  alias Overmind.Isolation.Worktree

  # Use the project repo itself for worktree operations.
  # The test creates and immediately cleans up a real worktree.
  @project_path File.cwd!()

  describe "list/1" do
    test "includes the main worktree path" do
      paths = Worktree.list(@project_path)
      assert is_list(paths)
      assert Enum.any?(paths, &(&1 == @project_path))
    end
  end

  describe "create/2 and cleanup/2" do
    test "creates a worktree and removes it" do
      branch = "overmind/test-wt-#{System.unique_integer([:positive])}"

      assert {:ok, path} = Worktree.create(@project_path, branch)
      assert File.exists?(path)

      paths_after_create = Worktree.list(@project_path)
      assert Enum.member?(paths_after_create, path)

      assert :ok = Worktree.cleanup(@project_path, path)
      refute File.exists?(path)

      paths_after_cleanup = Worktree.list(@project_path)
      refute Enum.member?(paths_after_cleanup, path)
    end

    test "returns {:error, reason} when branch already exists" do
      branch = "overmind/test-dup-#{System.unique_integer([:positive])}"

      {:ok, path} = Worktree.create(@project_path, branch)

      on_exit(fn -> Worktree.cleanup(@project_path, path) end)

      # Attempting to create the same branch again should fail
      assert {:error, _reason} = Worktree.create(@project_path, branch)
    end
  end
end
