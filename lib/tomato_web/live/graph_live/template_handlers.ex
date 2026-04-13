defmodule TomatoWeb.GraphLive.TemplateHandlers do
  @moduledoc """
  Handler functions for the template-picker modal in `TomatoWeb.GraphLive`:
  opening and closing the picker, and adding a node (or pre-populated
  gateway subgraph) from a `Tomato.TemplateLibrary` entry.

  Each public function takes `(params, socket)` and returns
  `{:noreply, socket}`, so the main LiveView can delegate directly:

      def handle_event("add_from_template", params, socket),
        do: TemplateHandlers.add(params, socket)

  ## `add/2` details

  Gateway templates create a parent gateway node plus a child subgraph
  pre-populated with the template's listed leaf children, each wired
  from the child subgraph's input node through to its output node.
  Leaf templates create a single leaf node with the template's content.
  An unknown `template-id` is a no-op.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Tomato.Store

  @type socket :: Phoenix.LiveView.Socket.t()
  @type result :: {:noreply, socket()}

  @spec open(map(), socket()) :: result()
  def open(_params, socket) do
    {:noreply, assign(socket, :show_template_picker, true)}
  end

  @spec close(map(), socket()) :: result()
  def close(_params, socket) do
    {:noreply, assign(socket, :show_template_picker, false)}
  end

  @spec add(map(), socket()) :: result()
  def add(%{"template-id" => template_id}, socket) do
    store = socket.assigns.store
    sg = socket.assigns.subgraph
    node_count = map_size(sg.nodes)
    y = 100 + node_count * 80

    template = Tomato.TemplateLibrary.get(template_id)

    if template do
      case Map.get(template, :type, :leaf) do
        :gateway ->
          add_gateway_template(store, sg, template, y, socket)

        _ ->
          add_leaf_template(store, sg, template, y, socket)
      end
    else
      {:noreply, socket}
    end
  end

  # --- Private ---

  defp add_gateway_template(store, sg, template, y, socket) do
    {:ok, gw, child} =
      Store.add_gateway(store, sg.id,
        name: template.name,
        position: %{x: 300, y: y}
      )

    children = Map.get(template, :children, [])
    child_sg = Store.get_subgraph(store, child.id)
    child_input = Tomato.Subgraph.input_node(child_sg)
    child_output = Tomato.Subgraph.output_node(child_sg)

    children
    |> Enum.with_index()
    |> Enum.each(fn {child_tmpl, idx} ->
      {:ok, leaf} =
        Store.add_node(store, child.id,
          type: :leaf,
          name: child_tmpl.name,
          content: String.trim(child_tmpl.content),
          position: %{x: 150 + idx * 180, y: 200}
        )

      Store.add_edge(store, child.id, child_input.id, leaf.id)
      Store.add_edge(store, child.id, leaf.id, child_output.id)
    end)

    {:noreply,
     socket
     |> assign(:show_template_picker, false)
     |> assign(:selected_node_id, gw.id)}
  end

  defp add_leaf_template(store, sg, template, y, socket) do
    {:ok, node} =
      Store.add_node(store, sg.id,
        type: :leaf,
        name: template.name,
        content: String.trim(template.content),
        position: %{x: 300, y: y}
      )

    {:noreply,
     socket
     |> assign(:show_template_picker, false)
     |> assign(:selected_node_id, node.id)}
  end
end
