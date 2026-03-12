defmodule OvermindWeb.MissionLiveTest do
  use OvermindWeb.ConnCase

  describe "MissionLive /" do
    test "renders dashboard heading", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Overmind Dashboard"
    end

    test "shows empty message when no missions running", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "No missions running"
    end
  end
end
