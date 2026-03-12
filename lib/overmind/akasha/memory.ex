defmodule Overmind.Akasha.Memory do
  @moduledoc false

  @type t :: %__MODULE__{
          id: integer() | nil,
          key: String.t(),
          content: String.t(),
          tags: [String.t()],
          created_at: integer(),
          updated_at: integer()
        }

  defstruct [:id, :key, :content, tags: [], created_at: 0, updated_at: 0]
end
