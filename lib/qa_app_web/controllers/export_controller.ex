defmodule QaAppWeb.ExportController do
  use QaAppWeb, :controller

  alias QaApp.Events
  alias QaApp.Engagement

  def csv(conn, %{"slug" => slug}) do
    case Events.get_room_by_slug(slug) do
      nil ->
        conn
        |> put_flash(:error, "Room not found")
        |> redirect(to: "/")

      room ->
        if authorized?(conn, room) do
          questions = Engagement.list_all_questions(room.id)

          rows =
            Enum.map(questions, fn q ->
              submitted_at = Calendar.strftime(q.inserted_at, "%Y-%m-%d %H:%M:%S UTC")
              escaped_content = "\"" <> String.replace(q.content, "\"", "\"\"") <> "\""

              "#{submitted_at},#{escaped_content},#{q.vote_count},#{q.is_asked}\n"
            end)

          csv_data = "Submitted At,Content,Vote Count,Is Asked\n" <> Enum.join(rows, "")

          conn
          |> put_resp_content_type("text/csv")
          |> put_resp_header(
            "content-disposition",
            "attachment; filename=\"#{room.slug}-questions.csv\""
          )
          |> send_resp(200, csv_data)
        else
          conn
          |> put_flash(:error, "You are not authorized to export this room.")
          |> redirect(to: "/")
        end
    end
  end

  def qr(conn, %{"slug" => slug}) do
    url = QaAppWeb.Endpoint.url() <> "/r/" <> slug

    case url |> QRCode.create() |> QRCode.render(:png) do
      {:ok, png_binary} ->
        conn
        |> put_resp_content_type("image/png")
        |> send_resp(200, png_binary)

      {:error, _} ->
        conn
        |> send_resp(500, "Failed to generate QR code")
    end
  end

  defp authorized?(conn, room) do
    user = conn.assigns[:current_user]
    user && (user.role == :admin || user.id == room.moderator_id)
  end
end
