defmodule Overmind.Isolation.Worktree do
  @moduledoc false

  # Worktrees are created inside the project at .overmind/worktrees/<branch>,
  # following the convention from PRD section 8: `git worktree add .overmind/worktrees/<branch> -b <branch>`.

  @spec create(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def create(project_path, branch_name) do
    path = worktree_path(project_path, branch_name)
    File.mkdir_p!(Path.dirname(path))

    case System.cmd("git", ["worktree", "add", path, "-b", branch_name],
           cd: project_path,
           stderr_to_stdout: true
         ) do
      {_, 0} -> {:ok, path}
      {output, _} -> {:error, String.trim(output)}
    end
  end

  @spec cleanup(String.t(), String.t()) :: :ok | {:error, String.t()}
  def cleanup(project_path, worktree_path) do
    case System.cmd("git", ["worktree", "remove", "--force", worktree_path],
           cd: project_path,
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        # Best-effort branch deletion — ignore failures (branch may not exist)
        branch = Path.basename(worktree_path)
        System.cmd("git", ["branch", "-D", branch], cd: project_path, stderr_to_stdout: true)
        :ok

      {output, _} ->
        {:error, String.trim(output)}
    end
  end

  @spec list(String.t()) :: [String.t()]
  def list(project_path) do
    case System.cmd("git", ["worktree", "list", "--porcelain"],
           cd: project_path,
           stderr_to_stdout: true
         ) do
      {output, 0} -> parse_worktree_paths(output)
      _ -> []
    end
  end

  # Private

  defp worktree_path(project_path, branch_name) do
    Path.join([project_path, ".overmind", "worktrees", branch_name])
  end

  # Each worktree block is separated by a blank line.
  # Blocks look like:
  #   worktree /path/to/worktree
  #   HEAD abc123
  #   branch refs/heads/name
  defp parse_worktree_paths(output) do
    output
    |> String.split("\n\n", trim: true)
    |> Enum.flat_map(&extract_path_from_block/1)
  end

  defp extract_path_from_block(block) do
    case Regex.run(~r/^worktree (.+)$/m, block) do
      [_, path] -> [path]
      _ -> []
    end
  end
end
