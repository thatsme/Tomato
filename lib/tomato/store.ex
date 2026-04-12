defmodule Tomato.Store do
  @moduledoc """
  GenServer managing all graph state. Holds graph in-memory,
  validates constraints on mutations, and persists to JSON.
  Supports multiple graph files in a graphs directory.
  """

  use GenServer

  alias Tomato.{Graph, Subgraph, Node, Edge, Constraint}

  @flush_delay 200

  @type server :: GenServer.server()

  # --- Client API ---

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = opts[:name] || __MODULE__
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec get_graph(server()) :: Graph.t()
  def get_graph(server \\ __MODULE__) do
    GenServer.call(server, :get_graph)
  end

  @spec get_subgraph(server(), String.t()) :: Subgraph.t() | nil
  def get_subgraph(server \\ __MODULE__, subgraph_id) do
    GenServer.call(server, {:get_subgraph, subgraph_id})
  end

  @spec add_node(server(), String.t(), keyword()) ::
          {:ok, Node.t()} | {:error, atom(), String.t()}
  def add_node(server \\ __MODULE__, subgraph_id, node_attrs) do
    GenServer.call(server, {:add_node, subgraph_id, node_attrs})
  end

  @spec remove_node(server(), String.t(), String.t()) :: :ok | {:error, atom(), String.t()}
  def remove_node(server \\ __MODULE__, subgraph_id, node_id) do
    GenServer.call(server, {:remove_node, subgraph_id, node_id})
  end

  @spec update_node(server(), String.t(), String.t(), keyword()) ::
          :ok | {:error, atom(), String.t()}
  def update_node(server \\ __MODULE__, subgraph_id, node_id, updates) do
    GenServer.call(server, {:update_node, subgraph_id, node_id, updates})
  end

  @spec add_edge(server(), String.t(), String.t(), String.t()) ::
          {:ok, Edge.t()} | {:error, atom(), String.t()}
  def add_edge(server \\ __MODULE__, subgraph_id, from_id, to_id) do
    GenServer.call(server, {:add_edge, subgraph_id, from_id, to_id})
  end

  @spec remove_edge(server(), String.t(), String.t()) :: :ok | {:error, atom(), String.t()}
  def remove_edge(server \\ __MODULE__, subgraph_id, edge_id) do
    GenServer.call(server, {:remove_edge, subgraph_id, edge_id})
  end

  @spec add_gateway(server(), String.t(), keyword()) ::
          {:ok, Node.t(), Subgraph.t()} | {:error, atom(), String.t()}
  def add_gateway(server \\ __MODULE__, subgraph_id, gateway_attrs) do
    GenServer.call(server, {:add_gateway, subgraph_id, gateway_attrs})
  end

  @doc "List all saved graph files."
  @spec list_graphs(server()) :: list(map())
  def list_graphs(server \\ __MODULE__) do
    GenServer.call(server, :list_graphs)
  end

  @doc "Load a graph from a file in the graphs directory."
  @spec load_graph(server(), String.t()) :: {:ok, Graph.t()} | {:error, atom()}
  def load_graph(server \\ __MODULE__, filename) do
    GenServer.call(server, {:load_graph, filename})
  end

  @doc "Create a new empty graph and save it immediately."
  @spec new_graph(server(), String.t()) :: {:ok, Graph.t(), String.t()}
  def new_graph(server \\ __MODULE__, name) do
    GenServer.call(server, {:new_graph, name})
  end

  @doc "Save current graph under a new filename."
  @spec save_as(server(), String.t()) :: {:ok, String.t()}
  def save_as(server \\ __MODULE__, name) do
    GenServer.call(server, {:save_as, name})
  end

  @doc "Delete a graph file."
  @spec delete_graph(server(), String.t()) :: :ok | {:error, atom()}
  def delete_graph(server \\ __MODULE__, filename) do
    GenServer.call(server, {:delete_graph, filename})
  end

  @doc "Add or update an OODN entry."
  @spec put_oodn(server(), String.t(), any()) :: {:ok, Tomato.OODN.t()}
  def put_oodn(server \\ __MODULE__, key, value) do
    GenServer.call(server, {:put_oodn, key, value})
  end

  @doc "Remove an OODN entry."
  @spec remove_oodn(server(), String.t()) :: :ok
  def remove_oodn(server \\ __MODULE__, oodn_id) do
    GenServer.call(server, {:remove_oodn, oodn_id})
  end

  @doc "Update an OODN value by id."
  @spec update_oodn(server(), String.t(), any()) :: :ok | {:error, atom()}
  def update_oodn(server \\ __MODULE__, oodn_id, value) do
    GenServer.call(server, {:update_oodn, oodn_id, value})
  end

  @doc "Move the OODN node position on canvas."
  @spec move_oodn(server(), map()) :: :ok
  def move_oodn(server \\ __MODULE__, position) do
    GenServer.call(server, {:move_oodn, position})
  end

  @doc "Add a machine (gateway with machine metadata and child subgraph)."
  @spec add_machine(server(), String.t(), keyword()) ::
          {:ok, Node.t(), Subgraph.t()} | {:error, atom(), String.t()}
  def add_machine(server \\ __MODULE__, subgraph_id, attrs) do
    GenServer.call(server, {:add_machine, subgraph_id, attrs})
  end

  @doc "Set the graph backend (:traditional or :flake)."
  @spec set_backend(server(), Graph.backend()) :: :ok
  def set_backend(server \\ __MODULE__, backend) when backend in [:traditional, :flake] do
    GenServer.call(server, {:set_backend, backend})
  end

  @doc "Returns the current file name."
  @spec current_file(server()) :: String.t() | nil
  def current_file(server \\ __MODULE__) do
    GenServer.call(server, :current_file)
  end

  # --- Server ---

  @impl true
  def init(opts) do
    graphs_dir = opts[:graphs_dir] || "priv/graphs"
    File.mkdir_p!(graphs_dir)

    # Try to load most recent graph, or create default
    {graph, file_path} = load_latest_or_create(graphs_dir)

    {:ok, %{graph: graph, file_path: file_path, graphs_dir: graphs_dir, flush_ref: nil},
     {:continue, :maybe_seed}}
  end

  @impl true
  def handle_continue(:maybe_seed, state) do
    root = Graph.root_subgraph(state.graph)

    if map_size(root.nodes) <= 2 do
      spawn(fn ->
        Process.sleep(100)
        Tomato.Demo.seed()
      end)
    end

    {:noreply, state}
  end

  @impl true
  def handle_call(:get_graph, _from, state) do
    {:reply, state.graph, state}
  end

  def handle_call(:current_file, _from, state) do
    filename = state.file_path && Path.basename(state.file_path)
    {:reply, filename, state}
  end

  def handle_call(:list_graphs, _from, state) do
    graphs =
      state.graphs_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.sort()
      |> Enum.map(fn filename ->
        path = Path.join(state.graphs_dir, filename)
        name = peek_graph_name(path)
        %{filename: filename, name: name}
      end)

    {:reply, graphs, state}
  end

  def handle_call({:load_graph, filename}, _from, state) do
    path = Path.join(state.graphs_dir, filename)

    if File.exists?(path) do
      graph = path |> File.read!() |> Jason.decode!() |> decode_graph()
      state = %{state | graph: graph, file_path: path, flush_ref: nil}
      broadcast(graph)
      {:reply, {:ok, graph}, state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:new_graph, name}, _from, state) do
    graph = Graph.new(name)
    filename = slugify(name) <> ".json"
    path = Path.join(state.graphs_dir, filename)

    # Write immediately
    json = Jason.encode!(graph, pretty: true)
    File.write!(path, json)

    state = %{state | graph: graph, file_path: path, flush_ref: nil}
    broadcast(graph)
    {:reply, {:ok, graph, filename}, state}
  end

  def handle_call({:save_as, name}, _from, state) do
    graph = %{state.graph | name: name, updated_at: DateTime.to_iso8601(DateTime.utc_now())}
    filename = slugify(name) <> ".json"
    path = Path.join(state.graphs_dir, filename)

    json = Jason.encode!(graph, pretty: true)
    File.write!(path, json)

    state = %{state | graph: graph, file_path: path}
    broadcast(graph)
    {:reply, {:ok, filename}, state}
  end

  def handle_call({:delete_graph, filename}, _from, state) do
    path = Path.join(state.graphs_dir, filename)

    if File.exists?(path) do
      File.rm!(path)
      {:reply, :ok, state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:get_subgraph, subgraph_id}, _from, state) do
    {:reply, Graph.get_subgraph(state.graph, subgraph_id), state}
  end

  def handle_call({:add_node, subgraph_id, node_attrs}, _from, state) do
    with {:ok, sg} <- fetch_subgraph(state.graph, subgraph_id) do
      node = Node.new(node_attrs)
      new_sg = Subgraph.add_node(sg, node)
      graph = Graph.put_subgraph(state.graph, new_sg)
      state = schedule_flush(%{state | graph: graph})
      broadcast(graph)
      {:reply, {:ok, node}, state}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:remove_node, subgraph_id, node_id}, _from, state) do
    with {:ok, sg} <- fetch_subgraph(state.graph, subgraph_id),
         {:ok, node} <- fetch_node(sg, node_id),
         :ok <- validate_deletable(node) do
      new_sg = Subgraph.remove_node(sg, node_id)
      graph = Graph.put_subgraph(state.graph, new_sg)
      state = schedule_flush(%{state | graph: graph})
      broadcast(graph)
      {:reply, :ok, state}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:update_node, subgraph_id, node_id, updates}, _from, state) do
    with {:ok, sg} <- fetch_subgraph(state.graph, subgraph_id) do
      new_sg = Subgraph.update_node(sg, node_id, updates)
      graph = Graph.put_subgraph(state.graph, new_sg)
      state = schedule_flush(%{state | graph: graph})
      broadcast(graph)
      {:reply, :ok, state}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:add_edge, subgraph_id, from_id, to_id}, _from, state) do
    with {:ok, sg} <- fetch_subgraph(state.graph, subgraph_id) do
      edge = Edge.new(from_id, to_id)
      new_sg = Subgraph.add_edge(sg, edge)

      case Constraint.topological_sort(new_sg) do
        {:ok, _} ->
          graph = Graph.put_subgraph(state.graph, new_sg)
          state = schedule_flush(%{state | graph: graph})
          broadcast(graph)
          {:reply, {:ok, edge}, state}

        {:error, _, _} = error ->
          {:reply, error, state}
      end
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:remove_edge, subgraph_id, edge_id}, _from, state) do
    with {:ok, sg} <- fetch_subgraph(state.graph, subgraph_id) do
      new_sg = Subgraph.remove_edge(sg, edge_id)
      graph = Graph.put_subgraph(state.graph, new_sg)
      state = schedule_flush(%{state | graph: graph})
      broadcast(graph)
      {:reply, :ok, state}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:add_gateway, subgraph_id, gateway_attrs}, _from, state) do
    with {:ok, sg} <- fetch_subgraph(state.graph, subgraph_id) do
      child_sg = Subgraph.new(name: gateway_attrs[:name] || "Sub", floor: sg.floor + 1)

      gateway_node =
        Node.new(
          type: :gateway,
          name: gateway_attrs[:name] || "Gateway",
          subgraph_id: child_sg.id,
          position: gateway_attrs[:position] || %{x: 0, y: 0}
        )

      new_sg = Subgraph.add_node(sg, gateway_node)

      graph =
        state.graph
        |> Graph.put_subgraph(new_sg)
        |> Graph.put_subgraph(child_sg)

      state = schedule_flush(%{state | graph: graph})
      broadcast(graph)
      {:reply, {:ok, gateway_node, child_sg}, state}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:put_oodn, key, value}, _from, state) do
    oodn = Tomato.OODN.new(key, value)

    graph = %{
      state.graph
      | oodn_registry: Map.put(state.graph.oodn_registry, oodn.id, oodn),
        updated_at: DateTime.to_iso8601(DateTime.utc_now())
    }

    state = schedule_flush(%{state | graph: graph})
    broadcast(graph)
    {:reply, {:ok, oodn}, state}
  end

  def handle_call({:remove_oodn, oodn_id}, _from, state) do
    graph = %{
      state.graph
      | oodn_registry: Map.delete(state.graph.oodn_registry, oodn_id),
        updated_at: DateTime.to_iso8601(DateTime.utc_now())
    }

    state = schedule_flush(%{state | graph: graph})
    broadcast(graph)
    {:reply, :ok, state}
  end

  def handle_call({:update_oodn, oodn_id, value}, _from, state) do
    case Map.get(state.graph.oodn_registry, oodn_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      oodn ->
        updated = %{oodn | value: value}

        graph = %{
          state.graph
          | oodn_registry: Map.put(state.graph.oodn_registry, oodn_id, updated),
            updated_at: DateTime.to_iso8601(DateTime.utc_now())
        }

        state = schedule_flush(%{state | graph: graph})
        broadcast(graph)
        {:reply, :ok, state}
    end
  end

  def handle_call({:add_machine, subgraph_id, attrs}, _from, state) do
    with {:ok, sg} <- fetch_subgraph(state.graph, subgraph_id) do
      hostname = attrs[:hostname] || "nixos"
      child_sg = Subgraph.new(name: hostname, floor: sg.floor + 1)

      machine_meta = %{
        hostname: hostname,
        system: attrs[:system] || "aarch64-linux",
        state_version: attrs[:state_version] || "24.11",
        type: attrs[:type] || :nixos,
        username: attrs[:username] || "user"
      }

      machine_node =
        Node.new(
          type: :gateway,
          name: hostname,
          subgraph_id: child_sg.id,
          machine: machine_meta,
          position: attrs[:position] || %{x: 0, y: 0}
        )

      new_sg = Subgraph.add_node(sg, machine_node)

      graph =
        state.graph
        |> Graph.put_subgraph(new_sg)
        |> Graph.put_subgraph(child_sg)

      state = schedule_flush(%{state | graph: graph})
      broadcast(graph)
      {:reply, {:ok, machine_node, child_sg}, state}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:set_backend, backend}, _from, state) do
    graph = %{state.graph | backend: backend}
    state = schedule_flush(%{state | graph: graph})
    broadcast(graph)
    {:reply, :ok, state}
  end

  def handle_call({:move_oodn, position}, _from, state) do
    graph = %{state.graph | oodn_position: position}
    state = schedule_flush(%{state | graph: graph})
    broadcast(graph)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:flush, state) do
    flush_to_disk(state)
    {:noreply, %{state | flush_ref: nil}}
  end

  # --- Private ---

  defp fetch_subgraph(graph, subgraph_id) do
    case Graph.get_subgraph(graph, subgraph_id) do
      nil -> {:error, :subgraph_not_found, "Subgraph #{subgraph_id} not found"}
      sg -> {:ok, sg}
    end
  end

  defp fetch_node(sg, node_id) do
    case Map.get(sg.nodes, node_id) do
      nil -> {:error, :node_not_found, "Node #{node_id} not found"}
      node -> {:ok, node}
    end
  end

  defp validate_deletable(%Node{type: type}) when type in [:input, :output] do
    {:error, :undeletable, "Cannot delete #{type} node"}
  end

  defp validate_deletable(_node), do: :ok

  defp schedule_flush(state) do
    if state.flush_ref, do: Process.cancel_timer(state.flush_ref)
    ref = Process.send_after(self(), :flush, @flush_delay)
    %{state | flush_ref: ref}
  end

  defp flush_to_disk(%{file_path: nil}), do: :ok

  defp flush_to_disk(%{graph: graph, file_path: path}) do
    path |> Path.dirname() |> File.mkdir_p!()
    json = Jason.encode!(graph, pretty: true)
    File.write!(path, json)
  end

  defp load_latest_or_create(graphs_dir) do
    case File.ls!(graphs_dir) |> Enum.filter(&String.ends_with?(&1, ".json")) |> Enum.sort() do
      [] ->
        graph = Graph.new("default")
        path = Path.join(graphs_dir, "default.json")
        json = Jason.encode!(graph, pretty: true)
        File.write!(path, json)
        {graph, path}

      [first | _] ->
        path = Path.join(graphs_dir, first)
        graph = path |> File.read!() |> Jason.decode!() |> decode_graph()
        {graph, path}
    end
  end

  defp peek_graph_name(path) do
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

  defp decode_graph(json_map) when is_map(json_map) do
    subgraphs =
      (json_map["subgraphs"] || %{})
      |> Enum.map(fn {id, sg_map} ->
        nodes =
          (sg_map["nodes"] || %{})
          |> Enum.map(fn {nid, n} ->
            {nid,
             %Node{
               id: n["id"],
               name: n["name"],
               type: decode_node_type(n["type"]),
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
          |> Map.new()

        edges =
          (sg_map["edges"] || %{})
          |> Enum.map(fn {eid, e} ->
            {eid, %Edge{id: e["id"], from: e["from"], to: e["to"]}}
          end)
          |> Map.new()

        {id,
         %Subgraph{
           id: sg_map["id"],
           name: sg_map["name"],
           floor: sg_map["floor"] || 0,
           nodes: nodes,
           edges: edges
         }}
      end)
      |> Map.new()

    oodn =
      (json_map["oodn_registry"] || %{})
      |> Enum.map(fn {id, o} ->
        {id, %Tomato.OODN{id: id, key: o["key"], value: o["value"]}}
      end)
      |> Map.new()

    %Graph{
      id: json_map["id"],
      name: json_map["name"] || "untitled",
      version: json_map["version"] || "0.1.0",
      created_at: json_map["created_at"],
      updated_at: json_map["updated_at"],
      root_subgraph_id: json_map["root_subgraph_id"],
      subgraphs: subgraphs,
      oodn_registry: oodn,
      oodn_position: decode_position(json_map["oodn_position"]),
      backend: decode_backend(json_map["backend"])
    }
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

  @spec slugify(String.t()) :: String.t()
  def slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp broadcast(graph) do
    Phoenix.PubSub.broadcast(Tomato.PubSub, "graph:updates", {:graph_updated, graph})
  end
end
