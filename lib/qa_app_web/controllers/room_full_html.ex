defmodule QaAppWeb.RoomFullHTML do
  @moduledoc """
  Renders the "room is full" page served by `QaAppWeb.RoomFullController`.
  """
  use QaAppWeb, :html

  embed_templates "room_full_html/*"
end
