defmodule TomatoWeb.GraphLive.CanvasComponents do
  @moduledoc """
  SVG canvas function components for the Tomato graph editor plus the
  shared presentation helpers they rely on.

  Public function components:

    * `graph_node/1` — a single node on the canvas (leaf/gateway/machine)
    * `edge_line/1` — a Bezier edge between two nodes
    * `oodn_node/1` — the OODN config panel rendered on the root floor

  The style and geometry helpers (`node_color/1`, `node_rect_class/2`,
  `node_text_class/1`, `has_content?/1`, `node_half_width/1`, etc.) are
  public so they can be imported and used directly inside the LiveView's
  render template.
  """

  use Phoenix.Component

  @oodn_max_visible 6

  # --- Style / geometry helpers (imported into GraphLive scope) ---

  @doc "True if a node has non-empty leaf content."
  def has_content?(%{content: c}) when is_binary(c) and c != "", do: true
  def has_content?(_), do: false

  @doc "Tailwind class for the node dot colour in the sidebar list."
  def node_color(:input), do: "bg-success"
  def node_color(:output), do: "bg-error"
  def node_color(:leaf), do: "bg-info"
  def node_color(:gateway), do: "bg-secondary"
  def node_color(_), do: "bg-base-content/30"

  @doc "Tailwind fill/stroke class for the SVG node rectangle."
  def node_rect_class(:input, true), do: "fill-success/20 stroke-success"
  def node_rect_class(:input, false), do: "fill-success/10 stroke-success/50"
  def node_rect_class(:output, true), do: "fill-error/20 stroke-error"
  def node_rect_class(:output, false), do: "fill-error/10 stroke-error/50"
  def node_rect_class(:leaf, true), do: "fill-info/20 stroke-info"
  def node_rect_class(:leaf, false), do: "fill-info/10 stroke-info/50"
  def node_rect_class(:gateway, true), do: "fill-secondary/20 stroke-secondary"
  def node_rect_class(:gateway, false), do: "fill-secondary/10 stroke-secondary/50"

  def node_rect_class(_, selected),
    do:
      if(selected,
        do: "fill-base-300 stroke-base-content",
        else: "fill-base-200 stroke-base-content/30"
      )

  @doc "Tailwind class for the SVG node label text."
  def node_text_class(true), do: "fill-base-content font-semibold"
  def node_text_class(false), do: "fill-base-content/70"

  @doc """
  Half-width of the node rectangle in canvas units — used by edge_line
  to position the Bezier curve endpoints just outside the node shape.
  """
  def node_half_width(node) do
    cond do
      Tomato.Node.machine?(node) -> 80
      node.type == :leaf && has_content?(node) -> 80
      true -> 60
    end
  end

  @doc """
  Build up to `max_lines` preview lines from a leaf node's content,
  skipping blanks and truncating long lines.
  """
  def content_preview(nil, _), do: []

  def content_preview(content, max_lines) do
    content
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.take(max_lines)
    |> Enum.map(&truncate_line/1)
  end

  @doc "Trim leading whitespace and truncate to ~22 characters."
  def truncate_line(line) do
    trimmed = String.trim_leading(line)

    if String.length(trimmed) > 22 do
      String.slice(trimmed, 0, 20) <> ".."
    else
      trimmed
    end
  end

  @doc "Truncate an OODN value for display in the panel."
  def truncate_value(v, max) when byte_size(v) > max, do: String.slice(v, 0, max) <> ".."
  def truncate_value(v, _max), do: v

  # --- Canvas components ---

  attr :node, :map, required: true
  attr :selected, :boolean, default: false
  attr :connecting, :boolean, default: false

  def graph_node(assigns) do
    is_machine = Tomato.Node.machine?(assigns.node)
    has_preview = assigns.node.type == :leaf && has_content?(assigns.node)
    preview_lines = if has_preview, do: content_preview(assigns.node.content, 3), else: []

    assigns =
      assigns
      |> assign(:is_machine, is_machine)
      |> assign(:has_preview, has_preview)
      |> assign(:preview_lines, preview_lines)

    ~H"""
    <g
      class="graph-node cursor-grab active:cursor-grabbing"
      data-node-id={@node.id}
      data-node-type={if @is_machine, do: "machine", else: @node.type}
      data-node-name={@node.name}
      transform={"translate(#{@node.position.x}, #{@node.position.y})"}
      phx-click="select_node"
      phx-value-node-id={@node.id}
    >
      <%!-- Machine node --%>
      <rect
        :if={@is_machine}
        x="-80"
        y="-25"
        width="160"
        height="50"
        rx="8"
        fill="#fef3c7"
        stroke="#d97706"
        stroke-width={if @selected, do: "3", else: "2"}
      />
      <%!-- Leaf with preview (taller) --%>
      <rect
        :if={!@is_machine && @has_preview}
        x="-80"
        y="-30"
        width="160"
        height="80"
        rx="6"
        class={[
          "stroke-2 transition-colors",
          node_rect_class(@node.type, @selected)
        ]}
      />
      <%!-- Regular node (no preview) --%>
      <rect
        :if={!@is_machine && !@has_preview}
        x="-60"
        y="-20"
        width="120"
        height="40"
        rx="6"
        class={[
          "stroke-2 transition-colors",
          node_rect_class(@node.type, @selected)
        ]}
      />
      <%!-- Machine icon --%>
      <text
        :if={@is_machine}
        x="-62"
        y="1"
        font-size="16"
        class="select-none pointer-events-none"
      >
        &#9881;
      </text>
      <%!-- Machine system label --%>
      <text
        :if={@is_machine}
        x="0"
        y="12"
        text-anchor="middle"
        font-size="9"
        fill="#92400e"
        opacity="0.6"
        class="select-none pointer-events-none"
      >
        {@node.machine.system}
      </text>
      <%!-- Gateway indicator (non-machine) --%>
      <circle
        :if={@node.type == :gateway && !@is_machine}
        cx="-42"
        cy="0"
        r="6"
        class="fill-secondary/30 stroke-secondary"
        stroke-width="1.5"
      />
      <%!-- Content indicator for leaf nodes --%>
      <circle
        :if={@node.type == :leaf && @has_preview}
        cx="62"
        cy="-20"
        r="4"
        class="fill-success stroke-success/50"
        stroke-width="1"
      />
      <%!-- Node name --%>
      <text
        :if={!@has_preview}
        text-anchor="middle"
        dominant-baseline={if @is_machine, do: "auto", else: "central"}
        y={if @is_machine, do: "-3", else: "0"}
        class={[
          "text-xs select-none pointer-events-none",
          if(@is_machine, do: "fill-amber-800 font-bold", else: node_text_class(@selected))
        ]}
      >
        {@node.name}
      </text>
      <%!-- Leaf with preview: name at top, content below --%>
      <text
        :if={@has_preview}
        x="-72"
        y="-15"
        font-size="11"
        font-weight="bold"
        class={["select-none pointer-events-none", node_text_class(@selected)]}
      >
        {@node.name}
      </text>
      <text
        :for={{line, idx} <- Enum.with_index(@preview_lines)}
        :if={@has_preview}
        x="-72"
        y={3 + idx * 13}
        font-size="9"
        font-family="monospace"
        opacity="0.65"
        class={["select-none pointer-events-none", node_text_class(@selected)]}
      >
        {line}
      </text>
    </g>
    """
  end

  attr :edge, :map, required: true
  attr :nodes, :map, required: true

  def edge_line(assigns) do
    from_node = Map.get(assigns.nodes, assigns.edge.from)
    to_node = Map.get(assigns.nodes, assigns.edge.to)

    path_d =
      if from_node && to_node do
        x1 = from_node.position.x + node_half_width(from_node)
        y1 = from_node.position.y
        x2 = to_node.position.x - node_half_width(to_node)
        y2 = to_node.position.y
        dx = abs(x2 - x1)
        offset = max(dx * 0.5, 80)
        "M #{x1} #{y1} C #{x1 + offset} #{y1}, #{x2 - offset} #{y2}, #{x2} #{y2}"
      end

    assigns =
      assigns
      |> assign(:from_node, from_node)
      |> assign(:to_node, to_node)
      |> assign(:path_d, path_d)

    ~H"""
    <path
      :if={@from_node && @to_node}
      d={@path_d}
      data-edge-id={@edge.id}
      data-from={@edge.from}
      data-to={@edge.to}
      fill="none"
      class="stroke-base-content/30 stroke-2 hover:stroke-primary cursor-pointer"
      marker-end="url(#arrowhead)"
      phx-click="delete_edge"
      phx-value-edge-id={@edge.id}
    />
    """
  end

  attr :oodn_registry, :map, required: true
  attr :position, :map, required: true

  def oodn_node(assigns) do
    all_entries = assigns.oodn_registry |> Map.values() |> Enum.sort_by(& &1.key)
    total_count = length(all_entries)
    visible_entries = Enum.take(all_entries, @oodn_max_visible)
    overflow = max(total_count - @oodn_max_visible, 0)
    has_overflow = overflow > 0

    row_height = 20
    header_height = 32
    padding = 10
    footer = if has_overflow, do: 18, else: 0
    width = 220
    visible_count = max(length(visible_entries), 1)
    height = header_height + padding + visible_count * row_height + padding + footer

    assigns =
      assign(assigns,
        entries: visible_entries,
        total_count: total_count,
        overflow: overflow,
        has_overflow: has_overflow,
        width: width,
        height: height,
        row_height: row_height,
        header_height: header_height,
        padding: padding,
        footer_y: header_height + padding + visible_count * row_height + 4
      )

    ~H"""
    <g
      class="oodn-node cursor-grab active:cursor-grabbing"
      data-node-id="oodn"
      data-node-type="oodn"
      data-node-name="Config"
      transform={"translate(#{@position.x}, #{@position.y})"}
    >
      <%!-- Shadow --%>
      <rect x="2" y="2" width={@width} height={@height} rx="6" fill="black" opacity="0.08" />

      <%!-- Body --%>
      <rect
        x="0"
        y="0"
        width={@width}
        height={@height}
        rx="6"
        fill="#fef9c3"
        stroke="#eab308"
        stroke-width="2"
      />

      <%!-- Header --%>
      <rect x="0" y="0" width={@width} height={@header_height} rx="6" fill="#eab308" opacity="0.25" />
      <rect x="0" y={@header_height - 4} width={@width} height="4" fill="#eab308" opacity="0.25" />

      <%!-- Header icon --%>
      <text
        x="10"
        y={@header_height / 2 + 1}
        dominant-baseline="central"
        font-size="14"
        class="select-none pointer-events-none"
      >
        &#9881;
      </text>
      <text
        x="28"
        y={@header_height / 2}
        dominant-baseline="central"
        font-size="12"
        font-weight="bold"
        fill="#92400e"
        class="select-none pointer-events-none"
      >
        OODN Config
      </text>
      <text
        x={@width - 10}
        y={@header_height / 2}
        dominant-baseline="central"
        text-anchor="end"
        font-size="10"
        fill="#92400e"
        opacity="0.5"
        class="select-none pointer-events-none"
      >
        {@total_count}
      </text>

      <%!-- Separator line --%>
      <line
        x1="8"
        y1={@header_height + 2}
        x2={@width - 8}
        y2={@header_height + 2}
        stroke="#eab308"
        opacity="0.3"
      />

      <%!-- Key-value rows --%>
      <g :for={{entry, idx} <- Enum.with_index(@entries)}>
        <%!-- Row background on hover --%>
        <rect
          x="4"
          y={@header_height + @padding + idx * @row_height - 2}
          width={@width - 8}
          height={@row_height - 2}
          rx="3"
          fill="#eab308"
          opacity="0.05"
        />
        <text
          x="10"
          y={@header_height + @padding + idx * @row_height + 12}
          font-size="11"
          font-family="monospace"
          fill="#78350f"
          class="select-none pointer-events-none"
        >
          {entry.key}
        </text>
        <text
          x={@width - 10}
          y={@header_height + @padding + idx * @row_height + 12}
          text-anchor="end"
          font-size="11"
          font-family="monospace"
          fill="#a16207"
          class="select-none pointer-events-none"
        >
          {truncate_value(entry.value, 14)}
        </text>
      </g>

      <%!-- Empty state --%>
      <text
        :if={@entries == []}
        x={@width / 2}
        y={@header_height + @padding + 12}
        text-anchor="middle"
        font-size="11"
        fill="#a16207"
        opacity="0.4"
        class="select-none pointer-events-none"
      >
        Double-click to add variables
      </text>

      <%!-- Overflow indicator --%>
      <text
        :if={@has_overflow}
        x={@width / 2}
        y={@footer_y + 10}
        text-anchor="middle"
        font-size="10"
        font-style="italic"
        fill="#a16207"
        opacity="0.7"
        class="select-none pointer-events-none"
      >
        + {@overflow} more (double-click to view)
      </text>
    </g>
    """
  end
end
