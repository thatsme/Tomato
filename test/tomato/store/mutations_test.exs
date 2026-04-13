defmodule Tomato.Store.MutationsTest do
  use ExUnit.Case, async: true

  alias Tomato.{Graph, Subgraph}
  alias Tomato.Store.Mutations

  setup do
    graph = Graph.new("test")
    sg = Graph.root_subgraph(graph)
    {:ok, graph: graph, sg: sg}
  end

  describe "add_node/3" do
    test "adds a leaf node to the subgraph", %{graph: graph, sg: sg} do
      {:ok, new_graph, node} = Mutations.add_node(graph, sg.id, type: :leaf, name: "N1")

      assert node.type == :leaf
      assert node.name == "N1"

      new_sg = Graph.get_subgraph(new_graph, sg.id)
      assert Map.has_key?(new_sg.nodes, node.id)
    end

    test "returns :subgraph_not_found for unknown subgraph", %{graph: graph} do
      assert {:error, :subgraph_not_found, _} =
               Mutations.add_node(graph, "nonexistent", type: :leaf, name: "X")
    end
  end

  describe "remove_node/3" do
    test "removes a leaf node", %{graph: graph, sg: sg} do
      {:ok, graph, node} = Mutations.add_node(graph, sg.id, type: :leaf, name: "R")
      {:ok, graph} = Mutations.remove_node(graph, sg.id, node.id)

      new_sg = Graph.get_subgraph(graph, sg.id)
      refute Map.has_key?(new_sg.nodes, node.id)
    end

    test "refuses to delete input node", %{graph: graph, sg: sg} do
      input = Subgraph.input_node(sg)
      assert {:error, :undeletable, _} = Mutations.remove_node(graph, sg.id, input.id)
    end

    test "refuses to delete output node", %{graph: graph, sg: sg} do
      output = Subgraph.output_node(sg)
      assert {:error, :undeletable, _} = Mutations.remove_node(graph, sg.id, output.id)
    end

    test "returns :node_not_found for unknown node", %{graph: graph, sg: sg} do
      assert {:error, :node_not_found, _} =
               Mutations.remove_node(graph, sg.id, "missing-id")
    end
  end

  describe "update_node/4" do
    test "updates node attributes", %{graph: graph, sg: sg} do
      {:ok, graph, node} = Mutations.add_node(graph, sg.id, type: :leaf, name: "Before")

      {:ok, graph} =
        Mutations.update_node(graph, sg.id, node.id, name: "After", content: "x = 1;")

      new_sg = Graph.get_subgraph(graph, sg.id)
      updated = Map.get(new_sg.nodes, node.id)
      assert updated.name == "After"
      assert updated.content == "x = 1;"
    end
  end

  describe "add_edge/4" do
    test "adds a valid edge", %{graph: graph, sg: sg} do
      input = Subgraph.input_node(sg)
      {:ok, graph, n1} = Mutations.add_node(graph, sg.id, type: :leaf, name: "A")
      {:ok, new_graph, edge} = Mutations.add_edge(graph, sg.id, input.id, n1.id)

      assert edge.from == input.id
      assert edge.to == n1.id

      new_sg = Graph.get_subgraph(new_graph, sg.id)
      assert Map.has_key?(new_sg.edges, edge.id)
    end

    test "rejects a cycle-forming edge", %{graph: graph, sg: sg} do
      {:ok, graph, n1} = Mutations.add_node(graph, sg.id, type: :leaf, name: "A")
      {:ok, graph, n2} = Mutations.add_node(graph, sg.id, type: :leaf, name: "B")
      {:ok, graph, _} = Mutations.add_edge(graph, sg.id, n1.id, n2.id)

      assert {:error, :cycle, _} = Mutations.add_edge(graph, sg.id, n2.id, n1.id)
    end
  end

  describe "remove_edge/3" do
    test "removes an existing edge", %{graph: graph, sg: sg} do
      input = Subgraph.input_node(sg)
      {:ok, graph, n1} = Mutations.add_node(graph, sg.id, type: :leaf, name: "A")
      {:ok, graph, edge} = Mutations.add_edge(graph, sg.id, input.id, n1.id)
      {:ok, graph} = Mutations.remove_edge(graph, sg.id, edge.id)

      new_sg = Graph.get_subgraph(graph, sg.id)
      refute Map.has_key?(new_sg.edges, edge.id)
    end
  end

  describe "add_gateway/3" do
    test "creates a gateway and its child subgraph", %{graph: graph, sg: sg} do
      {:ok, new_graph, gw, child_sg} = Mutations.add_gateway(graph, sg.id, name: "GW")

      assert gw.type == :gateway
      assert gw.subgraph_id == child_sg.id
      assert child_sg.floor == 1

      assert %Subgraph{} = Graph.get_subgraph(new_graph, child_sg.id)
    end
  end

  describe "set_backend/2" do
    test "switches backend to :flake", %{graph: graph} do
      new_graph = Mutations.set_backend(graph, :flake)
      assert new_graph.backend == :flake
    end

    test "switches backend to :traditional", %{graph: graph} do
      new_graph = graph |> Mutations.set_backend(:flake) |> Mutations.set_backend(:traditional)
      assert new_graph.backend == :traditional
    end
  end
end
