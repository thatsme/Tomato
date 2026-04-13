defmodule TomatoWeb.GraphLive.EdgeHandlers do
  @moduledoc """
  Handler functions for edge-related `handle_event` clauses in
  `TomatoWeb.GraphLive`. Each public function takes `(params, socket)`
  and returns `{:noreply, socket}`, matching the shape of LiveView's
  `handle_event/3` return so the main LiveView can delegate directly:

      def handle_event("delete_edge", params, socket),
        do: EdgeHandlers.delete(params, socket)

  Handlers read `socket.assigns.store` for the store server.

  ## Coupling with `NodeHandlers.select/2`

  `start_connect/2` and `start_connect_to/2` write the `:connecting_from`
  and `:connecting_to` socket assigns respectively. `NodeHandlers.select/2`
  reads those assigns to detect connection mode — when either is set, a
  click on a node completes an edge instead of selecting. `cancel_connect/2`
  clears `:connecting_from`, and `NodeHandlers.deselect/2` clears both.

  This is a two-module dance, not a bug. Any change to the connection-mode
  lifecycle (new cancel path, new trigger, new assign key) has to touch
  both modules in lockstep.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Tomato.Store

  @type socket :: Phoenix.LiveView.Socket.t()
  @type result :: {:noreply, socket()}

  # --- Edge mutation ---

  @spec delete(map(), socket()) :: result()
  def delete(%{"edge-id" => edge_id}, socket) do
    store = socket.assigns.store
    Store.remove_edge(store, socket.assigns.subgraph.id, edge_id)
    {:noreply, socket}
  end

  @spec disconnect(map(), socket()) :: result()
  def disconnect(%{"node-id" => node_id}, socket) do
    store = socket.assigns.store
    sg = socket.assigns.subgraph

    sg.edges
    |> Enum.filter(fn {_id, edge} -> edge.from == node_id or edge.to == node_id end)
    |> Enum.each(fn {edge_id, _edge} ->
      Store.remove_edge(store, sg.id, edge_id)
    end)

    {:noreply, socket}
  end

  @spec reverse(map(), socket()) :: result()
  def reverse(%{"edge-id" => edge_id}, socket) do
    store = socket.assigns.store
    sg = socket.assigns.subgraph

    case Map.get(sg.edges, edge_id) do
      nil ->
        {:noreply, socket}

      edge ->
        Store.remove_edge(store, sg.id, edge_id)
        Store.add_edge(store, sg.id, edge.to, edge.from)
        {:noreply, socket}
    end
  end

  # --- Connection-mode lifecycle (see moduledoc) ---

  @spec start_connect(map(), socket()) :: result()
  def start_connect(%{"node-id" => node_id}, socket) do
    {:noreply, assign(socket, :connecting_from, node_id)}
  end

  @spec cancel_connect(map(), socket()) :: result()
  def cancel_connect(_params, socket) do
    {:noreply, assign(socket, :connecting_from, nil)}
  end

  @spec start_connect_to(map(), socket()) :: result()
  def start_connect_to(%{"node-id" => node_id}, socket) do
    {:noreply, assign(socket, :connecting_to, node_id)}
  end
end
