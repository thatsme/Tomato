defmodule TomatoWeb.GraphLive.GraphStateHandlers do
  @moduledoc """
  Handler functions for graph-level state operations in `TomatoWeb.GraphLive`:
  backend selection, undo/redo, and graph-file lifecycle (open manager,
  load, create new, save-as, delete).

  Each public function takes `(params, socket)` and returns
  `{:noreply, socket}`, so the main LiveView can delegate directly:

      def handle_event("load_graph_file", params, socket),
        do: GraphStateHandlers.load(params, socket)

  This module groups backend toggle + history + file ops because they
  all manipulate graph-level state (as opposed to node/edge-level
  mutations which live in `NodeHandlers` / `EdgeHandlers`). `undo/2`
  and `redo/2` land here rather than in a separate `HistoryHandlers`
  because a two-clause module would be too thin — history is
  conceptually part of graph lifecycle.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Tomato.{Graph, Store}

  @type socket :: Phoenix.LiveView.Socket.t()
  @type result :: {:noreply, socket()}

  # --- Backend toggle ---

  @spec toggle_backend(map(), socket()) :: result()
  def toggle_backend(_params, socket) do
    new_backend = if socket.assigns.graph.backend == :flake, do: :traditional, else: :flake
    Store.set_backend(socket.assigns.store, new_backend)
    {:noreply, socket}
  end

  # --- History ---

  @spec undo(map(), socket()) :: result()
  def undo(_params, socket) do
    Store.undo(socket.assigns.store)
    {:noreply, socket}
  end

  @spec redo(map(), socket()) :: result()
  def redo(_params, socket) do
    Store.redo(socket.assigns.store)
    {:noreply, socket}
  end

  # --- Graph manager modal ---

  @spec open_manager(map(), socket()) :: result()
  def open_manager(_params, socket) do
    graph_list = Store.list_graphs(socket.assigns.store)

    {:noreply,
     socket
     |> assign(:show_graph_manager, true)
     |> assign(:graph_list, graph_list)}
  end

  @spec close_manager(map(), socket()) :: result()
  def close_manager(_params, socket) do
    {:noreply, assign(socket, :show_graph_manager, false)}
  end

  # --- Graph-file lifecycle ---

  @spec load(map(), socket()) :: result()
  def load(%{"filename" => filename}, socket) do
    case Store.load_graph(socket.assigns.store, filename) do
      {:ok, graph} ->
        root = Graph.root_subgraph(graph)

        {:noreply,
         socket
         |> assign(:graph, graph)
         |> assign(:subgraph, root)
         |> assign(:breadcrumb, [{root.id, root.name}])
         |> assign(:selected_node_id, nil)
         |> assign(:show_graph_manager, false)
         |> assign(:current_file, filename)}

      _ ->
        {:noreply, put_flash(socket, :error, "Failed to load graph")}
    end
  end

  @spec new(map(), socket()) :: result()
  def new(%{"name" => name}, socket) when name != "" do
    {:ok, graph, filename} = Store.new_graph(socket.assigns.store, name)
    root = Graph.root_subgraph(graph)

    {:noreply,
     socket
     |> assign(:graph, graph)
     |> assign(:subgraph, root)
     |> assign(:breadcrumb, [{root.id, root.name}])
     |> assign(:selected_node_id, nil)
     |> assign(:show_graph_manager, false)
     |> assign(:current_file, filename)}
  end

  def new(_params, socket), do: {:noreply, socket}

  @spec save_as(map(), socket()) :: result()
  def save_as(%{"name" => name}, socket) when name != "" do
    {:ok, filename} = Store.save_as(socket.assigns.store, name)

    {:noreply,
     socket
     |> assign(:current_file, filename)
     |> assign(:show_graph_manager, false)
     |> put_flash(:info, "Saved as #{filename}")}
  end

  def save_as(_params, socket), do: {:noreply, socket}

  @spec delete(map(), socket()) :: result()
  def delete(%{"filename" => filename}, socket) do
    store = socket.assigns.store
    Store.delete_graph(store, filename)
    graph_list = Store.list_graphs(store)
    {:noreply, assign(socket, :graph_list, graph_list)}
  end
end
