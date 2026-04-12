defmodule Tomato.Backend.FlakeTest do
  use ExUnit.Case, async: true

  alias Tomato.{Backend.Flake, Graph, Subgraph, Node, Edge, Walker}

  describe "finalize/2" do
    test "generates valid flake.nix structure" do
      output = Flake.finalize(["services.nginx.enable = true;"], %{})

      assert output =~ "inputs = {"
      assert output =~ "outputs ="
      assert output =~ "nixosConfigurations"
      assert output =~ "services.nginx.enable = true;"
    end

    test "includes hostname from OODN" do
      output = Flake.finalize([], %{"hostname" => "my-server"})
      assert output =~ ~s(nixosConfigurations."my-server")
    end

    test "includes system arch from OODN" do
      output = Flake.finalize([], %{"system_arch" => "x86_64-linux"})
      assert output =~ ~s(system = "x86_64-linux")
    end

    test "generates inputs from input_ OODNs" do
      oodn = %{
        "input_nixpkgs" => "github:nixos/nixpkgs?ref=nixos-unstable",
        "input_sops-nix" => "github:Mic92/sops-nix"
      }

      output = Flake.finalize([], oodn)
      assert output =~ ~s(nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable")
      assert output =~ ~s(sops-nix.url = "github:Mic92/sops-nix")
    end

    test "generates follows declarations" do
      oodn = %{
        "input_nixpkgs" => "github:nixos/nixpkgs",
        "input_home-manager" => "github:nix-community/home-manager",
        "input_home-manager_follows" => "nixpkgs"
      }

      output = Flake.finalize([], oodn)
      assert output =~ ~s(home-manager.inputs.nixpkgs.follows = "nixpkgs")
    end

    test "input names appear in output args" do
      oodn = %{
        "input_nixpkgs" => "github:nixos/nixpkgs",
        "input_home-manager" => "github:nix-community/home-manager"
      }

      output = Flake.finalize([], oodn)
      assert output =~ "home-manager, nixpkgs, ..."
    end

    test "preserves SSH in skeleton" do
      output = Flake.finalize([], %{})
      assert output =~ "services.openssh"
      assert output =~ "PermitRootLogin"
    end

    test "uses keymap and state_version from OODN" do
      output = Flake.finalize([], %{"keymap" => "de", "state_version" => "23.11"})
      assert output =~ ~s(console.keyMap = "de")
      assert output =~ ~s(system.stateVersion = "23.11")
    end
  end

  describe "Walker.walk/1 with flake backend" do
    test "dispatches to flake backend when graph.backend is :flake" do
      graph = build_flake_graph()
      output = Walker.walk(graph)

      assert output =~ "inputs = {"
      assert output =~ "nixosConfigurations"
      assert output =~ "test.option = true;"
    end

    test "dispatches to traditional backend by default" do
      graph = build_traditional_graph()
      output = Walker.walk(graph)

      assert output =~ "{ config, pkgs, lib, ... }:"
      refute output =~ "nixosConfigurations"
    end
  end

  defp build_flake_graph do
    graph = %{Graph.new("test") | backend: :flake}
    root = Graph.root_subgraph(graph)
    input = Subgraph.input_node(root)
    output = Subgraph.output_node(root)

    leaf = Node.new(type: :leaf, name: "Test", content: "test.option = true;")
    root = Subgraph.add_node(root, leaf)

    root =
      root
      |> Subgraph.add_edge(Edge.new(input.id, leaf.id))
      |> Subgraph.add_edge(Edge.new(leaf.id, output.id))

    graph
    |> Graph.put_subgraph(root)
    |> Map.put(:oodn_registry, %{})
  end

  defp build_traditional_graph do
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
end
