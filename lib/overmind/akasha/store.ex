defmodule Overmind.Akasha.Store do
  @moduledoc false
  use GenServer

  alias Overmind.Akasha.Memory

  @default_db_path Path.expand("~/.overmind/akasha.db")

  # SQL to create the memories table if not already present.
  @create_table_sql """
  CREATE TABLE IF NOT EXISTS memories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    key TEXT UNIQUE NOT NULL,
    content TEXT NOT NULL,
    tags TEXT DEFAULT '',
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )
  """

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec remember(String.t(), String.t(), [String.t()]) :: {:ok, Memory.t()} | {:error, term()}
  def remember(key, content, tags \\ []) do
    GenServer.call(__MODULE__, {:remember, key, content, tags})
  end

  @spec recall(String.t()) :: {:ok, Memory.t()} | {:error, :not_found}
  def recall(key) do
    GenServer.call(__MODULE__, {:recall, key})
  end

  @spec forget(String.t()) :: :ok | {:error, :not_found}
  def forget(key) do
    GenServer.call(__MODULE__, {:forget, key})
  end

  @spec search(String.t()) :: {:ok, [Memory.t()]}
  def search(query) do
    GenServer.call(__MODULE__, {:search, query})
  end

  # Truncates all memories — used in tests to reset state between test runs.
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    path = Keyword.get(opts, :db_path, Application.get_env(:overmind, :akasha_db_path, @default_db_path))
    File.mkdir_p!(Path.dirname(path))
    {:ok, conn} = Exqlite.Sqlite3.open(path)
    :ok = Exqlite.Sqlite3.execute(conn, @create_table_sql)
    {:ok, %{conn: conn}}
  end

  @impl true
  def terminate(_reason, %{conn: conn}) do
    Exqlite.Sqlite3.close(conn)
  end

  @impl true
  def handle_call({:remember, key, content, tags}, _from, %{conn: conn} = state) do
    now = System.system_time(:second)
    tags_str = Enum.join(tags, ",")

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(conn, """
      INSERT INTO memories (key, content, tags, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(key) DO UPDATE SET
        content = excluded.content,
        tags = excluded.tags,
        updated_at = excluded.updated_at
      """)

    :ok = Exqlite.Sqlite3.bind(stmt, [key, content, tags_str, now, now])
    :done = Exqlite.Sqlite3.step(conn, stmt)
    :ok = Exqlite.Sqlite3.release(conn, stmt)

    {:reply, do_recall(conn, key), state}
  end

  @impl true
  def handle_call({:recall, key}, _from, %{conn: conn} = state) do
    {:reply, do_recall(conn, key), state}
  end

  @impl true
  def handle_call({:forget, key}, _from, %{conn: conn} = state) do
    {:reply, do_forget(conn, key), state}
  end

  @impl true
  def handle_call({:search, query}, _from, %{conn: conn} = state) do
    pattern = "%#{query}%"

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(conn, """
      SELECT id, key, content, tags, created_at, updated_at FROM memories
      WHERE key LIKE ? OR content LIKE ? OR tags LIKE ?
      ORDER BY updated_at DESC
      """)

    :ok = Exqlite.Sqlite3.bind(stmt, [pattern, pattern, pattern])
    memories = collect_rows(conn, stmt, [])
    :ok = Exqlite.Sqlite3.release(conn, stmt)
    {:reply, {:ok, memories}, state}
  end

  @impl true
  def handle_call(:clear, _from, %{conn: conn} = state) do
    :ok = Exqlite.Sqlite3.execute(conn, "DELETE FROM memories")
    {:reply, :ok, state}
  end

  # Private

  defp do_recall(conn, key) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(conn, """
      SELECT id, key, content, tags, created_at, updated_at FROM memories WHERE key = ?
      """)

    :ok = Exqlite.Sqlite3.bind(stmt, [key])

    result =
      case Exqlite.Sqlite3.step(conn, stmt) do
        {:row, row} -> {:ok, row_to_memory(row)}
        :done -> {:error, :not_found}
      end

    :ok = Exqlite.Sqlite3.release(conn, stmt)
    result
  end

  # Check existence before deleting so we can return :not_found semantics.
  # SQLite DELETE WHERE is silent on no-op, so a pre-check is required.
  defp do_forget(conn, key) do
    case do_recall(conn, key) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, _} ->
        {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "DELETE FROM memories WHERE key = ?")
        :ok = Exqlite.Sqlite3.bind(stmt, [key])
        :done = Exqlite.Sqlite3.step(conn, stmt)
        :ok = Exqlite.Sqlite3.release(conn, stmt)
        :ok
    end
  end

  defp collect_rows(conn, stmt, acc) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, row} -> collect_rows(conn, stmt, [row_to_memory(row) | acc])
      :done -> Enum.reverse(acc)
    end
  end

  defp row_to_memory([id, key, content, tags_str, created_at, updated_at]) do
    tags = parse_tags(tags_str)
    %Memory{id: id, key: key, content: content, tags: tags, created_at: created_at, updated_at: updated_at}
  end

  defp parse_tags(nil), do: []
  defp parse_tags(""), do: []
  defp parse_tags(str), do: String.split(str, ",")
end
