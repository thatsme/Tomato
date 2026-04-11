defmodule Tomato.ConstraintTest do
  use ExUnit.Case, async: true

  alias Tomato.{Constraint, Subgraph, Node, Edge}

  describe "validate/1" do
    test "valid subgraph passes" do
      sg = build_valid_subgraph()
      assert :ok = Constraint.validate(sg)
    end

    test "rejects subgraph without input node" do
      sg = Subgraph.new()
      input = Subgraph.input_node(sg)
      sg = %{sg | nodes: Map.delete(sg.nodes, input.id)}
      leaf = Node.new(type: :leaf, name: "L")
      sg = Subgraph.add_node(sg, leaf)

      assert {:error, :no_input, _} = Constraint.validate(sg)
    end

    test "rejects subgraph without output node" do
      sg = Subgraph.new()
      output = Subgraph.output_node(sg)
      sg = %{sg | nodes: Map.delete(sg.nodes, output.id)}
      leaf = Node.new(type: :leaf, name: "L")
      sg = Subgraph.add_node(sg, leaf)

      assert {:error, :no_output, _} = Constraint.validate(sg)
    end

    test "rejects subgraph with fewer than 3 nodes" do
      sg = Subgraph.new()
      assert {:error, :too_few_nodes, _} = Constraint.validate(sg)
    end

    test "rejects edges referencing non-existent nodes" do
      sg = build_valid_subgraph()
      bad_edge = Edge.new("nonexistent", "also-fake")
      sg = Subgraph.add_edge(sg, bad_edge)

      assert {:error, :invalid_edge, _} = Constraint.validate(sg)
    end

    test "rejects incoming edges to input node" do
      sg = build_valid_subgraph()
      input = Subgraph.input_node(sg)
      leaf = Enum.find_value(sg.nodes, fn {_id, n} -> if n.type == :leaf, do: n end)
      edge = Edge.new(leaf.id, input.id)
      sg = Subgraph.add_edge(sg, edge)

      assert {:error, :input_has_incoming, _} = Constraint.validate(sg)
    end

    test "rejects outgoing edges from output node" do
      sg = build_valid_subgraph()
      output = Subgraph.output_node(sg)
      leaf = Enum.find_value(sg.nodes, fn {_id, n} -> if n.type == :leaf, do: n end)
      edge = Edge.new(output.id, leaf.id)
      sg = Subgraph.add_edge(sg, edge)

      assert {:error, :output_has_outgoing, _} = Constraint.validate(sg)
    end
  end

  describe "topological_sort/1" do
    test "returns sorted node ids for valid DAG" do
      sg = build_valid_subgraph()
      assert {:ok, sorted} = Constraint.topological_sort(sg)
      assert length(sorted) == map_size(sg.nodes)
    end

    test "detects cycles" do
      sg = build_valid_subgraph()
      leaf = Enum.find_value(sg.nodes, fn {_id, n} -> if n.type == :leaf, do: n end)
      input = Subgraph.input_node(sg)

      # Create cycle: input -> leaf -> input (via edges)
      e1 = Edge.new(input.id, leaf.id)
      e2 = Edge.new(leaf.id, input.id)
      sg = sg |> Subgraph.add_edge(e1) |> Subgraph.add_edge(e2)

      assert {:error, :cycle, _} = Constraint.topological_sort(sg)
    end

    test "input node comes first in sort" do
      sg = build_valid_subgraph()
      input = Subgraph.input_node(sg)
      assert {:ok, [first | _]} = Constraint.topological_sort(sg)
      assert first == input.id
    end
  end

  defp build_valid_subgraph do
    sg = Subgraph.new(name: "test")
    input = Subgraph.input_node(sg)
    output = Subgraph.output_node(sg)
    leaf = Node.new(type: :leaf, name: "Leaf", content: "test = true;")
    sg = Subgraph.add_node(sg, leaf)
    e1 = Edge.new(input.id, leaf.id)
    e2 = Edge.new(leaf.id, output.id)
    sg |> Subgraph.add_edge(e1) |> Subgraph.add_edge(e2)
  end
end
