defmodule Overmind.Mission.NameTest do
  use ExUnit.Case

  alias Overmind.Mission.Name

  describe "generate/0" do
    test "returns adjective-noun format" do
      name = Name.generate()
      assert Regex.match?(~r/^[a-z]+-[a-z]+$/, name)
    end

    test "produces varied names" do
      names = for _ <- 1..20, do: Name.generate()
      assert length(Enum.uniq(names)) > 1
    end
  end
end
