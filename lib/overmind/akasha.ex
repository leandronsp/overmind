defmodule Overmind.Akasha do
  @moduledoc false

  alias Overmind.Akasha.{Memory, Store}

  @spec remember(String.t(), String.t(), [String.t()]) :: {:ok, Memory.t()} | {:error, term()}
  def remember(key, content, tags \\ []) do
    Store.remember(key, content, tags)
  end

  @spec recall(String.t()) :: {:ok, Memory.t()} | {:error, :not_found}
  def recall(key), do: Store.recall(key)

  @spec forget(String.t()) :: :ok | {:error, :not_found}
  def forget(key), do: Store.forget(key)

  @spec search(String.t()) :: {:ok, [Memory.t()]}
  def search(query), do: Store.search(query)
end
