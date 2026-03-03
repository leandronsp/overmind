defmodule OvermindWeb.LogsLiveTest do
  use OvermindWeb.ConnCase

  describe "LogsLive /missions/:id/logs" do
    test "renders back link and logs section for unknown id", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/missions/nonexistent/logs")
      assert html =~ "All missions"
      assert html =~ "Logs"
      assert html =~ "not found"
    end
  end
end
