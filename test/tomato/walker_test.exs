defmodule Tomato.WalkerTest do
  use ExUnit.Case, async: true

  alias Tomato.{Walker, Graph, Subgraph, Node, Edge}

  describe "walk/1" do
    test "generates NixOS config from graph with leaf nodes" do
      graph = build_graph_with_content()
      output = Walker.walk(graph)

      assert output =~ "{ config, pkgs, lib, ... }:"
      assert output =~ "imports = [ ./hardware-configuration.nix ]"
      assert output =~ "test.option = true;"
    end

    test "empty graph produces skeleton only" do
      graph = Graph.new("empty")
      output = Walker.walk(graph)

      assert output =~ "{ config, pkgs, lib, ... }:"
      refute output =~ "test.option"
    end

    test "interpolates OODN variables" do
      graph = build_graph_with_oodn()
      output = Walker.walk(graph)

      assert output =~ ~s(networking.hostName = "my-host";)
      refute output =~ "${hostname}"
    end

    test "uses OODN values in skeleton" do
      graph = Graph.new("test")
      oodn = Tomato.OODN.new("keymap", "de")
      graph = %{graph | oodn_registry: %{oodn.id => oodn}}

      output = Walker.walk(graph)
      assert output =~ ~s(console.keyMap = "de";)
    end

    test "recurses into gateway subgraphs" do
      graph = build_graph_with_gateway()
      output = Walker.walk(graph)

      assert output =~ "root.content = true;"
      assert output =~ "child.content = true;"
    end
  end

  describe "interpolate/2" do
    test "replaces known keys" do
      assert Walker.interpolate(~S(host = "${name}";), %{"name" => "foo"}) ==
               ~s(host = "foo";)
    end

    test "leaves unknown keys as-is" do
      assert Walker.interpolate(~S(x = ${unknown};), %{}) == ~S(x = ${unknown};)
    end

    test "handles multiple replacements" do
      result = Walker.interpolate(~S(${a} and ${b}), %{"a" => "1", "b" => "2"})
      assert result == "1 and 2"
    end
  end

  describe "validate/1" do
    test "returns :disabled when config flag is off" do
      prev = Application.get_env(:tomato, :nix_validation)
      Application.put_env(:tomato, :nix_validation, enabled: false)
      on_exit(fn -> restore_nix_validation(prev) end)

      assert Walker.validate(build_graph_with_content()) == :disabled
    end

    @tag :nix_cli
    test "returns :ok for a graph whose leaves all parse" do
      assert Walker.validate(build_graph_with_content()) == :ok
    end

    @tag :nix_cli
    test "returns :ok for an empty graph" do
      assert Walker.validate(Graph.new("empty")) == :ok
    end

    @tag :nix_cli
    test "returns error with offending node id and name" do
      graph = build_graph_with_bad_leaf()

      assert {:error, [err]} = Walker.validate(graph)
      assert err.node_name == "Bad"
      assert is_binary(err.node_id)
      assert err.reason =~ "error"
      refute err.reason =~ System.tmp_dir!()
    end

    @tag :nix_cli
    test "interpolates OODN before validating (bad node id still attributed)" do
      # Leaf content is valid until interpolation replaces ${broken}
      # with a malformed literal — the error must still point at the
      # offending leaf, not at some post-interpolation artifact.
      graph = build_graph_with_interpolated_bad_leaf()

      assert {:error, [err]} = Walker.validate(graph)
      assert err.node_name == "Interpolated"
    end

    @tag :nix_cli
    test "reports multiple offending nodes" do
      graph = build_graph_with_two_bad_leaves()

      assert {:error, errs} = Walker.validate(graph)
      assert length(errs) == 2
      names = Enum.map(errs, & &1.node_name) |> Enum.sort()
      assert names == ["BadOne", "BadTwo"]
    end
  end

  describe "build_oodn_map/1" do
    test "builds flat key-value map from registry" do
      graph = Graph.new("test")
      o1 = Tomato.OODN.new("k1", "v1")
      o2 = Tomato.OODN.new("k2", "v2")
      graph = %{graph | oodn_registry: %{o1.id => o1, o2.id => o2}}

      oodn = Walker.build_oodn_map(graph)
      assert oodn == %{"k1" => "v1", "k2" => "v2"}
    end
  end

  # --- Helpers ---

  defp build_graph_with_content do
    graph = Graph.new("test")
    root = Graph.root_subgraph(graph)
    input = Subgraph.input_node(root)
    output = Subgraph.output_node(root)

    leaf = Node.new(type: :leaf, name: "Test", content: "test.option = true;")
    root = Subgraph.add_node(root, leaf)

    root =
      root
      |> Subgraph.add_edge(Edge.new(input.id, leaf.id))
      |> Subgraph.add_edge(Edge.new(leaf.id, output.id))

    Graph.put_subgraph(graph, root)
  end

  defp build_graph_with_oodn do
    graph = build_graph_with_content()
    root = Graph.root_subgraph(graph)

    # Replace leaf content with OODN reference
    leaf = Enum.find_value(root.nodes, fn {_id, n} -> if n.type == :leaf, do: n end)
    root = Subgraph.update_node(root, leaf.id, content: ~S(networking.hostName = "${hostname}";))
    graph = Graph.put_subgraph(graph, root)

    oodn = Tomato.OODN.new("hostname", "my-host")
    %{graph | oodn_registry: %{oodn.id => oodn}}
  end

  defp build_graph_with_bad_leaf do
    graph = Graph.new("bad")
    root = Graph.root_subgraph(graph)
    input = Subgraph.input_node(root)
    output = Subgraph.output_node(root)

    # `= ;` is a Nix parse error — missing RHS
    bad = Node.new(type: :leaf, name: "Bad", content: "services.openssh.enable = ;")
    root = Subgraph.add_node(root, bad)

    root =
      root
      |> Subgraph.add_edge(Edge.new(input.id, bad.id))
      |> Subgraph.add_edge(Edge.new(bad.id, output.id))

    Graph.put_subgraph(graph, root)
  end

  defp build_graph_with_interpolated_bad_leaf do
    graph = Graph.new("interpolated")
    root = Graph.root_subgraph(graph)
    input = Subgraph.input_node(root)
    output = Subgraph.output_node(root)

    # After OODN interpolation, content becomes `x = @;` — a parse error
    leaf = Node.new(type: :leaf, name: "Interpolated", content: "x = ${bad};")
    root = Subgraph.add_node(root, leaf)

    root =
      root
      |> Subgraph.add_edge(Edge.new(input.id, leaf.id))
      |> Subgraph.add_edge(Edge.new(leaf.id, output.id))

    graph = Graph.put_subgraph(graph, root)
    oodn = Tomato.OODN.new("bad", "@")
    %{graph | oodn_registry: %{oodn.id => oodn}}
  end

  defp build_graph_with_two_bad_leaves do
    graph = Graph.new("two_bad")
    root = Graph.root_subgraph(graph)
    input = Subgraph.input_node(root)
    output = Subgraph.output_node(root)

    one = Node.new(type: :leaf, name: "BadOne", content: "a = ;")
    two = Node.new(type: :leaf, name: "BadTwo", content: "b = ;")
    root = root |> Subgraph.add_node(one) |> Subgraph.add_node(two)

    root =
      root
      |> Subgraph.add_edge(Edge.new(input.id, one.id))
      |> Subgraph.add_edge(Edge.new(one.id, two.id))
      |> Subgraph.add_edge(Edge.new(two.id, output.id))

    Graph.put_subgraph(graph, root)
  end

  defp restore_nix_validation(nil), do: Application.delete_env(:tomato, :nix_validation)
  defp restore_nix_validation(prev), do: Application.put_env(:tomato, :nix_validation, prev)

  defp build_graph_with_gateway do
    graph = Graph.new("test")
    root = Graph.root_subgraph(graph)
    input = Subgraph.input_node(root)
    output = Subgraph.output_node(root)

    # Root leaf
    root_leaf = Node.new(type: :leaf, name: "RootLeaf", content: "root.content = true;")
    root = Subgraph.add_node(root, root_leaf)

    # Child subgraph
    child = Subgraph.new(name: "child", floor: 1)
    child_input = Subgraph.input_node(child)
    child_output = Subgraph.output_node(child)
    child_leaf = Node.new(type: :leaf, name: "ChildLeaf", content: "child.content = true;")
    child = Subgraph.add_node(child, child_leaf)

    child =
      child
      |> Subgraph.add_edge(Edge.new(child_input.id, child_leaf.id))
      |> Subgraph.add_edge(Edge.new(child_leaf.id, child_output.id))

    # Gateway
    gateway = Node.new(type: :gateway, name: "GW", subgraph_id: child.id)
    root = Subgraph.add_node(root, gateway)

    # Wire root
    root =
      root
      |> Subgraph.add_edge(Edge.new(input.id, root_leaf.id))
      |> Subgraph.add_edge(Edge.new(root_leaf.id, gateway.id))
      |> Subgraph.add_edge(Edge.new(gateway.id, output.id))

    graph
    |> Graph.put_subgraph(root)
    |> Graph.put_subgraph(child)
  end
end
