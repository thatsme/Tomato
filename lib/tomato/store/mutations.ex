defmodule Tomato.Store.Mutations do
  @moduledoc """
  Pure graph mutations — no GenServer state, no side effects. Each
  function takes a `%Graph{}` and returns `{:ok, graph}`,
  `{:ok, graph, payload}`, or `{:error, atom(), String.t()}`.

  The Store GenServer wraps these results with history/flush/broadcast.
  """

  alias Tomato.{Constraint, Edge, Graph, Node, Subgraph}

  @doc """
  Create a new node in the given subgraph. `attrs` is a keyword list
  passed straight to `Tomato.Node.new/1`.
  """
  @spec add_node(Graph.t(), String.t(), keyword()) ::
          {:ok, Graph.t(), Node.t()} | {:error, atom(), String.t()}
  def add_node(%Graph{} = graph, subgraph_id, node_attrs) do
    with {:ok, sg} <- fetch_subgraph(graph, subgraph_id) do
      node = Node.new(node_attrs)
      new_sg = Subgraph.add_node(sg, node)
      {:ok, Graph.put_subgraph(graph, new_sg), node}
    end
  end

  @doc """
  Remove a node from a subgraph. Refuses to delete `:input`/`:output`
  nodes.
  """
  @spec remove_node(Graph.t(), String.t(), String.t()) ::
          {:ok, Graph.t()} | {:error, atom(), String.t()}
  def remove_node(%Graph{} = graph, subgraph_id, node_id) do
    with {:ok, sg} <- fetch_subgraph(graph, subgraph_id),
         {:ok, node} <- fetch_node(sg, node_id),
         :ok <- validate_deletable(node) do
      new_sg = Subgraph.remove_node(sg, node_id)
      {:ok, Graph.put_subgraph(graph, new_sg)}
    end
  end

  @doc """
  Update a node's attributes (name, content, position, etc.).
  """
  @spec update_node(Graph.t(), String.t(), String.t(), keyword()) ::
          {:ok, Graph.t()} | {:error, atom(), String.t()}
  def update_node(%Graph{} = graph, subgraph_id, node_id, updates) do
    with {:ok, sg} <- fetch_subgraph(graph, subgraph_id) do
      new_sg = Subgraph.update_node(sg, node_id, updates)
      {:ok, Graph.put_subgraph(graph, new_sg)}
    end
  end

  @doc """
  Add a directed edge between two nodes in the same subgraph. Rejected
  if it would introduce a cycle.
  """
  @spec add_edge(Graph.t(), String.t(), String.t(), String.t()) ::
          {:ok, Graph.t(), Edge.t()} | {:error, atom(), String.t()}
  def add_edge(%Graph{} = graph, subgraph_id, from_id, to_id) do
    with {:ok, sg} <- fetch_subgraph(graph, subgraph_id) do
      edge = Edge.new(from_id, to_id)
      new_sg = Subgraph.add_edge(sg, edge)

      case Constraint.topological_sort(new_sg) do
        {:ok, _} -> {:ok, Graph.put_subgraph(graph, new_sg), edge}
        {:error, _, _} = error -> error
      end
    end
  end

  @doc """
  Remove an edge from a subgraph.
  """
  @spec remove_edge(Graph.t(), String.t(), String.t()) ::
          {:ok, Graph.t()} | {:error, atom(), String.t()}
  def remove_edge(%Graph{} = graph, subgraph_id, edge_id) do
    with {:ok, sg} <- fetch_subgraph(graph, subgraph_id) do
      new_sg = Subgraph.remove_edge(sg, edge_id)
      {:ok, Graph.put_subgraph(graph, new_sg)}
    end
  end

  @doc """
  Create a gateway node and a matching child subgraph one floor deeper.
  """
  @spec add_gateway(Graph.t(), String.t(), keyword()) ::
          {:ok, Graph.t(), Node.t(), Subgraph.t()} | {:error, atom(), String.t()}
  def add_gateway(%Graph{} = graph, subgraph_id, gateway_attrs) do
    with {:ok, sg} <- fetch_subgraph(graph, subgraph_id) do
      child_sg = Subgraph.new(name: gateway_attrs[:name] || "Sub", floor: sg.floor + 1)

      gateway_node =
        Node.new(
          type: :gateway,
          name: gateway_attrs[:name] || "Gateway",
          subgraph_id: child_sg.id,
          position: gateway_attrs[:position] || %{x: 0, y: 0}
        )

      new_sg = Subgraph.add_node(sg, gateway_node)

      new_graph =
        graph
        |> Graph.put_subgraph(new_sg)
        |> Graph.put_subgraph(child_sg)

      {:ok, new_graph, gateway_node, child_sg}
    end
  end

  @doc """
  Set the graph's backend (`:traditional` or `:flake`).
  """
  @spec set_backend(Graph.t(), Graph.backend()) :: Graph.t()
  def set_backend(%Graph{} = graph, backend) when backend in [:traditional, :flake] do
    %{graph | backend: backend}
  end

  # --- shared helpers (also used by Tomato.Store.Machine) ---

  @doc false
  @spec fetch_subgraph(Graph.t(), String.t()) ::
          {:ok, Subgraph.t()} | {:error, :subgraph_not_found, String.t()}
  def fetch_subgraph(%Graph{} = graph, subgraph_id) do
    case Graph.get_subgraph(graph, subgraph_id) do
      nil -> {:error, :subgraph_not_found, "Subgraph #{subgraph_id} not found"}
      sg -> {:ok, sg}
    end
  end

  @doc false
  @spec fetch_node(Subgraph.t(), String.t()) ::
          {:ok, Node.t()} | {:error, :node_not_found, String.t()}
  def fetch_node(%Subgraph{} = sg, node_id) do
    case Map.get(sg.nodes, node_id) do
      nil -> {:error, :node_not_found, "Node #{node_id} not found"}
      node -> {:ok, node}
    end
  end

  defp validate_deletable(%Node{type: type}) when type in [:input, :output] do
    {:error, :undeletable, "Cannot delete #{type} node"}
  end

  defp validate_deletable(_node), do: :ok
end
