defmodule Tomato.StoreTest do
  use ExUnit.Case

  alias Tomato.{Store, Graph, Subgraph}

  setup do
    dir = System.tmp_dir!() |> Path.join("tomato_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    name = :"store_test_#{System.unique_integer([:positive])}"
    {:ok, pid} = Store.start_link(name: name, graphs_dir: dir)

    on_exit(fn ->
      try do
        GenServer.stop(pid, :normal, 1000)
      catch
        :exit, _ -> :ok
      end

      File.rm_rf!(dir)
    end)

    %{store: pid, dir: dir}
  end

  describe "graph operations" do
    test "get_graph returns a graph", %{store: s} do
      graph = Store.get_graph(s)
      assert %Graph{} = graph
      assert graph.name == "default"
    end

    test "get_subgraph returns root subgraph", %{store: s} do
      graph = Store.get_graph(s)
      sg = Store.get_subgraph(s, graph.root_subgraph_id)
      assert %Subgraph{} = sg
      assert sg.floor == 0
    end
  end

  describe "node operations" do
    test "add_node creates a leaf node", %{store: s} do
      graph = Store.get_graph(s)
      sg = Graph.root_subgraph(graph)

      {:ok, node} = Store.add_node(s, sg.id, type: :leaf, name: "Test")
      assert node.type == :leaf
      assert node.name == "Test"

      updated_sg = Store.get_subgraph(s, sg.id)
      assert Map.has_key?(updated_sg.nodes, node.id)
    end

    test "remove_node deletes a leaf node", %{store: s} do
      graph = Store.get_graph(s)
      sg = Graph.root_subgraph(graph)

      {:ok, node} = Store.add_node(s, sg.id, type: :leaf, name: "ToDelete")
      assert :ok = Store.remove_node(s, sg.id, node.id)

      updated_sg = Store.get_subgraph(s, sg.id)
      refute Map.has_key?(updated_sg.nodes, node.id)
    end

    test "cannot delete input node", %{store: s} do
      graph = Store.get_graph(s)
      sg = Graph.root_subgraph(graph)
      input = Subgraph.input_node(sg)

      assert {:error, :undeletable, _} = Store.remove_node(s, sg.id, input.id)
    end

    test "cannot delete output node", %{store: s} do
      graph = Store.get_graph(s)
      sg = Graph.root_subgraph(graph)
      output = Subgraph.output_node(sg)

      assert {:error, :undeletable, _} = Store.remove_node(s, sg.id, output.id)
    end

    test "update_node changes node properties", %{store: s} do
      graph = Store.get_graph(s)
      sg = Graph.root_subgraph(graph)

      {:ok, node} = Store.add_node(s, sg.id, type: :leaf, name: "Before")
      :ok = Store.update_node(s, sg.id, node.id, name: "After", content: "x = 1;")

      updated_sg = Store.get_subgraph(s, sg.id)
      updated_node = Map.get(updated_sg.nodes, node.id)
      assert updated_node.name == "After"
      assert updated_node.content == "x = 1;"
    end
  end

  describe "edge operations" do
    test "add_edge creates a valid edge", %{store: s} do
      graph = Store.get_graph(s)
      sg = Graph.root_subgraph(graph)
      input = Subgraph.input_node(sg)

      {:ok, node} = Store.add_node(s, sg.id, type: :leaf, name: "N")
      {:ok, edge} = Store.add_edge(s, sg.id, input.id, node.id)

      assert edge.from == input.id
      assert edge.to == node.id
    end

    test "rejects edge that creates a cycle", %{store: s} do
      graph = Store.get_graph(s)
      sg = Graph.root_subgraph(graph)

      {:ok, n1} = Store.add_node(s, sg.id, type: :leaf, name: "A")
      {:ok, n2} = Store.add_node(s, sg.id, type: :leaf, name: "B")

      {:ok, _} = Store.add_edge(s, sg.id, n1.id, n2.id)
      assert {:error, :cycle, _} = Store.add_edge(s, sg.id, n2.id, n1.id)
    end

    test "remove_edge deletes an edge", %{store: s} do
      graph = Store.get_graph(s)
      sg = Graph.root_subgraph(graph)
      input = Subgraph.input_node(sg)

      {:ok, node} = Store.add_node(s, sg.id, type: :leaf, name: "N")
      {:ok, edge} = Store.add_edge(s, sg.id, input.id, node.id)
      :ok = Store.remove_edge(s, sg.id, edge.id)

      updated_sg = Store.get_subgraph(s, sg.id)
      refute Map.has_key?(updated_sg.edges, edge.id)
    end
  end

  describe "gateway operations" do
    test "add_gateway creates gateway + child subgraph", %{store: s} do
      graph = Store.get_graph(s)
      sg = Graph.root_subgraph(graph)

      {:ok, gw, child} = Store.add_gateway(s, sg.id, name: "GW")
      assert gw.type == :gateway
      assert gw.subgraph_id == child.id
      assert child.floor == 1

      child_sg = Store.get_subgraph(s, child.id)
      assert child_sg.name == "GW"
    end
  end

  describe "OODN operations" do
    test "put_oodn adds a key-value pair", %{store: s} do
      {:ok, oodn} = Store.put_oodn(s, "hostname", "test-host")
      assert oodn.key == "hostname"
      assert oodn.value == "test-host"

      graph = Store.get_graph(s)
      assert Map.has_key?(graph.oodn_registry, oodn.id)
    end

    test "update_oodn changes value", %{store: s} do
      {:ok, oodn} = Store.put_oodn(s, "port", "80")
      :ok = Store.update_oodn(s, oodn.id, "8080")

      graph = Store.get_graph(s)
      updated = Map.get(graph.oodn_registry, oodn.id)
      assert updated.value == "8080"
    end

    test "remove_oodn deletes entry", %{store: s} do
      {:ok, oodn} = Store.put_oodn(s, "tmp", "val")
      :ok = Store.remove_oodn(s, oodn.id)

      graph = Store.get_graph(s)
      refute Map.has_key?(graph.oodn_registry, oodn.id)
    end
  end

  describe "graph management" do
    test "new_graph creates and saves", %{store: s, dir: dir} do
      {:ok, graph, filename} = Store.new_graph(s, "my-project")
      assert graph.name == "my-project"
      assert filename == "my-project.json"
      assert File.exists?(Path.join(dir, filename))
    end

    test "list_graphs returns saved files", %{store: s} do
      Store.new_graph(s, "alpha")
      Store.new_graph(s, "beta")

      graphs = Store.list_graphs(s)
      names = Enum.map(graphs, & &1.name)
      assert "alpha" in names
      assert "beta" in names
    end

    test "load_graph switches active graph", %{store: s} do
      {:ok, _, filename} = Store.new_graph(s, "other")
      {:ok, loaded} = Store.load_graph(s, filename)
      assert loaded.name == "other"

      current = Store.get_graph(s)
      assert current.name == "other"
    end
  end

  describe "topic/1" do
    test "strips Elixir. prefix for module atoms" do
      assert Store.topic(Tomato.Store) == "graph:updates:Tomato.Store"
    end

    test "formats plain atoms without modification" do
      assert Store.topic(:test_store_123) == "graph:updates:test_store_123"
    end

    test "falls back to anonymous for nil" do
      assert Store.topic(nil) == "graph:updates:anonymous"
    end
  end
end
