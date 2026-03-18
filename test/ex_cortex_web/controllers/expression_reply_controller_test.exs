defmodule ExCortexWeb.ExpressionReplyControllerTest do
  use ExCortexWeb.ConnCase, async: true

  test "returns 404 when correlation not found", %{conn: conn} do
    conn = post(conn, "/api/expressions/reply", %{ref: "nonexistent", content: "hello"})
    assert json_response(conn, 404)["error"] == "correlation not found"
  end

  test "returns 400 when ref missing", %{conn: conn} do
    conn = post(conn, "/api/expressions/reply", %{content: "hello"})
    assert json_response(conn, 400)["error"] == "missing ref parameter"
  end

  test "returns 400 when both missing", %{conn: conn} do
    conn = post(conn, "/api/expressions/reply", %{})
    assert json_response(conn, 400)["error"] =~ "missing"
  end
end
