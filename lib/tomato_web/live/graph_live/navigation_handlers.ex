defmodule TomatoWeb.GraphLive.NavigationHandlers do
  @moduledoc """
  Handler functions for navigation and search `handle_event` clauses in
  `TomatoWeb.GraphLive` — entering gateway subgraphs, walking the
  breadcrumb, searching nodes, and jumping to a search result.

  Each public function takes `(params, socket)` and returns
  `{:noreply, socket}`, so the main LiveView can delegate directly:

      def handle_event("enter_gateway", params, socket),
        do: NavigationHandlers.enter_gateway(params, socket)

  Navigation handlers read `socket.assigns.graph` and `:breadcrumb`, and
  write `:subgraph`, `:breadcrumb`, and clear selection/editing assigns
  when the active subgraph changes.

  The search helpers (`search_graph/2`, `build_breadcrumb_to/2`, etc.)
  are pure — they operate on `Tomato.Graph` without touching the socket —
  and live as `defp` in this module since they're only used by the
  search and goto handlers.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Tomato.Graph

  @type socket :: Phoenix.LiveView.Socket.t()
  @type result :: {:noreply, socket()}

  # --- Subgraph navigation ---

  @spec enter_gateway(map(), socket()) :: result()
  def enter_gateway(%{"node-id" => node_id}, socket) do
    sg = socket.assigns.subgraph
    node = Map.get(sg.nodes, node_id)

    if node && node.type == :gateway && node.subgraph_id do
      child_sg = Graph.get_subgraph(socket.assigns.graph, node.subgraph_id)

      if child_sg do
        breadcrumb = socket.assigns.breadcrumb ++ [{child_sg.id, child_sg.name}]

        {:noreply,
         socket
         |> assign(:subgraph, child_sg)
         |> assign(:breadcrumb, breadcrumb)
         |> assign(:selected_node_id, nil)
         |> assign(:editing_content_node_id, nil)}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @spec navigate_breadcrumb(map(), socket()) :: result()
  def navigate_breadcrumb(%{"subgraph-id" => sg_id}, socket) do
    subgraph = Graph.get_subgraph(socket.assigns.graph, sg_id)

    if subgraph do
      breadcrumb =
        Enum.take_while(socket.assigns.breadcrumb, fn {id, _} -> id != sg_id end) ++
          [{sg_id, subgraph.name}]

      {:noreply,
       socket
       |> assign(:subgraph, subgraph)
       |> assign(:breadcrumb, breadcrumb)
       |> assign(:selected_node_id, nil)
       |> assign(:editing_content_node_id, nil)}
    else
      {:noreply, socket}
    end
  end

  # --- Search ---

  @spec search(map(), socket()) :: result()
  def search(%{"q" => query}, socket) do
    results =
      if String.trim(query) == "" do
        []
      else
        search_graph(socket.assigns.graph, query)
      end

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:search_results, results)}
  end

  @spec goto_search_result(map(), socket()) :: result()
  def goto_search_result(%{"subgraph-id" => sg_id, "node-id" => node_id}, socket) do
    case jump_to(socket, sg_id, node_id) do
      {:ok, socket} ->
        {:noreply,
         socket
         |> assign(:search_query, "")
         |> assign(:search_results, [])}

      :error ->
        {:noreply, socket}
    end
  end

  @doc """
  Jump to a node in any subgraph — walks the breadcrumb from the root so
  the target subgraph becomes active, then selects the node. Used by
  validation error rows in the generated-output modal to land on the
  offending leaf regardless of how deeply nested it is inside machine
  gateways. Shares its implementation with `goto_search_result/2`.
  """
  @spec navigate_to_node(map(), socket()) :: result()
  def navigate_to_node(%{"subgraph-id" => sg_id, "node-id" => node_id}, socket) do
    case jump_to(socket, sg_id, node_id) do
      {:ok, socket} -> {:noreply, socket}
      :error -> {:noreply, socket}
    end
  end

  @spec jump_to(socket(), String.t(), String.t()) :: {:ok, socket()} | :error
  defp jump_to(socket, sg_id, node_id) do
    case Graph.get_subgraph(socket.assigns.graph, sg_id) do
      nil ->
        :error

      subgraph ->
        breadcrumb = build_breadcrumb_to(socket.assigns.graph, sg_id)

        {:ok,
         socket
         |> assign(:subgraph, subgraph)
         |> assign(:breadcrumb, breadcrumb)
         |> assign(:selected_node_id, node_id)
         |> assign(:editing_content_node_id, nil)}
    end
  end

  # --- Pure helpers ---

  defp search_graph(graph, query) do
    q = String.downcase(query)

    graph.subgraphs
    |> Enum.flat_map(fn {sg_id, sg} ->
      sg.nodes
      |> Enum.filter(fn {_id, node} -> matches_search?(node, q) end)
      |> Enum.map(fn {_id, node} ->
        %{node: node, subgraph_id: sg_id, subgraph_name: sg.name}
      end)
    end)
    |> Enum.take(50)
  end

  defp matches_search?(node, q) do
    String.contains?(String.downcase(node.name), q) ||
      (is_binary(node.content) && String.contains?(String.downcase(node.content), q))
  end

  defp build_breadcrumb_to(graph, target_sg_id) do
    # Walk from root looking for path to target subgraph
    root_id = graph.root_subgraph_id
    root = graph.subgraphs[root_id]
    initial = [{root_id, root.name}]

    case find_path(graph, root, target_sg_id, initial) do
      nil -> initial
      path -> path
    end
  end

  defp find_path(_graph, sg, target_id, acc) when sg.id == target_id, do: acc

  defp find_path(graph, sg, target_id, acc) do
    sg.nodes
    |> Map.values()
    |> Enum.find_value(fn node ->
      if node.type == :gateway && is_binary(node.subgraph_id) do
        case Graph.get_subgraph(graph, node.subgraph_id) do
          nil ->
            nil

          child_sg ->
            new_acc = acc ++ [{child_sg.id, child_sg.name}]

            cond do
              child_sg.id == target_id -> new_acc
              true -> find_path(graph, child_sg, target_id, new_acc)
            end
        end
      end
    end)
  end
end
