defmodule Overmind.Mission.Name do
  @moduledoc false

  @adjectives ~w(
    bold brave calm cool dark fast firm keen loud mild
    pale pure rare sharp slim soft swift tall warm wise
  )

  @nouns ~w(
    arc beam bolt core dawn edge flux gate haze iris
    jade knot lens mist node opal peak quad reef spark
  )

  @spec generate() :: String.t()
  def generate do
    adj = Enum.random(@adjectives)
    noun = Enum.random(@nouns)
    "#{adj}-#{noun}"
  end
end
