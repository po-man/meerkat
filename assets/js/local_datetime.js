// Client-side local timezone rendering for date-times.
//
// The server renders the absolute UTC instant as an ISO-8601 string in a
// `data-iso` attribute, plus a UTC-formatted fallback in the element body.
// This hook replaces the fallback with the same wording rendered in the
// viewer's local timezone. `Intl.DateTimeFormat` without a `timeZone` option
// defaults to the browser's local timezone.
//
// Set `data-format="time"` for time-only rendering ("2:30 PM"); the default
// renders a full date and time ("Oct 28, 2026 2:30 PM").

const TIME_FORMATTER = new Intl.DateTimeFormat("en-US", {
  hour: "numeric",
  minute: "2-digit",
})

const DATE_FORMATTER = new Intl.DateTimeFormat("en-US", {
  month: "short",
  day: "numeric",
  year: "numeric",
})

const LocalDateTime = {
  mounted() {
    this.render()
  },

  updated() {
    this.render()
  },

  render() {
    const iso = this.el.dataset.iso
    if (!iso) return

    const date = new Date(iso)
    if (Number.isNaN(date.getTime())) return

    const time = TIME_FORMATTER.format(date)
    this.el.textContent =
      this.el.dataset.format === "time"
        ? time
        : `${DATE_FORMATTER.format(date)} ${time}`
  },
}

export default LocalDateTime
