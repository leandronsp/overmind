defmodule Overmind.Provider.ClaudeTest do
  use ExUnit.Case

  alias Overmind.Provider.Claude

  describe "build_command/1" do
    test "wraps prompt with claude -p flags" do
      assert Claude.build_command("capital da australia") ==
               "claude -p 'capital da australia' --output-format stream-json --verbose"
    end

    test "escapes single quotes in prompt" do
      assert Claude.build_command("what's up") ==
               "claude -p 'what'\\''s up' --output-format stream-json --verbose"
    end
  end

  describe "build_session_command/0" do
    test "returns claude with stream-json flags" do
      cmd = Claude.build_session_command()
      assert cmd =~ "claude -p"
      assert cmd =~ "--input-format stream-json"
      assert cmd =~ "--output-format stream-json"
      assert cmd =~ "--verbose"
    end
  end

  describe "build_input_message/1" do
    test "returns stream-json user message" do
      msg = Claude.build_input_message("hello")
      {:ok, parsed} = JSON.decode(msg)
      assert parsed["type"] == "user"
      assert parsed["message"]["role"] == "user"
      assert parsed["message"]["content"] == "hello"
    end

    test "message ends with newline" do
      msg = Claude.build_input_message("hello")
      assert String.ends_with?(msg, "\n")
    end
  end

  describe "parse_line/1" do
    test "non-JSON returns plain event" do
      assert Claude.parse_line("hello world") == {{:plain, "hello world"}, nil}
    end

    test "empty string returns plain event" do
      assert Claude.parse_line("") == {{:plain, ""}, nil}
    end

    test "system type" do
      json = ~s({"type":"system","subtype":"init","session_id":"abc123"})
      {event, raw} = Claude.parse_line(json)
      assert {:system, %{"subtype" => "init"}} = event
      assert raw["type"] == "system"
    end

    test "assistant text content" do
      json =
        ~s({"type":"assistant","message":{"content":[{"type":"text","text":"Canberra"}]}})

      {event, raw} = Claude.parse_line(json)
      assert event == {:text, "Canberra"}
      assert raw["type"] == "assistant"
    end

    test "assistant tool_use content" do
      json =
        ~s({"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}})

      {event, raw} = Claude.parse_line(json)
      assert event == {:tool_use, "Bash"}
      assert raw["type"] == "assistant"
    end

    test "assistant thinking content" do
      json =
        ~s({"type":"assistant","message":{"content":[{"type":"thinking","thinking":"hmm"}]}})

      {event, raw} = Claude.parse_line(json)
      assert event == {:thinking, "hmm"}
      assert raw["type"] == "assistant"
    end

    test "assistant with multiple content blocks — text wins" do
      json =
        ~s({"type":"assistant","message":{"content":[{"type":"thinking","thinking":"hmm"},{"type":"text","text":"answer"}]}})

      {event, _raw} = Claude.parse_line(json)
      assert event == {:text, "answer"}
    end

    test "assistant with tool_use and thinking — tool_use wins" do
      json =
        ~s({"type":"assistant","message":{"content":[{"type":"thinking","thinking":"hmm"},{"type":"tool_use","name":"Read","input":{}}]}})

      {event, _raw} = Claude.parse_line(json)
      assert event == {:tool_use, "Read"}
    end

    test "user tool_result content" do
      json =
        ~s({"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"123","content":"ok"}]}})

      {event, raw} = Claude.parse_line(json)
      assert {:tool_result, %{"tool_use_id" => "123"}} = event
      assert raw["type"] == "user"
    end

    test "result success" do
      json =
        ~s({"type":"result","subtype":"success","result":"Done!","duration_ms":1500,"cost_usd":0.003,"is_error":false})

      {event, raw} = Claude.parse_line(json)

      assert {:result, %{text: "Done!", duration_ms: 1500, cost_usd: 0.003}} = event
      assert raw["type"] == "result"
    end

    test "result error" do
      json = ~s({"type":"result","subtype":"error_max_turns","error":"Max turns reached","is_error":true})

      {event, raw} = Claude.parse_line(json)
      assert {:result, %{text: "Max turns reached"}} = event
      assert raw["type"] == "result"
    end

    test "unknown type returns ignored" do
      json = ~s({"type":"unknown_thing","data":"stuff"})
      {event, raw} = Claude.parse_line(json)
      assert {:ignored, %{"type" => "unknown_thing"}} = event
      assert raw["type"] == "unknown_thing"
    end

    test "assistant with empty content" do
      json = ~s({"type":"assistant","message":{"content":[]}})
      {event, raw} = Claude.parse_line(json)
      assert {:ignored, _} = event
      assert raw["type"] == "assistant"
    end
  end

  describe "format_for_logs/1" do
    test "text event" do
      assert Claude.format_for_logs({:text, "Hello"}) == "Hello\n"
    end

    test "tool_use event returns empty" do
      assert Claude.format_for_logs({:tool_use, "Bash"}) == ""
    end

    test "result event returns empty" do
      assert Claude.format_for_logs({:result, %{text: "Done!"}}) == ""
    end

    test "plain event" do
      assert Claude.format_for_logs({:plain, "hello"}) == "hello\n"
    end

    test "thinking event returns empty" do
      assert Claude.format_for_logs({:thinking, "hmm"}) == ""
    end

    test "system event returns empty" do
      assert Claude.format_for_logs({:system, %{}}) == ""
    end

    test "tool_result event returns empty" do
      assert Claude.format_for_logs({:tool_result, %{}}) == ""
    end

    test "ignored event returns empty" do
      assert Claude.format_for_logs({:ignored, %{}}) == ""
    end
  end
end
