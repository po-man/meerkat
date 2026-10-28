defmodule QaAppWeb.DateTimeHelpers do
  @moduledoc """
  Helpers for rendering date-times in templates.

  Timestamps are stored as UTC (`:utc_datetime`). Templates render the absolute
  instant with `datetime_iso/1` into a `data-iso` attribute, which the
  `LocalDateTime` JS hook re-formats in the viewer's local timezone.
  """

  @doc """
  Returns the ISO-8601 representation of a UTC `DateTime`, e.g.
  `"2026-10-28T14:30:00Z"`, suitable for client-side formatting.

  Returns `nil` for non-`DateTime` values so templates can keep their existing
  defensive fallbacks.
  """
  def datetime_iso(%DateTime{} = datetime) do
    DateTime.to_iso8601(datetime)
  end

  def datetime_iso(_), do: nil
end
