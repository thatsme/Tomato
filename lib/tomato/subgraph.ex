defmodule Tomato.Subgraph do
  @moduledoc """
  A self-contained DAG on a specific floor.
  """

  alias Tomato.{Node, Edge}

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          floor: non_neg_integer(),
          nodes: %{String.t() => Node.t()},
          edges: %{String.t() => Edge.t()}
        }

  @derive Jason.Encoder
  @enforce_keys [:id, :name]
  defstruct [:id, :name, floor: 0, nodes: %{}, edges: %{}]

  @doc """
  Creates a new subgraph with auto-generated input and output nodes.
  """
  @spec new(keyword()) :: t()
  def new(attrs \\ []) do
    id = attrs[:id] || UUID.uuid4()
    floor = attrs[:floor] || 0
    name = attrs[:name] || "Subgraph"

    input_node = Node.new(type: :input, name: "Input", position: %{x: 100, y: 50})
    output_node = Node.new(type: :output, name: "Output", position: %{x: 100, y: 450})

    nodes = %{
      input_node.id => input_node,
      output_node.id => output_node
    }

    %__MODULE__{
      id: id,
      name: name,
      floor: floor,
      nodes: nodes,
      edges: %{}
    }
  end

  @spec input_node(t()) :: Node.t() | nil
  def input_node(%__MODULE__{nodes: nodes}) do
    Enum.find_value(nodes, fn {_id, node} ->
      if node.type == :input, do: node
    end)
  end

  @spec output_node(t()) :: Node.t() | nil
  def output_node(%__MODULE__{nodes: nodes}) do
    Enum.find_value(nodes, fn {_id, node} ->
      if node.type == :output, do: node
    end)
  end

  @spec add_node(t(), Node.t()) :: t()
  def add_node(%__MODULE__{} = sg, %Node{} = node) do
    %{sg | nodes: Map.put(sg.nodes, node.id, node)}
  end

  @spec add_edge(t(), Edge.t()) :: t()
  def add_edge(%__MODULE__{} = sg, %Edge{} = edge) do
    %{sg | edges: Map.put(sg.edges, edge.id, edge)}
  end

  @spec remove_node(t(), String.t()) :: t()
  def remove_node(%__MODULE__{} = sg, node_id) do
    # Also remove any edges connected to this node
    edges =
      sg.edges
      |> Enum.reject(fn {_id, edge} -> edge.from == node_id or edge.to == node_id end)
      |> Map.new()

    %{sg | nodes: Map.delete(sg.nodes, node_id), edges: edges}
  end

  @spec remove_edge(t(), String.t()) :: t()
  def remove_edge(%__MODULE__{} = sg, edge_id) do
    %{sg | edges: Map.delete(sg.edges, edge_id)}
  end

  @spec update_node(t(), String.t(), keyword()) :: t()
  def update_node(%__MODULE__{} = sg, node_id, updates) do
    case Map.get(sg.nodes, node_id) do
      nil ->
        sg

      node ->
        updated = struct(node, updates)
        %{sg | nodes: Map.put(sg.nodes, node_id, updated)}
    end
  end
end
