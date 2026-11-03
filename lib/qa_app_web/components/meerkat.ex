defmodule QaAppWeb.Components.Meerkat do
  @moduledoc """
  The Meerkat key visual.

  The mascot is rendered as one inline SVG so that it can be themed by the
  design tokens rather than shipped as a picture, and animated without a
  canvas, a runtime, or a vendored library.

  The figure is grouped by body part and every animated part carries a
  `data-part` hook:

    * `assets/css/app.css` owns the continuous ambient motion (breathing
      body, tail sway) and the pivot points, so the meerkat is alive from the
      first paint and keeps working if JavaScript never runs.
    * `assets/js/meerkat.js` owns the discrete beats (blink, eye-roll, the
      paw raise it keeps insisting on, and the "reach higher" stretch).

  Whole-body motion is deliberately vertical only. The figure is a standing
  animal, so any rotation of the body reads as an unnatural shake; the body
  breathes and reaches, and only the tail, head and arm rotate.

  The `viewBox` keeps its origin at `0 0` and only trims the empty space below
  the feet, so the pivot coordinates in the stylesheet address the artwork
  directly in the original drawing space.

  Rendered once per page: the internal `meerkat-*` ids are fixed.
  """

  use Phoenix.Component

  attr :class, :any, default: nil
  attr :rest, :global

  def meerkat(assigns) do
    ~H"""
    <div data-meerkat class={@class} aria-hidden="true" {@rest}>
      <svg viewBox="0 0 373 414" fill="none" xmlns="http://www.w3.org/2000/svg" focusable="false">
        <defs>
          <%!-- Masks and clips are stencils: only their alpha channel is used. --%>
          <mask
            id="meerkat-mask-tail"
            style="mask-type:alpha"
            maskUnits="userSpaceOnUse"
            x="10"
            y="306"
            width="150"
            height="101"
          >
            <path
              d="M144.293 309.98C155.291 319.445 169.793 336.98 146.794 367.979C138.033 379.788 117.905 391.606 99.7937 400.479C84.584 407.931 64.7939 405.979 51.2923 405.979C32.5524 405.979 10.7944 400.479 10.7933 394.478C10.7923 388.978 31.6522 387.407 50.2926 385.478C64.7926 383.978 74.9045 380.335 88.793 370.479C99.3623 362.978 107.971 350.979 113.293 340.979C129.794 309.98 133.294 300.514 144.293 309.98Z"
              fill="#000"
            />
          </mask>

          <mask
            id="meerkat-mask-body"
            style="mask-type:alpha"
            maskUnits="userSpaceOnUse"
            x="123"
            y="22"
            width="159"
            height="351"
          >
            <path
              d="M281 279.004C279.821 324.265 252 374 197.001 372C134.542 369.729 119.071 332.004 124.999 279.004C129.889 235.284 147.499 212.004 151.999 159.504C156.499 107.003 143.999 98.5 143.999 64.5028C143.999 40.9722 176.267 20.2355 202 23.0003C229.486 25.9533 258.807 33.6528 265 56.003C272.439 82.8479 251.5 90.0035 254.5 120.504C257.5 151.004 283.5 183.004 281 279.004Z"
              fill="#000"
            />
          </mask>

          <mask
            id="meerkat-mask-flank"
            style="mask-type:alpha"
            maskUnits="userSpaceOnUse"
            x="116"
            y="24"
            width="106"
            height="349"
          >
            <path
              d="M221 311.5C224.151 331.756 218 372.762 197.001 371.998C134.542 369.727 111.072 332.002 117 279.002C121.89 235.282 139.5 212.002 144 159.502C148.5 107.001 136 98.498 136 64.5008C136 40.9703 174 23.4416 188.5 24.9996C203 26.5576 203.342 33.9584 206 56.998C209 83 155.5 81.4961 186 128.498C216.5 175.5 197.001 230 197.001 271.5C198.824 285 215.945 279.002 221 311.5Z"
              fill="#000"
            />
          </mask>

          <mask
            id="meerkat-mask-head"
            style="mask-type:alpha"
            maskUnits="userSpaceOnUse"
            x="135"
            y="0"
            width="149"
            height="126"
          >
            <path
              d="M284 69.3453C284 103.889 260.262 126 209.5 126C158.738 126 135 103.889 135 69.3453C135 34.8017 158.373 0 209.5 0C260.627 0 284 34.8017 284 69.3453Z"
              fill="#000"
            />
          </mask>

          <clipPath id="meerkat-clip-eye-left">
            <path d="M209.419 50.3096C217.079 64.4001 209.828 72.6409 190.465 83.1667C171.102 93.6925 160.243 95.2959 152.584 81.2054C146.813 70.5906 149.915 55.0501 169.418 44.4486C188.92 33.8471 203.649 39.6948 209.419 50.3096Z" />
          </clipPath>

          <clipPath id="meerkat-clip-eye-right">
            <path d="M295.57 73.2309C288.212 87.4811 277.321 86.1089 257.739 75.9971C238.157 65.8854 230.732 57.8006 238.091 43.5504C243.634 32.8153 258.235 26.6558 277.958 36.8403C297.682 47.0248 301.113 62.4958 295.57 73.2309Z" />
          </clipPath>
        </defs>

        <g id="meerkat" data-part="meerkat">
          <%!-- JS owns this wrapper: whole-body beats (the reach). --%>
          <g data-part="ambient">
            <g data-part="leg-back">
              <path
                d="M293 326.5C290.001 360 260.501 396 239.001 396C221.5 396 220 389.5 218.5 330.5C218.5 297.639 222.371 267 247.5 267C272.629 267 293 293.639 293 326.5Z"
                fill="var(--mk-4)"
              />
              <path
                d="M286 402C286.264 408.069 272.449 407 254.5 407C221 407 221 405.5 221 395C221 383.5 224 385 254.5 385C279 385 285.5 390.5 286 402Z"
                fill="var(--mk-4)"
              />
            </g>

            <g data-part="leg-front">
              <path
                d="M222.5 326.5C219.5 360 189.972 394.899 168.5 396C149 397 153.5 384.5 151.5 371.5C146.28 358.488 141.452 358.429 131.5 343.5C120.5 327 128.371 266.5 153.5 266.5C200.499 266.5 222.5 293.639 222.5 326.5Z"
                fill="var(--mk-3)"
              />
              <path
                d="M215.5 402C215.764 408.069 201.949 407 184 407C150.5 407 150.5 405.5 150.5 395C150.5 383.5 153.5 385 184 385C208.5 385 215 390.5 215.5 402Z"
                fill="var(--mk-3)"
              />
            </g>

            <g data-part="tail" mask="url(#meerkat-mask-tail)">
              <ellipse cx="124" cy="360.001" rx="146" ry="113" fill="var(--mk-3)" />
              <ellipse cx="130.5" cy="369.001" rx="78.5" ry="69" fill="var(--mk-accent)" />
            </g>

            <%!-- Behind the torso: the far arm, already raised to ask. --%>
            <g data-part="arm-raised">
              <path
                d="M335.069 45.4058C349.068 49.2238 345.802 71.4053 341.069 90.9057C337.601 105.194 329.107 128.108 316.569 143.906C306.04 157.172 288.356 172.442 277.069 179.406C261.121 189.247 250.57 179.406 246.569 166.906C243.131 156.165 243.106 153.172 249.069 135.406C253.289 122.832 269.232 127.098 283.569 117.906C295.403 110.318 306.531 93.7402 309.069 82.4057C316.569 48.9053 321.069 41.5877 335.069 45.4058Z"
                fill="var(--mk-4)"
              />
            </g>

            <g data-part="torso-front" mask="url(#meerkat-mask-body)">
              <ellipse cx="207.5" cy="197" rx="141.5" ry="184" fill="var(--mk-2)" />
              <ellipse cx="211.5" cy="244.5" rx="84.5" ry="107.5" fill="var(--mk-1)" />
            </g>

            <g data-part="torso-back" mask="url(#meerkat-mask-flank)">
              <ellipse cx="144.5" cy="207.5" rx="139.5" ry="207.5" fill="var(--mk-3)" />
              <path
                d="M163.936 221.76C160.291 224.658 146.639 217.762 136.815 205.408C126.991 193.055 117.5 182.148 126.649 174.872C137.892 165.931 139.492 183.209 148.058 196.467C157.23 210.664 167.581 218.861 163.936 221.76Z"
                fill="var(--mk-4)"
              />
              <path
                d="M171.486 251.068C169.022 255.255 152.5 253 134 244.5C116.047 236.251 100.5 227.5 106.858 213.039C115.983 192.285 125.095 217.883 141.223 229.247C158.492 241.415 173.95 246.881 171.486 251.068Z"
                fill="var(--mk-4)"
              />
              <path
                d="M171 276.5C169.665 281.171 150.363 284.278 130.323 280.691C110.875 277.21 93.6291 272.638 96.1565 257.044C99.7837 234.665 115.025 257.159 133.488 264.114C153.258 271.561 172.335 271.829 171 276.5Z"
                fill="var(--mk-4)"
              />
              <path
                d="M171.431 208.123C169.315 210.817 176.975 224.269 188.973 235.54C200.616 246.478 211.822 255.591 219.836 247.821C231.337 236.671 210.476 235.918 197.256 226.978C183.1 217.405 173.548 205.43 171.431 208.123Z"
                fill="var(--mk-4)"
              />
            </g>

            <%!-- In front of the torso: the near arm, bent across the belly. --%>
            <g data-part="arm-near">
              <path
                d="M257 249C253.427 255.906 243.366 256.865 236.5 252.5C230.552 248.718 228 239.375 224.5 238.5C206.5 234 198.5 235.5 177 211C165.829 198.27 162.442 175.495 157.999 162.999C151.72 145.343 153.437 128.791 166.499 127.5C177.721 126.391 181.838 123.185 194.5 137C210.999 155 208.518 165.555 214.5 181.5C219.438 194.662 225.949 200.643 236.5 205.5C253.5 213.327 263.668 236.112 257 249Z"
                fill="var(--mk-3)"
              />
            </g>

            <g data-part="head-unit">
              <g data-part="ears">
                <g data-part="ear-right">
                  <ellipse cx="275" cy="39" rx="31" ry="39" fill="var(--mk-3)" />
                  <ellipse cx="274.5" cy="40" rx="21.5" ry="27" fill="var(--mk-ear)" />
                </g>
                <g data-part="ear-left">
                  <circle cx="128" cy="52" r="39" fill="var(--mk-3)" />
                  <circle cx="127" cy="53" r="27" fill="var(--mk-ear)" />
                </g>
              </g>

              <g data-part="face" mask="url(#meerkat-mask-head)">
                <path
                  d="M284 69.3453C284 103.889 260.262 126 209.5 126C158.738 126 135 103.889 135 69.3453C135 34.8017 158.373 0 209.5 0C260.627 0 284 34.8017 284 69.3453Z"
                  fill="var(--mk-3)"
                />
                <path
                  d="M284 69.346C284 103.89 260.262 126.001 209.5 126.001C158.738 126.001 135 103.89 135 69.346C135 34.8024 161.373 73.0009 212.5 73.0009C263.627 73.0009 284 34.8024 284 69.346Z"
                  fill="var(--mk-2)"
                />
                <path
                  d="M255 85.5C263 113 219 128.506 186 126C153 123.494 135 103.167 135 75C135 46.8335 157.833 24 186 24C214.167 24 247 58 255 85.5Z"
                  fill="var(--mk-1)"
                />
                <path
                  d="M223.501 41.5001C221.21 54.0001 240 69.5001 256.501 69.5001C273.002 69.5001 284.215 64.4998 280.501 51.5C276.786 38.5002 263.152 16.746 246.5 18.0002C229.848 19.2543 225.792 29.0001 223.501 41.5001Z"
                  fill="var(--mk-blush)"
                />

                <g data-part="eyes">
                  <g data-part="eye-left">
                    <path
                      d="M209.419 50.3096C217.079 64.4001 209.828 72.6409 190.465 83.1667C171.102 93.6925 160.243 95.2959 152.584 81.2054C146.813 70.5906 149.915 55.0501 169.418 44.4486C188.92 33.8471 203.649 39.6948 209.419 50.3096Z"
                      fill="var(--mk-4)"
                    />
                    <g data-part="pupil-left" clip-path="url(#meerkat-clip-eye-left)">
                      <circle cx="193" cy="61.001" r="10" fill="var(--mk-5)" />
                      <circle cx="197" cy="57.001" r="3" fill="var(--mk-spark)" />
                    </g>
                  </g>

                  <g data-part="eye-right">
                    <path
                      d="M295.57 73.2309C288.212 87.4811 277.321 86.1089 257.739 75.9971C238.157 65.8854 230.732 57.8006 238.091 43.5504C243.634 32.8153 258.235 26.6558 277.958 36.8403C297.682 47.0248 301.113 62.4958 295.57 73.2309Z"
                      fill="var(--mk-4)"
                    />
                    <g data-part="pupil-right" clip-path="url(#meerkat-clip-eye-right)">
                      <circle cx="254.998" cy="54.0039" r="10" fill="var(--mk-5)" />
                      <circle cx="258.998" cy="50.0039" r="3" fill="var(--mk-spark)" />
                    </g>
                  </g>
                </g>

                <path
                  d="M251.58 79.9415C252.247 84.831 245.612 91.9764 238.716 92.9174C231.82 93.8583 223.514 88.7516 222.846 83.8621C222.179 78.9726 226.423 76.428 236.283 75.0826C246.143 73.7373 250.913 75.052 251.58 79.9415Z"
                  fill="var(--mk-5)"
                />
              </g>
            </g>
          </g>
        </g>
      </svg>
    </div>
    """
  end
end
