defmodule OvermindTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  test "hello prints banner" do
    output = capture_io(fn -> Overmind.hello() end)
    assert output =~ "Overmind v0.1.0"
    assert output =~ "Kubernetes for AI Agents"
  end
end
