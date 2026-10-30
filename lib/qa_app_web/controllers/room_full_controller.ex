defmodule QaAppWeb.RoomFullController do
  @moduledoc """
  Renders the "room is full" page for visitors who could not join a room
  because it reached its `max_visitors` limit.

  This page is deliberately NOT a LiveView: waiting visitors hold no WebSocket
  connection, which is what the visitor limit exists to protect. Instead the
  response carries a `Refresh` header so each visitor's browser re-checks the
  room with a cheap HTTP GET every few seconds and is admitted automatically
  the moment a spot frees up.
  """

  use QaAppWeb, :controller

  alias QaApp.Events

  # How often a waiting visitor's browser re-checks the room, in seconds.
  @retry_seconds 20

  def show(conn, %{"slug" => slug}) do
    case Events.get_room_by_slug(slug) do
      nil ->
        conn
        |> put_flash(:error, "Event room not found")
        |> redirect(to: "/")

      room ->
        conn
        |> put_resp_header("refresh", "#{@retry_seconds}; url=#{retry_path(slug)}")
        |> render(:show, room: room)
    end
  end

  # The room page the visitor is sent back to for re-admission; its mount runs
  # the capacity gate again.
  defp retry_path(slug), do: ~p"/r/#{slug}"
end
