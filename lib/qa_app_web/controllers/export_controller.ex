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
        questions = Engagement.list_all_questions(room.id)

        header = "ID,Submitted At,Content,Vote Count,Is Asked,Session ID\n"

        rows =
          questions
          |> Enum.map(fn q ->
            submitted_at = Calendar.strftime(q.inserted_at, "%Y-%m-%d %H:%M:%S UTC")
            escaped_content = "\"" <> String.replace(q.content, "\"", "\"\"") <> "\""

            "#{q.id},#{submitted_at},#{escaped_content},#{q.vote_count},#{q.is_asked},#{q.session_id}\n"
          end)
          |> Enum.join("")

        csv_data = header <> rows

        conn
        |> put_resp_content_type("text/csv")
        |> put_resp_header(
          "content-disposition",
          "attachment; filename=\"#{room.slug}-questions.csv\""
        )
        |> send_resp(200, csv_data)
    end
  end

  def qr(conn, %{"slug" => slug}) do
    url = QaAppWeb.Endpoint.url() <> "/r/" <> slug

    case QRCode.create(url) do
      {:ok, qr} ->
        png_binary = QRCode.render(qr)

        conn
        |> put_resp_content_type("image/png")
        |> send_resp(200, png_binary)

      {:error, _} ->
        conn
        |> send_resp(500, "Failed to generate QR code")
    end
  end
end
