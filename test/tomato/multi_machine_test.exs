defmodule Tomato.MultiMachineTest do
  use ExUnit.Case, async: true

  alias Tomato.{Walker, Graph, Subgraph, Node, Edge}

  describe "machine nodes" do
    test "Node.machine? detects machine gateways" do
      machine =
        Node.new(
          type: :gateway,
          name: "srv",
          machine: %{hostname: "srv", system: "x86_64-linux", state_version: "24.11"}
        )

      gateway = Node.new(type: :gateway, name: "gw")
      leaf = Node.new(type: :leaf, name: "leaf")

      assert Node.machine?(machine)
      refute Node.machine?(gateway)
      refute Node.machine?(leaf)
    end

    test "find_machines returns only machine gateways" do
      sg = Subgraph.new(name: "root")

      machine =
        Node.new(
          type: :gateway,
          name: "srv",
          machine: %{hostname: "srv", system: "x86_64-linux", state_version: "24.11"}
        )

      gateway = Node.new(type: :gateway, name: "gw", subgraph_id: "fake")
      leaf = Node.new(type: :leaf, name: "leaf")

      sg =
        sg |> Subgraph.add_node(machine) |> Subgraph.add_node(gateway) |> Subgraph.add_node(leaf)

      machines = Walker.find_machines(sg)
      assert length(machines) == 1
      assert hd(machines).name == "srv"
    end
  end

  describe "per-machine OODN override" do
    test "machine hostname overrides global OODN in subtree" do
      graph = build_multi_machine_graph()
      graph = %{graph | backend: :flake}
      output = Walker.walk(graph)

      # Both machine hostnames should appear
      assert output =~ ~s(networking.hostName = "server-1")
      assert output =~ ~s(networking.hostName = "server-2")
      # Global hostname should not appear in configs
      refute output =~ ~s(networking.hostName = "global-host")
    end

    test "each machine gets its own nixosConfigurations entry in flake mode" do
      graph = build_multi_machine_graph()
      graph = %{graph | backend: :flake}
      output = Walker.walk(graph)

      assert output =~ ~s(nixosConfigurations = {)
      assert output =~ ~s("server-1" = nixpkgs.lib.nixosSystem)
      assert output =~ ~s("server-2" = nixpkgs.lib.nixosSystem)
    end

    test "different system arches per machine" do
      graph = build_multi_machine_graph()
      graph = %{graph | backend: :flake}
      output = Walker.walk(graph)

      assert output =~ ~s(system = "aarch64-linux")
      assert output =~ ~s(system = "x86_64-linux")
    end

    test "shared fragments appear in each machine config" do
      graph = build_multi_machine_graph_with_shared()
      graph = %{graph | backend: :flake}
      output = Walker.walk(graph)

      # Shared config should appear in both machine configs
      occurrences = output |> String.split("shared.option = true;") |> length()
      # Should appear at least twice (once per machine)
      assert occurrences >= 3
    end
  end

  describe "traditional backend with machines" do
    test "traditional backend walks normally regardless of machines" do
      graph = build_multi_machine_graph()
      graph = %{graph | backend: :traditional}
      output = Walker.walk(graph)

      # Traditional mode walks the full graph as-is
      assert output =~ "{ config, pkgs, lib, ... }:"
    end
  end

  # --- Helpers ---

  defp build_multi_machine_graph do
    graph = Graph.new("multi")

    # Add OODNs
    oodn1 = Tomato.OODN.new("hostname", "global-host")
    graph = %{graph | oodn_registry: %{oodn1.id => oodn1}}

    root = Graph.root_subgraph(graph)
    input = Subgraph.input_node(root)
    output = Subgraph.output_node(root)

    # Machine 1: aarch64
    child1 = Subgraph.new(name: "server-1", floor: 1)
    child1_input = Subgraph.input_node(child1)
    child1_output = Subgraph.output_node(child1)

    child1_leaf =
      Node.new(type: :leaf, name: "Net1", content: ~S(networking.hostName = "${hostname}";))

    child1 =
      child1
      |> Subgraph.add_node(child1_leaf)
      |> Subgraph.add_edge(Edge.new(child1_input.id, child1_leaf.id))
      |> Subgraph.add_edge(Edge.new(child1_leaf.id, child1_output.id))

    m1 =
      Node.new(
        type: :gateway,
        name: "server-1",
        subgraph_id: child1.id,
        machine: %{hostname: "server-1", system: "aarch64-linux", state_version: "24.11"}
      )

    # Machine 2: x86_64
    child2 = Subgraph.new(name: "server-2", floor: 1)
    child2_input = Subgraph.input_node(child2)
    child2_output = Subgraph.output_node(child2)

    child2_leaf =
      Node.new(type: :leaf, name: "Net2", content: ~S(networking.hostName = "${hostname}";))

    child2 =
      child2
      |> Subgraph.add_node(child2_leaf)
      |> Subgraph.add_edge(Edge.new(child2_input.id, child2_leaf.id))
      |> Subgraph.add_edge(Edge.new(child2_leaf.id, child2_output.id))

    m2 =
      Node.new(
        type: :gateway,
        name: "server-2",
        subgraph_id: child2.id,
        machine: %{hostname: "server-2", system: "x86_64-linux", state_version: "23.11"}
      )

    # Wire root
    root = root |> Subgraph.add_node(m1) |> Subgraph.add_node(m2)

    root =
      root
      |> Subgraph.add_edge(Edge.new(input.id, m1.id))
      |> Subgraph.add_edge(Edge.new(input.id, m2.id))

    root =
      root
      |> Subgraph.add_edge(Edge.new(m1.id, output.id))
      |> Subgraph.add_edge(Edge.new(m2.id, output.id))

    graph |> Graph.put_subgraph(root) |> Graph.put_subgraph(child1) |> Graph.put_subgraph(child2)
  end

  defp build_multi_machine_graph_with_shared do
    graph = build_multi_machine_graph()
    root = Graph.root_subgraph(graph)
    input = Subgraph.input_node(root)

    # Add a shared leaf at root level (not inside any machine)
    shared = Node.new(type: :leaf, name: "Shared", content: "shared.option = true;")
    root = Subgraph.add_node(root, shared)
    root = Subgraph.add_edge(root, Edge.new(input.id, shared.id))

    # Connect shared to both machines
    machines = Walker.find_machines(root)

    root =
      Enum.reduce(machines, root, fn m, acc ->
        Subgraph.add_edge(acc, Edge.new(shared.id, m.id))
      end)

    Graph.put_subgraph(graph, root)
  end
end
