defmodule QaAppWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  The design system is a matte, editorial, Swiss-minimal language:

    * Two-color warm monochrome (paper + ink) with a single clay accent,
      exposed as semantic Tailwind utilities (`bg-paper`, `text-ink`,
      `border-line`, `text-accent`, ...) defined in `assets/css/app.css`.
    * Sharp geometry: 4px corners on controls, 8px on panels, 1px hairlines
      for separation. No shadows, no gradients, no blur.
    * Geist Sans for text, Geist Mono for meta, overlines, and numerals.

  See `assets/css/app.css` for the token definitions.
  """
  use Phoenix.Component
  use Gettext, backend: QaAppWeb.Gettext

  import QaAppWeb.DateTimeHelpers, only: [datetime_iso: 1]

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash
        id="welcome-back"
        kind={:info}
        phx-mounted={show("#welcome-back") |> JS.remove_attribute("hidden")}
        hidden
      >
        Welcome Back!
      </.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"

  attr :autodismiss,
       :boolean,
       default: true,
       doc: "whether the flash auto-dismisses after a few seconds (with a bottom progress bar)"

  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-hook=".FlashNotice"
      data-flash-kind={@kind}
      data-flash-autodismiss={to_string(@autodismiss)}
      role="alert"
      class="fixed top-4 right-4 z-50 w-80 max-w-[calc(100vw-2rem)]"
      {@rest}
    >
      <div class={[
        "relative overflow-hidden bg-paper border border-line-strong border-l-2 rounded p-3 flex items-start gap-2.5",
        if(@kind == :info, do: "border-l-accent", else: "border-l-danger")
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-4 shrink-0 text-ink-2" />
        <.icon
          :if={@kind == :error}
          name="hero-exclamation-circle"
          class="size-4 shrink-0 text-danger"
        />
        <div class="flex-1 min-w-0 text-[13px] leading-snug text-ink">
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <span
          :if={@autodismiss}
          aria-hidden="true"
          class="flash-progress absolute bottom-0 left-0 right-0 h-0.5 bg-accent origin-left"
        ></span>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".FlashNotice">
        export default {
          mounted() {
            if (this.el.dataset.flashAutodismiss !== "true") return;
            this.kind = this.el.dataset.flashKind;
            this.dismissTimer = setTimeout(() => this.dismiss(), 5000);
          },
          dismiss() {
            const el = this.el;
            el.style.transition = "opacity 300ms ease, transform 300ms ease";
            el.style.opacity = "0";
            el.style.transform = "translateY(-6px)";

            this.hideTimer = setTimeout(() => {
              // Clear the server-side flash now that the bubble is gone, so it
              // won't reappear on a later render.
              if (this.el.isConnected) {
                this.pushEvent("lv:clear-flash", {key: this.kind});
              }
              el.remove();
            }, 300);
          },
          destroyed() {
            clearTimeout(this.dismissTimer);
            clearTimeout(this.hideTimer);
          }
        }
      </script>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any
  attr :variant, :string, values: ~w(primary ghost danger)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    base =
      "inline-flex items-center justify-center gap-2 h-10 px-4 rounded text-sm font-medium transition-colors duration-150 disabled:opacity-40 disabled:cursor-not-allowed disabled:pointer-events-none"

    variants = %{
      nil => base <> " bg-transparent border border-line-strong text-ink hover:border-ink",
      "primary" => base <> " bg-ink text-paper hover:bg-accent",
      "ghost" => base <> " bg-transparent border border-line-strong text-ink hover:border-ink",
      "danger" => base <> " bg-transparent text-danger hover:underline"
    }

    assigns =
      assign_new(assigns, :class, fn ->
        [Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://phoenix-html.hexdocs.pm/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="mb-2">
      <label for={@id} class="flex items-center gap-2.5 cursor-pointer select-none text-sm text-ink">
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={@class || "size-4 rounded-sm border border-line-strong"}
          {@rest}
        />
        {@label}
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="mb-2">
      <label
        :if={@label}
        for={@id}
        class="block font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3 mb-2"
      >
        {@label}
      </label>
      <select
        id={@id}
        name={@name}
        class={[
          @class || input_base_class() <> " h-10",
          @errors != [] && (@error_class || "border-danger")
        ]}
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="mb-2">
      <label
        :if={@label}
        for={@id}
        class="block font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3 mb-2"
      >
        {@label}
      </label>
      <textarea
        id={@id}
        name={@name}
        class={[
          @class || input_base_class() <> " py-3 h-24 resize-none leading-relaxed",
          @errors != [] && (@error_class || "border-danger")
        ]}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="mb-2">
      <label
        :if={@label}
        for={@id}
        class="block font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3 mb-2"
      >
        {@label}
      </label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          @class || input_base_class() <> " h-10",
          @errors != [] && (@error_class || "border-danger")
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  @doc """
  Renders a switch-style toggle bound to a boolean form field, such as a
  room's `is_active` status.

  Unlike `input/1`, the control is a sliding switch that matches the app's
  design language while keeping the standard hidden-false / visible-checkbox
  semantics so the value round-trips through the form.

  ## Examples

      <.toggle field={@form[:is_active]} label="Room is open" hint="Visitors can join while this is on." />
      <.toggle name="room[is_active]" value={@active} label="Room is open" />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :hint, :string, default: nil
  attr :value, :any

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:is_active]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for the toggle"
  attr :rest, :global, include: ~w(disabled form)

  def toggle(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns[:id] || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:checked, fn -> Phoenix.HTML.Form.normalize_value("checkbox", field.value) end)
    |> toggle()
  end

  def toggle(assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div>
      <div class="flex items-center justify-between gap-6">
        <div class="min-w-0">
          <p :if={@label} class="text-sm font-medium text-ink">{@label}</p>
          <p :if={@hint} class="mt-1 text-xs leading-relaxed text-ink-3">{@hint}</p>
        </div>
        <label class="relative h-5 w-9 shrink-0 cursor-pointer">
          <input
            type="hidden"
            name={@name}
            value="false"
            disabled={@rest[:disabled]}
            form={@rest[:form]}
          />
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class="peer sr-only"
            disabled={@rest[:disabled]}
            form={@rest[:form]}
          />
          <div class="absolute inset-0 rounded-full border border-line-strong bg-surface transition-colors duration-150 peer-checked:border-accent peer-checked:bg-accent">
          </div>
          <span class="absolute top-1/2 left-0.5 h-3.5 w-3.5 -translate-y-1/2 rounded-full bg-paper border border-line-strong transition-transform duration-150 peer-checked:translate-x-[16px] peer-checked:border-transparent"></span>
        </label>
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  @doc """
  Renders a compact switch that flips a room's active/inactive status
  directly from a list row.

  The switch posts the `toggle_room_active` event with the room's id, which
  the admin and moderator listings handle server-side.

  ## Examples

      <.status_toggle room={room} />
  """
  attr :room, :map, required: true

  def status_toggle(assigns) do
    ~H"""
    <button
      type="button"
      role="switch"
      id={"room-active-toggle-#{@room.id}"}
      aria-checked={to_string(@room.is_active)}
      aria-label={"Toggle #{@room.title} active state"}
      title={if(@room.is_active, do: "Deactivate room", else: "Activate room")}
      phx-click="toggle_room_active"
      phx-value-id={@room.id}
      class={[
        "relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border transition-colors duration-150",
        if(@room.is_active,
          do: "bg-accent border-accent",
          else: "bg-surface border-line-strong hover:border-ink"
        )
      ]}
    >
      <span class={[
        "inline-block h-3.5 w-3.5 rounded-full border transition-transform duration-150",
        if(@room.is_active,
          do: "translate-x-[16px] bg-paper border-accent",
          else: "translate-x-[2px] bg-paper border-line-strong"
        )
      ]}></span>
    </button>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-1.5 items-center text-xs text-danger">
      <.icon name="hero-exclamation-circle" class="size-3.5 shrink-0" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  # Shared base class for text-like inputs (select / textarea / text)
  defp input_base_class do
    "w-full bg-transparent border border-line-strong rounded px-3 text-sm text-ink placeholder:text-ink-3 transition-colors focus:outline-none focus:border-ink"
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[
      @actions != [] && "flex items-center justify-between gap-6",
      "pb-4 border-b border-line"
    ]}>
      <div>
        <h2 class="text-xl font-semibold tracking-[-0.02em] text-ink">
          {render_slot(@inner_block)}
        </h2>
        <p :if={@subtitle != []} class="mt-1 text-sm text-ink-2">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="w-full text-left text-sm">
      <thead>
        <tr>
          <th
            :for={col <- @col}
            class="py-3 pr-4 font-mono text-[11px] font-normal uppercase tracking-[0.14em] text-ink-3 border-b border-line-strong whitespace-nowrap"
          >
            {col[:label]}
          </th>
          <th :if={@action != []} class="py-3 border-b border-line-strong text-right">
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr
          :for={row <- @rows}
          id={@row_id && @row_id.(row)}
          class="border-b border-line hover:bg-surface transition-colors"
        >
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={[@row_click && "hover:cursor-pointer", "py-4 pr-4 align-top text-ink"]}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="py-4 text-right align-top">
            <div class="flex gap-3 justify-end">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="divide-y divide-line border-y border-line">
      <li :for={item <- @item} class="py-3">
        <div class="font-mono text-[11px] uppercase tracking-[0.14em] text-ink-3">{item.title}</div>
        <div class="mt-1 text-sm text-ink">{render_slot(item)}</div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  Renders a date-time in the viewer's local timezone.

  The server renders the absolute UTC instant as an ISO-8601 string in a
  `data-iso` attribute and a UTC-formatted fallback as the element body. The
  `LocalDateTime` JS hook (see `assets/js/local_datetime.js`) replaces the
  fallback with the same wording rendered in the viewer's local timezone.

  ## Examples

      <.local_datetime id="room-expiry" datetime={expires_at} />
      <.local_datetime id={"q-time-\#{question.id}"} datetime={question.inserted_at} format={:time} class="tabular-nums" />
  """
  attr :datetime,
       :any,
       default: nil,
       doc: "the UTC DateTime to render; nil renders a dash"

  attr :format,
       :atom,
       values: [:time, :datetime],
       default: :datetime,
       doc: "the presentation to use for the local rendering"

  attr :id, :string, required: true, doc: "the unique DOM id (required by the phx-hook)"

  attr :class,
       :string,
       default: nil,
       doc: "optional classes to add to the span"

  def local_datetime(assigns) do
    ~H"""
    <span
      id={@id}
      data-iso={datetime_iso(@datetime)}
      data-format={Atom.to_string(@format)}
      phx-hook="LocalDateTime"
      class={@class}
    >
      {local_datetime_fallback(@datetime, @format)}
    </span>
    """
  end

  defp local_datetime_fallback(%DateTime{} = datetime, :time) do
    Calendar.strftime(datetime, "%I:%M %p") <> " UTC"
  end

  defp local_datetime_fallback(%DateTime{} = datetime, :datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %I:%M %p") <> " UTC"
  end

  defp local_datetime_fallback(_, _), do: "—"

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(QaAppWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(QaAppWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
