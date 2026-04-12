defmodule Tomato.Store.Persistence do
  @moduledoc """
  JSON serialization for Tomato graphs and the on-disk flush path.

  Encoding is delegated to `Jason.encode!/2` (the Graph/Subgraph/Node
  structs derive `Jason.Encoder`). Decoding walks the untyped JSON map
  returned by `Jason.decode!/1` and rebuilds each struct.
  """

  alias Tomato.{Edge, Graph, Node, Subgraph}

  @doc """
  Encode a graph as pretty-printed JSON.
  """
  @spec encode(Graph.t()) :: String.t()
  def encode(%Graph{} = graph), do: Jason.encode!(graph, pretty: true)

  @doc """
  Write the graph held in the state to disk at its `:file_path`. No-op
  when `file_path` is `nil`.
  """
  @spec flush_to_disk(map()) :: :ok
  def flush_to_disk(%{file_path: nil}), do: :ok

  def flush_to_disk(%{graph: graph, file_path: path}) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, encode(graph))
  end

  @doc """
  Peek at a graph file's display name without decoding the full graph.
  Falls back to the filename stem if the file is missing or malformed.
  """
  @spec peek_graph_name(String.t()) :: String.t()
  def peek_graph_name(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{"name" => name}} -> name
          _ -> Path.basename(path, ".json")
        end

      _ ->
        Path.basename(path, ".json")
    end
  end

  @doc """
  Decode a `Jason.decode!/1` result into a `%Graph{}` struct.
  """
  @spec decode_graph(map()) :: Graph.t()
  def decode_graph(json_map) when is_map(json_map) do
    %Graph{
      id: json_map["id"],
      name: json_map["name"] || "untitled",
      version: json_map["version"] || "0.2.0",
      created_at: json_map["created_at"],
      updated_at: json_map["updated_at"],
      root_subgraph_id: json_map["root_subgraph_id"],
      subgraphs: decode_subgraphs(json_map["subgraphs"] || %{}),
      oodn_registry: decode_oodn(json_map["oodn_registry"] || %{}),
      oodn_position: decode_position(json_map["oodn_position"]),
      backend: decode_backend(json_map["backend"])
    }
  end

  defp decode_subgraphs(map) do
    Map.new(map, fn {id, sg_map} ->
      {id,
       %Subgraph{
         id: sg_map["id"],
         name: sg_map["name"],
         floor: sg_map["floor"] || 0,
         nodes: decode_nodes(sg_map["nodes"] || %{}),
         edges: decode_edges(sg_map["edges"] || %{})
       }}
    end)
  end

  defp decode_nodes(map) do
    Map.new(map, fn {nid, n} ->
      {nid,
       %Node{
         id: n["id"],
         name: n["name"],
         type: decode_node_type(n["type"]),
         target: decode_target(n["target"]),
         template_fn: n["template_fn"],
         subgraph_id: n["subgraph_id"],
         content: n["content"],
         machine: decode_machine(n["machine"]),
         inputs: n["inputs"] || [],
         outputs: n["outputs"] || [],
         position: %{
           x: get_in(n, ["position", "x"]) || 0,
           y: get_in(n, ["position", "y"]) || 0
         }
       }}
    end)
  end

  defp decode_target("home_manager"), do: :home_manager
  defp decode_target("all"), do: :all
  defp decode_target(_), do: :nixos

  defp decode_edges(map) do
    Map.new(map, fn {eid, e} ->
      {eid, %Edge{id: e["id"], from: e["from"], to: e["to"]}}
    end)
  end

  defp decode_oodn(map) do
    Map.new(map, fn {id, o} ->
      {id, %Tomato.OODN{id: id, key: o["key"], value: o["value"]}}
    end)
  end

  defp decode_machine(nil), do: nil

  defp decode_machine(%{"hostname" => h} = m) do
    %{
      hostname: h,
      system: m["system"] || "aarch64-linux",
      state_version: m["state_version"] || "24.11",
      type: decode_machine_type(m["type"]),
      username: m["username"] || "user"
    }
  end

  defp decode_machine(_), do: nil

  defp decode_machine_type("home_manager"), do: :home_manager
  defp decode_machine_type(_), do: :nixos

  defp decode_backend("flake"), do: :flake
  defp decode_backend(_), do: :traditional

  defp decode_position(nil), do: %{x: 600, y: 80}
  defp decode_position(%{"x" => x, "y" => y}), do: %{x: x, y: y}
  defp decode_position(_), do: %{x: 600, y: 80}

  defp decode_node_type("input"), do: :input
  defp decode_node_type("output"), do: :output
  defp decode_node_type("leaf"), do: :leaf
  defp decode_node_type("gateway"), do: :gateway
end
