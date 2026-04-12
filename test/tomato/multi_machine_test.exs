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

  describe "shared fragment target filtering" do
    test "shared :nixos fragment is excluded from Home Manager machines" do
      graph = build_mixed_graph_with_shared_nixos()
      graph = %{graph | backend: :flake}
      output = Walker.walk(graph)

      # The shared NixOS firewall must appear in the NixOS server
      assert output =~ "networking.firewall.enable = true;"

      # ...but exactly once — it must NOT appear in the HM laptop.
      # split on the fragment: n occurrences => n+1 pieces.
      occurrences = output |> String.split("networking.firewall.enable = true;") |> length()

      assert occurrences == 2,
             "expected shared :nixos fragment in exactly 1 machine, got #{occurrences - 1}"
    end

    test "shared :home_manager fragment is excluded from NixOS machines" do
      graph = build_mixed_graph_with_shared_hm()
      graph = %{graph | backend: :flake}
      output = Walker.walk(graph)

      # Shared HM-only fragment must appear in the HM laptop
      assert output =~ "programs.direnv.enable = true;"

      # ...but not in the NixOS server
      occurrences = output |> String.split("programs.direnv.enable = true;") |> length()

      assert occurrences == 2,
             "expected shared :home_manager fragment in exactly 1 machine, got #{occurrences - 1}"
    end

    test "shared :all fragment appears in both NixOS and HM machines" do
      graph = build_mixed_graph_with_shared_all()
      graph = %{graph | backend: :flake}
      output = Walker.walk(graph)

      # Fragment tagged :all must appear in BOTH configs
      occurrences = output |> String.split("universal.marker = true;") |> length()

      assert occurrences == 3,
             "expected :all fragment in both machines, got #{occurrences - 1}"
    end

    test "in-machine leaves are preserved regardless of target" do
      # The default leaf target is :nixos, but content the user explicitly
      # places inside a Home Manager machine gateway must still appear in
      # that machine's config — the gateway structure is the scope, not
      # the leaf's target tag. Filtering in-machine content by target
      # would strip the Git leaf out of build_mixed_graph/0's HM machine.
      graph = build_mixed_graph()
      graph = %{graph | backend: :flake}
      output = Walker.walk(graph)

      # Git leaf is inside the HM macbook gateway; must appear in output.
      assert output =~ "programs.git.enable = true;"
      # SSH leaf is inside the NixOS server gateway; must appear too.
      assert output =~ "services.openssh.enable = true;"
    end
  end

  defp build_mixed_graph_with_shared_nixos do
    add_shared_leaf(build_mixed_graph(), "Firewall", "networking.firewall.enable = true;", :nixos)
  end

  defp build_mixed_graph_with_shared_hm do
    add_shared_leaf(build_mixed_graph(), "Direnv", "programs.direnv.enable = true;", :home_manager)
  end

  defp build_mixed_graph_with_shared_all do
    add_shared_leaf(build_mixed_graph(), "Universal", "universal.marker = true;", :all)
  end

  defp add_shared_leaf(graph, name, content, target) do
    root = Graph.root_subgraph(graph)
    input = Subgraph.input_node(root)

    shared = Node.new(type: :leaf, name: name, content: content, target: target)
    root = Subgraph.add_node(root, shared)
    root = Subgraph.add_edge(root, Edge.new(input.id, shared.id))

    Graph.put_subgraph(graph, root)
  end

  describe "per-machine oodn_overrides" do
    test "machine oodn_overrides shadow global OODN for that machine only" do
      graph = build_two_nginx_machines_with_overrides()
      graph = %{graph | backend: :flake}
      output = Walker.walk(graph)

      # Each machine should get its own nginx_port via the override
      assert output =~ ~s(nginx on port 8080)
      assert output =~ ~s(nginx on port 8081)
    end

    test "unset override falls through to global OODN" do
      graph = build_nginx_with_only_global_port()
      graph = %{graph | backend: :flake}
      output = Walker.walk(graph)

      # Machine without an override uses the global nginx_port=80
      assert output =~ ~s(nginx on port 80)
    end

    test "override wins over hardcoded hostname" do
      # oodn_overrides is merged AFTER the hardcoded machine keys, so a
      # user who sets `hostname` in overrides can shadow the gateway's
      # machine.hostname. This is intentional — overrides are the highest
      # precedence layer.
      graph = build_machine_with_override_hostname()
      graph = %{graph | backend: :flake}
      output = Walker.walk(graph)

      assert output =~ ~s(hostname-via-override)
    end
  end

  defp build_two_nginx_machines_with_overrides do
    graph = Graph.new("two-nginx")
    oodn = Tomato.OODN.new("nginx_port", "80")
    graph = %{graph | oodn_registry: %{oodn.id => oodn}}

    root = Graph.root_subgraph(graph)
    input = Subgraph.input_node(root)
    output = Subgraph.output_node(root)

    {root, graph} = add_nginx_machine(graph, root, "srv-a", %{"nginx_port" => "8080"}, 100)
    {root, graph} = add_nginx_machine(graph, root, "srv-b", %{"nginx_port" => "8081"}, 300)

    machines = Walker.find_machines(root)
    [m1, m2] = machines

    root =
      root
      |> Subgraph.add_edge(Edge.new(input.id, m1.id))
      |> Subgraph.add_edge(Edge.new(input.id, m2.id))
      |> Subgraph.add_edge(Edge.new(m1.id, output.id))
      |> Subgraph.add_edge(Edge.new(m2.id, output.id))

    Graph.put_subgraph(graph, root)
  end

  defp build_nginx_with_only_global_port do
    graph = Graph.new("one-nginx")
    oodn = Tomato.OODN.new("nginx_port", "80")
    graph = %{graph | oodn_registry: %{oodn.id => oodn}}

    root = Graph.root_subgraph(graph)
    input = Subgraph.input_node(root)
    output = Subgraph.output_node(root)

    {root, graph} = add_nginx_machine(graph, root, "srv", %{}, 200)
    [m] = Walker.find_machines(root)

    root =
      root
      |> Subgraph.add_edge(Edge.new(input.id, m.id))
      |> Subgraph.add_edge(Edge.new(m.id, output.id))

    Graph.put_subgraph(graph, root)
  end

  defp build_machine_with_override_hostname do
    graph = Graph.new("override-host")

    root = Graph.root_subgraph(graph)
    input = Subgraph.input_node(root)
    output = Subgraph.output_node(root)

    # Build a machine whose hardcoded hostname is "srv-real" but whose
    # oodn_overrides sets hostname="hostname-via-override". The leaf
    # inside interpolates ${hostname}.
    child = Subgraph.new(name: "srv-real", floor: 1)
    cin = Subgraph.input_node(child)
    cout = Subgraph.output_node(child)
    leaf = Node.new(type: :leaf, name: "Host", content: ~S(host.label = "${hostname}";))

    child =
      child
      |> Subgraph.add_node(leaf)
      |> Subgraph.add_edge(Edge.new(cin.id, leaf.id))
      |> Subgraph.add_edge(Edge.new(leaf.id, cout.id))

    machine =
      Node.new(
        type: :gateway,
        name: "srv-real",
        subgraph_id: child.id,
        machine: %{
          hostname: "srv-real",
          system: "x86_64-linux",
          state_version: "24.11",
          type: :nixos,
          oodn_overrides: %{"hostname" => "hostname-via-override"}
        }
      )

    root =
      root
      |> Subgraph.add_node(machine)
      |> Subgraph.add_edge(Edge.new(input.id, machine.id))
      |> Subgraph.add_edge(Edge.new(machine.id, output.id))

    graph |> Graph.put_subgraph(root) |> Graph.put_subgraph(child)
  end

  # Build an nginx-serving machine subgraph and return {root, graph} with
  # the machine added at the given root position.
  defp add_nginx_machine(graph, root, hostname, overrides, x) do
    child = Subgraph.new(name: hostname, floor: 1)
    cin = Subgraph.input_node(child)
    cout = Subgraph.output_node(child)

    leaf =
      Node.new(
        type: :leaf,
        name: "Nginx",
        content: ~S(nginx on port ${nginx_port})
      )

    child =
      child
      |> Subgraph.add_node(leaf)
      |> Subgraph.add_edge(Edge.new(cin.id, leaf.id))
      |> Subgraph.add_edge(Edge.new(leaf.id, cout.id))

    machine =
      Node.new(
        type: :gateway,
        name: hostname,
        subgraph_id: child.id,
        position: %{x: x, y: 200},
        machine: %{
          hostname: hostname,
          system: "x86_64-linux",
          state_version: "24.11",
          type: :nixos,
          oodn_overrides: overrides
        }
      )

    root = Subgraph.add_node(root, machine)
    {root, graph |> Graph.put_subgraph(child)}
  end

  describe "Home Manager machines" do
    test "home_manager machine generates homeConfigurations" do
      graph = build_mixed_graph()
      graph = %{graph | backend: :flake}
      output = Walker.walk(graph)

      assert output =~ "nixosConfigurations"
      assert output =~ "homeConfigurations"
    end

    test "homeConfigurations uses username@hostname format" do
      graph = build_mixed_graph()
      graph = %{graph | backend: :flake}
      output = Walker.walk(graph)

      assert output =~ ~s("alex@macbook")
    end

    test "homeConfigurations uses home-manager.lib.homeManagerConfiguration" do
      graph = build_mixed_graph()
      graph = %{graph | backend: :flake}
      output = Walker.walk(graph)

      assert output =~ "home-manager.lib.homeManagerConfiguration"
    end

    test "home config sets home.username and home.homeDirectory" do
      graph = build_mixed_graph()
      graph = %{graph | backend: :flake}
      output = Walker.walk(graph)

      assert output =~ ~s(home.username = "alex")
      assert output =~ ~s(home.homeDirectory = "/home/alex")
    end

    test "nixos machine does not appear in homeConfigurations" do
      graph = build_mixed_graph()
      graph = %{graph | backend: :flake}
      output = Walker.walk(graph)

      refute output =~ ~s("server" = home-manager)
    end
  end

  defp build_mixed_graph do
    graph = Graph.new("mixed")
    oodn = Tomato.OODN.new("input_nixpkgs", "github:nixos/nixpkgs")
    oodn_hm = Tomato.OODN.new("input_home-manager", "github:nix-community/home-manager")
    graph = %{graph | oodn_registry: %{oodn.id => oodn, oodn_hm.id => oodn_hm}}

    root = Graph.root_subgraph(graph)
    input = Subgraph.input_node(root)
    output = Subgraph.output_node(root)

    # NixOS machine
    c1 = Subgraph.new(name: "server", floor: 1)
    c1i = Subgraph.input_node(c1)
    c1o = Subgraph.output_node(c1)
    c1l = Node.new(type: :leaf, name: "SSH", content: "services.openssh.enable = true;")

    c1 =
      c1
      |> Subgraph.add_node(c1l)
      |> Subgraph.add_edge(Edge.new(c1i.id, c1l.id))
      |> Subgraph.add_edge(Edge.new(c1l.id, c1o.id))

    m1 =
      Node.new(
        type: :gateway,
        name: "server",
        subgraph_id: c1.id,
        machine: %{
          hostname: "server",
          system: "x86_64-linux",
          state_version: "24.11",
          type: :nixos,
          username: "root"
        }
      )

    # Home Manager machine
    c2 = Subgraph.new(name: "macbook", floor: 1)
    c2i = Subgraph.input_node(c2)
    c2o = Subgraph.output_node(c2)
    c2l = Node.new(type: :leaf, name: "Git", content: ~S(programs.git.enable = true;))

    c2 =
      c2
      |> Subgraph.add_node(c2l)
      |> Subgraph.add_edge(Edge.new(c2i.id, c2l.id))
      |> Subgraph.add_edge(Edge.new(c2l.id, c2o.id))

    m2 =
      Node.new(
        type: :gateway,
        name: "macbook",
        subgraph_id: c2.id,
        machine: %{
          hostname: "macbook",
          system: "aarch64-darwin",
          state_version: "24.11",
          type: :home_manager,
          username: "alex"
        }
      )

    root = root |> Subgraph.add_node(m1) |> Subgraph.add_node(m2)

    root =
      root
      |> Subgraph.add_edge(Edge.new(input.id, m1.id))
      |> Subgraph.add_edge(Edge.new(input.id, m2.id))
      |> Subgraph.add_edge(Edge.new(m1.id, output.id))
      |> Subgraph.add_edge(Edge.new(m2.id, output.id))

    graph
    |> Graph.put_subgraph(root)
    |> Graph.put_subgraph(c1)
    |> Graph.put_subgraph(c2)
  end
end
