defmodule Tomato.Constraint do
  @moduledoc """
  DAG constraint validation. All checks run synchronously before any mutation is committed.
  """

  alias Tomato.Subgraph

  @type error :: {:error, atom(), String.t()}

  @doc """
  Validates all constraints on a subgraph. Returns :ok or {:error, reason, message}.
  """
  @spec validate(Subgraph.t()) :: :ok | error()
  def validate(%Subgraph{} = sg) do
    with :ok <- validate_single_input(sg),
         :ok <- validate_single_output(sg),
         :ok <- validate_minimum_nodes(sg),
         :ok <- validate_edges_reference_existing_nodes(sg),
         :ok <- validate_input_no_incoming(sg),
         :ok <- validate_output_no_outgoing(sg),
         :ok <- validate_no_cycles(sg) do
      :ok
    end
  end

  defp validate_single_input(%Subgraph{nodes: nodes}) do
    input_count = Enum.count(nodes, fn {_id, n} -> n.type == :input end)

    case input_count do
      1 -> :ok
      0 -> {:error, :no_input, "Subgraph must have exactly one :input node"}
      _ -> {:error, :multiple_inputs, "Subgraph must have exactly one :input node"}
    end
  end

  defp validate_single_output(%Subgraph{nodes: nodes}) do
    output_count = Enum.count(nodes, fn {_id, n} -> n.type == :output end)

    case output_count do
      1 -> :ok
      0 -> {:error, :no_output, "Subgraph must have exactly one :output node"}
      _ -> {:error, :multiple_outputs, "Subgraph must have exactly one :output node"}
    end
  end

  defp validate_minimum_nodes(%Subgraph{nodes: nodes}) do
    if map_size(nodes) >= 3 do
      :ok
    else
      {:error, :too_few_nodes, "Subgraph must have at least 3 nodes (input + output + one other)"}
    end
  end

  defp validate_edges_reference_existing_nodes(%Subgraph{nodes: nodes, edges: edges}) do
    node_ids = MapSet.new(Map.keys(nodes))

    invalid =
      Enum.find(edges, fn {_id, edge} ->
        not MapSet.member?(node_ids, edge.from) or not MapSet.member?(node_ids, edge.to)
      end)

    case invalid do
      nil -> :ok
      {_id, edge} -> {:error, :invalid_edge, "Edge #{edge.id} references non-existent node"}
    end
  end

  defp validate_input_no_incoming(%Subgraph{nodes: nodes, edges: edges}) do
    input_ids =
      nodes
      |> Enum.filter(fn {_id, n} -> n.type == :input end)
      |> Enum.map(fn {id, _n} -> id end)
      |> MapSet.new()

    has_incoming =
      Enum.any?(edges, fn {_id, edge} -> MapSet.member?(input_ids, edge.to) end)

    if has_incoming do
      {:error, :input_has_incoming, "Input nodes cannot have incoming edges"}
    else
      :ok
    end
  end

  defp validate_output_no_outgoing(%Subgraph{nodes: nodes, edges: edges}) do
    output_ids =
      nodes
      |> Enum.filter(fn {_id, n} -> n.type == :output end)
      |> Enum.map(fn {id, _n} -> id end)
      |> MapSet.new()

    has_outgoing =
      Enum.any?(edges, fn {_id, edge} -> MapSet.member?(output_ids, edge.from) end)

    if has_outgoing do
      {:error, :output_has_outgoing, "Output nodes cannot have outgoing edges"}
    else
      :ok
    end
  end

  @doc """
  Topological sort using Kahn's algorithm. Returns {:ok, sorted_ids} or {:error, :cycle, msg}.
  """
  @spec topological_sort(Subgraph.t()) :: {:ok, list(String.t())} | error()
  def topological_sort(%Subgraph{nodes: nodes, edges: edges}) do
    # Build adjacency list and in-degree map
    node_ids = Map.keys(nodes)
    in_degree = Map.new(node_ids, fn id -> {id, 0} end)

    {adjacency, in_degree} =
      Enum.reduce(edges, {%{}, in_degree}, fn {_id, edge}, {adj, deg} ->
        adj = Map.update(adj, edge.from, [edge.to], &[edge.to | &1])
        deg = Map.update!(deg, edge.to, &(&1 + 1))
        {adj, deg}
      end)

    # Start with nodes that have no incoming edges
    queue = Enum.filter(node_ids, fn id -> Map.get(in_degree, id) == 0 end)

    do_topo_sort(queue, adjacency, in_degree, [], length(node_ids))
  end

  defp do_topo_sort([], _adj, _deg, sorted, expected) do
    if length(sorted) == expected do
      {:ok, Enum.reverse(sorted)}
    else
      {:error, :cycle, "Cycle detected in subgraph"}
    end
  end

  defp do_topo_sort([node | rest], adj, deg, sorted, expected) do
    neighbors = Map.get(adj, node, [])

    {new_queue, new_deg} =
      Enum.reduce(neighbors, {rest, deg}, fn neighbor, {q, d} ->
        new_d = Map.update!(d, neighbor, &(&1 - 1))

        if Map.get(new_d, neighbor) == 0 do
          {q ++ [neighbor], new_d}
        else
          {q, new_d}
        end
      end)

    do_topo_sort(new_queue, adj, new_deg, [node | sorted], expected)
  end

  defp validate_no_cycles(sg) do
    case topological_sort(sg) do
      {:ok, _} -> :ok
      error -> error
    end
  end
end
