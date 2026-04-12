defmodule Tomato.Walker do
  @moduledoc """
  Traverses the graph top-down via topological sort and produces
  composed Nix output from leaf node content.

  OODN (Out-Of-DAG Node) values are interpolated into every leaf node's
  content via `${key}` placeholders. The OODN map is built once at walk
  start and carried unchanged to every depth.

  Each leaf declares a `:target` (`:nixos`, `:home_manager`, or `:all`);
  the walker collects `{target, fragment}` tuples internally and filters
  them against the current machine type before passing plain strings to
  the backend. That way a NixOS-only shared leaf (e.g. `networking.*`)
  is never spliced into a Home Manager machine's config.
  """

  alias Tomato.{Constraint, Graph, Node, Subgraph}

  @type tagged_fragment :: {Node.target(), String.t()}

  @doc """
  Walk the entire graph starting from the root subgraph.
  Dispatches to the appropriate backend based on graph.backend.
  Returns the generated .nix string.
  """
  @spec walk(Graph.t()) :: String.t()
  def walk(%Graph{backend: :flake} = graph) do
    oodn = build_oodn_map(graph)
    root = Graph.root_subgraph(graph)
    machines = find_machines(root)

    if machines == [] do
      # No machine nodes — single config in flake format. Treat as NixOS.
      tagged = walk_subgraph(root, graph, oodn)
      fragments = filter_by_target(tagged, :nixos)
      Tomato.Backend.Flake.finalize(fragments, oodn)
    else
      # Multi-machine — generate per-machine configs
      machine_configs =
        Enum.map(machines, fn machine_node ->
          machine_oodn =
            oodn
            |> Map.put("hostname", machine_node.machine.hostname)
            |> Map.put("system_arch", machine_node.machine.system)
            |> Map.put("state_version", machine_node.machine.state_version)
            |> Map.put("username", Map.get(machine_node.machine, :username, "user"))

          child_sg = Graph.get_subgraph(graph, machine_node.subgraph_id)
          tagged = if child_sg, do: walk_subgraph(child_sg, graph, machine_oodn), else: []

          machine_type = Map.get(machine_node.machine, :type, :nixos)
          fragments = filter_by_target(tagged, machine_type)
          {machine_node.machine, fragments}
        end)

      # Shared root-level fragments split by target: NixOS machines only
      # receive :nixos/:all leaves, HM machines only receive :home_manager/:all.
      shared_tagged = walk_shared(root, graph, oodn)
      nixos_shared = filter_by_target(shared_tagged, :nixos)
      hm_shared = filter_by_target(shared_tagged, :home_manager)

      Tomato.Backend.Flake.finalize_multi(machine_configs, nixos_shared, hm_shared, oodn)
    end
  end

  def walk(%Graph{} = graph) do
    oodn = build_oodn_map(graph)
    root = Graph.root_subgraph(graph)
    tagged = walk_subgraph(root, graph, oodn)
    # Traditional backend is NixOS-only.
    fragments = filter_by_target(tagged, :nixos)
    finalize(fragments, oodn)
  end

  @doc """
  Find all machine gateway nodes in a subgraph.
  """
  @spec find_machines(Subgraph.t()) :: list(Node.t())
  def find_machines(%Subgraph{nodes: nodes}) do
    nodes
    |> Map.values()
    |> Enum.filter(&Node.machine?/1)
  end

  @doc """
  Walk only non-machine leaf/gateway nodes in a subgraph (shared config).
  Returns tagged fragments — the caller filters by target.
  """
  @spec walk_shared(Subgraph.t(), Graph.t(), map()) :: [tagged_fragment()]
  def walk_shared(%Subgraph{} = sg, %Graph{} = graph, oodn) do
    case Constraint.topological_sort(sg) do
      {:ok, sorted_ids} ->
        Enum.flat_map(sorted_ids, fn node_id ->
          node = Map.get(sg.nodes, node_id)

          if Node.machine?(node) do
            []
          else
            collect_fragments(node, graph, oodn)
          end
        end)

      {:error, _, _} ->
        []
    end
  end

  @doc """
  Build a flat key→value map from the graph's OODN registry.
  """
  @spec build_oodn_map(Graph.t()) :: map()
  def build_oodn_map(%Graph{oodn_registry: registry}) do
    registry
    |> Map.values()
    |> Map.new(fn %{key: k, value: v} -> {k, v} end)
  end

  @doc """
  Walk a single subgraph, recursing into gateways.
  Returns tagged fragments — the caller filters by target.
  """
  @spec walk_subgraph(Subgraph.t(), Graph.t(), map()) :: [tagged_fragment()]
  def walk_subgraph(%Subgraph{} = sg, %Graph{} = graph, oodn) do
    case Constraint.topological_sort(sg) do
      {:ok, sorted_ids} ->
        Enum.flat_map(sorted_ids, fn node_id ->
          node = Map.get(sg.nodes, node_id)
          collect_fragments(node, graph, oodn)
        end)

      {:error, _, _} ->
        []
    end
  end

  defp collect_fragments(%{type: :leaf, content: content, target: target}, _graph, oodn)
       when is_binary(content) and content != "" do
    [{target, interpolate(String.trim(content), oodn)}]
  end

  defp collect_fragments(%{type: :gateway, subgraph_id: sg_id, machine: machine}, graph, oodn)
       when is_binary(sg_id) and is_map(machine) do
    # Machine gateway — override OODNs with machine-specific values.
    machine_oodn =
      oodn
      |> Map.put("hostname", Map.get(machine, :hostname, Map.get(oodn, "hostname", "nixos")))
      |> Map.put(
        "system_arch",
        Map.get(machine, :system, Map.get(oodn, "system_arch", "aarch64-linux"))
      )
      |> Map.put(
        "state_version",
        Map.get(machine, :state_version, Map.get(oodn, "state_version", "24.11"))
      )
      |> Map.put("username", Map.get(machine, :username, Map.get(oodn, "username", "user")))

    case Graph.get_subgraph(graph, sg_id) do
      nil -> []
      child_sg -> walk_subgraph(child_sg, graph, machine_oodn)
    end
  end

  defp collect_fragments(%{type: :gateway, subgraph_id: sg_id}, graph, oodn)
       when is_binary(sg_id) do
    case Graph.get_subgraph(graph, sg_id) do
      nil -> []
      child_sg -> walk_subgraph(child_sg, graph, oodn)
    end
  end

  defp collect_fragments(_node, _graph, _oodn), do: []

  # Filter tagged fragments by the target machine type. Keeps fragments
  # tagged `:all` or exactly matching the machine type; drops the rest.
  @spec filter_by_target([tagged_fragment()], :nixos | :home_manager) :: [String.t()]
  defp filter_by_target(tagged, machine_type) do
    Enum.flat_map(tagged, fn
      {:all, frag} -> [frag]
      {^machine_type, frag} -> [frag]
      _ -> []
    end)
  end

  @doc """
  Interpolate `${key}` placeholders in content with OODN values.
  Unknown keys are left as-is.
  """
  @spec interpolate(String.t(), map()) :: String.t()
  def interpolate(content, oodn) do
    Regex.replace(~r/\$\{(\w+)\}/, content, fn _match, key ->
      Map.get(oodn, key, "${#{key}}")
    end)
  end

  @doc """
  Wrap fragments in a NixOS module skeleton.
  Skeleton values are also driven by OODNs where available.
  """
  @spec finalize(list(String.t()), map()) :: String.t()
  def finalize(fragments, oodn) do
    keymap = Map.get(oodn, "keymap", "us")
    state_version = Map.get(oodn, "state_version", "24.11")

    body =
      fragments
      |> Enum.map(fn frag ->
        frag
        |> String.split("\n")
        |> Enum.map(&("  " <> &1))
        |> Enum.join("\n")
      end)
      |> Enum.join("\n\n")

    output = """
    # Generated by Tomato - Hierarchical DAG Engine
    # Do not edit manually

    { config, pkgs, lib, ... }:
    {
      imports = [ ./hardware-configuration.nix ];

      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      console.keyMap = "#{keymap}";

      # Tomato deploy requires SSH — do not remove
      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin = "yes";
          PasswordAuthentication = true;
        };
      };

      networking.useDHCP = lib.mkDefault true;

      system.stateVersion = "#{state_version}";

    #{body}
    }
    """

    String.trim(output)
  end
end
