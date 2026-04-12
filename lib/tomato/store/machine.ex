defmodule Tomato.Store.Machine do
  @moduledoc """
  Pure mutation that adds a machine gateway node (a `:gateway` node
  carrying a `machine` metadata map) and its matching child subgraph.
  """

  alias Tomato.{Graph, Node, Subgraph}
  alias Tomato.Store.Mutations

  @doc """
  Create a machine gateway and its child subgraph one floor deeper.

  `attrs` keys (all optional):
    * `:hostname` — defaults to `"nixos"`
    * `:system` — defaults to `"aarch64-linux"`
    * `:state_version` — defaults to `"24.11"`
    * `:type` — `:nixos` (default) or `:home_manager`
    * `:username` — defaults to `"user"`
    * `:position` — defaults to `%{x: 0, y: 0}`
  """
  @spec add(Graph.t(), String.t(), keyword()) ::
          {:ok, Graph.t(), Node.t(), Subgraph.t()} | {:error, atom(), String.t()}
  def add(%Graph{} = graph, subgraph_id, attrs) do
    with {:ok, sg} <- Mutations.fetch_subgraph(graph, subgraph_id) do
      hostname = attrs[:hostname] || "nixos"
      child_sg = Subgraph.new(name: hostname, floor: sg.floor + 1)

      machine_meta = %{
        hostname: hostname,
        system: attrs[:system] || "aarch64-linux",
        state_version: attrs[:state_version] || "24.11",
        type: attrs[:type] || :nixos,
        username: attrs[:username] || "user"
      }

      machine_node =
        Node.new(
          type: :gateway,
          name: hostname,
          subgraph_id: child_sg.id,
          machine: machine_meta,
          position: attrs[:position] || %{x: 0, y: 0}
        )

      new_sg = Subgraph.add_node(sg, machine_node)

      new_graph =
        graph
        |> Graph.put_subgraph(new_sg)
        |> Graph.put_subgraph(child_sg)

      {:ok, new_graph, machine_node, child_sg}
    end
  end
end
