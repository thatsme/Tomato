defmodule TomatoWeb.GraphLive.NodeHandlers do
  @moduledoc """
  Handler functions for node-related `handle_event` clauses in
  `TomatoWeb.GraphLive`. Each public function takes `(params, socket)`
  and returns `{:noreply, socket}`, matching the shape of LiveView's
  `handle_event/3` return so the main LiveView can delegate directly:

      def handle_event("add_leaf", params, socket),
        do: NodeHandlers.add_leaf(params, socket)

  Handlers read `socket.assigns.store` for the store server and touch
  selection / editing / connection assigns as needed.

  ## Invariant: `select/2` in connection mode

  In connection mode, `select_node` completes an edge rather than selecting.
  This branch lives here because the event name drives dispatch — the edge
  concern is incidental to the node interaction. See `EdgeHandlers` (when
  extracted) for `start_connect` / `disconnect`.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Tomato.Store

  @type socket :: Phoenix.LiveView.Socket.t()
  @type result :: {:noreply, socket()}

  # --- Node creation ---

  @spec add_leaf(map(), socket()) :: result()
  def add_leaf(_params, socket) do
    store = socket.assigns.store
    sg = socket.assigns.subgraph
    node_count = map_size(sg.nodes)
    y = 100 + node_count * 80

    {:ok, _node} =
      Store.add_node(store, sg.id,
        type: :leaf,
        name: "Node #{node_count - 1}",
        position: %{x: 300, y: y}
      )

    {:noreply, socket}
  end

  @spec add_gateway(map(), socket()) :: result()
  def add_gateway(_params, socket) do
    store = socket.assigns.store
    sg = socket.assigns.subgraph
    node_count = map_size(sg.nodes)
    y = 100 + node_count * 80

    {:ok, _gateway, _child_sg} =
      Store.add_gateway(store, sg.id,
        name: "Gateway #{node_count - 1}",
        position: %{x: 300, y: y}
      )

    {:noreply, socket}
  end

  @spec add_node_at(map(), socket()) :: result()
  def add_node_at(%{"type" => type, "x" => x, "y" => y}, socket) do
    store = socket.assigns.store
    sg = socket.assigns.subgraph
    node_count = map_size(sg.nodes)

    case type do
      "leaf" ->
        {:ok, _node} =
          Store.add_node(store, sg.id,
            type: :leaf,
            name: "Node #{node_count - 1}",
            position: %{x: x, y: y}
          )

        {:noreply, socket}

      "gateway" ->
        {:ok, _gw, _child} =
          Store.add_gateway(store, sg.id,
            name: "Gateway #{node_count - 1}",
            position: %{x: x, y: y}
          )

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  @spec duplicate(map(), socket()) :: result()
  def duplicate(%{"node-id" => node_id}, socket) do
    store = socket.assigns.store
    sg = socket.assigns.subgraph
    node = Map.get(sg.nodes, node_id)

    if node do
      {:ok, _new_node} =
        Store.add_node(store, sg.id,
          type: node.type,
          name: node.name <> " (copy)",
          content: node.content,
          position: %{x: node.position.x + 40, y: node.position.y + 40}
        )
    end

    {:noreply, socket}
  end

  # --- Selection ---

  @spec select(map(), socket()) :: result()
  def select(%{"node-id" => node_id}, socket) do
    store = socket.assigns.store
    sg_id = socket.assigns.subgraph.id

    cond do
      socket.assigns.connecting_from ->
        from_id = socket.assigns.connecting_from
        if from_id != node_id, do: Store.add_edge(store, sg_id, from_id, node_id)
        {:noreply, assign(socket, :connecting_from, nil)}

      socket.assigns[:connecting_to] ->
        to_id = socket.assigns.connecting_to
        if to_id != node_id, do: Store.add_edge(store, sg_id, node_id, to_id)
        {:noreply, assign(socket, :connecting_to, nil)}

      true ->
        {:noreply, assign(socket, :selected_node_id, node_id)}
    end
  end

  @spec deselect(map(), socket()) :: result()
  def deselect(_params, socket) do
    {:noreply,
     socket
     |> assign(:selected_node_id, nil)
     |> assign(:connecting_from, nil)
     |> assign(:connecting_to, nil)}
  end

  @spec start_rename(map(), socket()) :: result()
  def start_rename(%{"node-id" => node_id}, socket) do
    {:noreply, assign(socket, :selected_node_id, node_id)}
  end

  # --- Mutation ---

  @spec delete(map(), socket()) :: result()
  def delete(%{"node-id" => node_id}, socket) do
    store = socket.assigns.store
    Store.remove_node(store, socket.assigns.subgraph.id, node_id)

    {:noreply,
     socket
     |> assign(:selected_node_id, nil)
     |> assign(:editing_content_node_id, nil)}
  end

  @spec moved(map(), socket()) :: result()
  def moved(%{"node_id" => node_id, "x" => x, "y" => y}, socket) do
    store = socket.assigns.store
    Store.update_node(store, socket.assigns.subgraph.id, node_id, position: %{x: x, y: y})
    {:noreply, socket}
  end

  @spec rename(map(), socket()) :: result()
  def rename(%{"node-id" => node_id, "name" => name}, socket) do
    store = socket.assigns.store
    Store.update_node(store, socket.assigns.subgraph.id, node_id, name: name)
    {:noreply, socket}
  end

  # --- Content editor lifecycle ---

  @spec edit_content(map(), socket()) :: result()
  def edit_content(%{"node-id" => node_id}, socket) do
    {:noreply,
     socket
     |> assign(:editing_content_node_id, node_id)
     |> assign(:selected_node_id, node_id)}
  end

  @spec save_content(map(), socket()) :: result()
  def save_content(%{"node-id" => node_id, "content" => content}, socket) do
    store = socket.assigns.store
    Store.update_node(store, socket.assigns.subgraph.id, node_id, content: content)
    {:noreply, assign(socket, :editing_content_node_id, nil)}
  end

  @spec close_editor(map(), socket()) :: result()
  def close_editor(_params, socket) do
    {:noreply, assign(socket, :editing_content_node_id, nil)}
  end
end
