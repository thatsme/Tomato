defmodule Tomato.Store.PersistenceTest do
  use ExUnit.Case, async: true

  alias Tomato.Graph
  alias Tomato.Store.{Machine, Mutations, OODN, Persistence}

  defp roundtrip(%Graph{} = graph) do
    graph |> Persistence.encode() |> Jason.decode!() |> Persistence.decode_graph()
  end

  describe "roundtrip encode/decode" do
    test "preserves an empty graph" do
      decoded = Graph.new("roundtrip") |> roundtrip()

      assert decoded.name == "roundtrip"
      assert decoded.backend == :traditional
      assert map_size(decoded.subgraphs) == 1
    end

    test "preserves leaf nodes with content" do
      graph = Graph.new("with-nodes")
      sg = Graph.root_subgraph(graph)

      {:ok, graph, _} =
        Mutations.add_node(graph, sg.id, type: :leaf, name: "N", content: "x = 1;")

      decoded = roundtrip(graph)
      decoded_sg = Graph.get_subgraph(decoded, sg.id)
      leaf = decoded_sg.nodes |> Map.values() |> Enum.find(&(&1.type == :leaf))

      assert leaf.name == "N"
      assert leaf.content == "x = 1;"
    end

    test "preserves OODN registry entries" do
      graph = Graph.new("with-oodn")
      {graph, _} = OODN.put(graph, "hostname", "host1")
      {graph, _} = OODN.put(graph, "port", "80")

      decoded = roundtrip(graph)
      keys = decoded.oodn_registry |> Map.values() |> Enum.map(& &1.key) |> Enum.sort()

      assert keys == ["hostname", "port"]
    end

    test "preserves flake backend" do
      graph = Graph.new("flake-graph") |> Mutations.set_backend(:flake)
      decoded = roundtrip(graph)

      assert decoded.backend == :flake
    end

    test "preserves machine metadata for :nixos type" do
      graph = Graph.new("with-machine")
      sg = Graph.root_subgraph(graph)

      {:ok, graph, _node, _child} =
        Machine.add(graph, sg.id,
          hostname: "webserver",
          system: "x86_64-linux",
          state_version: "24.11",
          type: :nixos,
          username: "admin"
        )

      decoded = roundtrip(graph)
      decoded_sg = Graph.get_subgraph(decoded, sg.id)
      machine_node = decoded_sg.nodes |> Map.values() |> Enum.find(& &1.machine)

      assert machine_node.machine.hostname == "webserver"
      assert machine_node.machine.system == "x86_64-linux"
      assert machine_node.machine.state_version == "24.11"
      assert machine_node.machine.type == :nixos
      assert machine_node.machine.username == "admin"
    end

    test "preserves :home_manager machine type" do
      graph = Graph.new("home-graph")
      sg = Graph.root_subgraph(graph)

      {:ok, graph, _node, _child} =
        Machine.add(graph, sg.id, hostname: "laptop", type: :home_manager)

      decoded = roundtrip(graph)
      decoded_sg = Graph.get_subgraph(decoded, sg.id)
      machine_node = decoded_sg.nodes |> Map.values() |> Enum.find(& &1.machine)

      assert machine_node.machine.type == :home_manager
      assert machine_node.machine.hostname == "laptop"
    end
  end

  describe "peek_graph_name/1" do
    @tag :tmp_dir
    test "returns the encoded name for a valid graph file", %{tmp_dir: tmp} do
      graph = Graph.new("my-cool-graph")
      path = Path.join(tmp, "mine.json")
      File.write!(path, Persistence.encode(graph))

      assert Persistence.peek_graph_name(path) == "my-cool-graph"
    end

    @tag :tmp_dir
    test "falls back to filename stem for an unreadable file", %{tmp_dir: tmp} do
      path = Path.join(tmp, "ghost.json")
      assert Persistence.peek_graph_name(path) == "ghost"
    end
  end
end
