defmodule QaAppWeb.HealthControllerTest do
  # Not async: the failure case stops the shared Repo process.
  use QaAppWeb.ConnCase, async: false

  test "GET /healthz reports ok when the database answers", %{conn: conn} do
    conn = get(conn, ~p"/healthz")

    assert response(conn, 200) == "ok"
  end

  test "GET /healthz needs no session and sets no cookie", %{conn: conn} do
    conn = get(conn, ~p"/healthz")

    assert conn.status == 200
    assert get_resp_header(conn, "set-cookie") == []
  end

  test "GET /healthz reports 503 when the database is unreachable", %{conn: conn} do
    repo = Process.whereis(QaApp.Repo)
    assert is_pid(repo)

    :ok = Supervisor.terminate_child(QaApp.Supervisor, QaApp.Repo)

    try do
      conn = get(conn, ~p"/healthz")
      assert response(conn, 503) == "unavailable"
    after
      {:ok, _pid} = Supervisor.restart_child(QaApp.Supervisor, QaApp.Repo)
    end
  end
end
