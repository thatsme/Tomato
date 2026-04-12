defmodule Tomato.Store do
  @moduledoc """
  GenServer managing all graph state. Holds the graph in-memory,
  validates constraints on mutations via `Tomato.Store.Mutations`, and
  persists to JSON through `Tomato.Store.Persistence`. Supports multiple
  graph files in a graphs directory.

  This module is the public client API + GenServer lifecycle. The actual
  mutation and persistence logic lives in the submodules under
  `Tomato.Store.*`, which can be tested without a running GenServer.
  """

  use GenServer

  alias Tomato.{Edge, Graph, Node, Subgraph}

  alias Tomato.Store.{
    GraphFiles,
    Machine,
    Mutations,
    OODN,
    Persistence,
    State
  }

  @flush_delay 200

  @type server :: GenServer.server()

  # --- Client API ---

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = opts[:name] || __MODULE__
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec get_graph(server()) :: Graph.t()
  def get_graph(server \\ __MODULE__),
    do: GenServer.call(server, :get_graph)

  @spec get_subgraph(server(), String.t()) :: Subgraph.t() | nil
  def get_subgraph(server \\ __MODULE__, subgraph_id),
    do: GenServer.call(server, {:get_subgraph, subgraph_id})

  @spec add_node(server(), String.t(), keyword()) ::
          {:ok, Node.t()} | {:error, atom(), String.t()}
  def add_node(server \\ __MODULE__, subgraph_id, node_attrs),
    do: GenServer.call(server, {:add_node, subgraph_id, node_attrs})

  @spec remove_node(server(), String.t(), String.t()) ::
          :ok | {:error, atom(), String.t()}
  def remove_node(server \\ __MODULE__, subgraph_id, node_id),
    do: GenServer.call(server, {:remove_node, subgraph_id, node_id})

  @spec update_node(server(), String.t(), String.t(), keyword()) ::
          :ok | {:error, atom(), String.t()}
  def update_node(server \\ __MODULE__, subgraph_id, node_id, updates),
    do: GenServer.call(server, {:update_node, subgraph_id, node_id, updates})

  @spec add_edge(server(), String.t(), String.t(), String.t()) ::
          {:ok, Edge.t()} | {:error, atom(), String.t()}
  def add_edge(server \\ __MODULE__, subgraph_id, from_id, to_id),
    do: GenServer.call(server, {:add_edge, subgraph_id, from_id, to_id})

  @spec remove_edge(server(), String.t(), String.t()) ::
          :ok | {:error, atom(), String.t()}
  def remove_edge(server \\ __MODULE__, subgraph_id, edge_id),
    do: GenServer.call(server, {:remove_edge, subgraph_id, edge_id})

  @spec add_gateway(server(), String.t(), keyword()) ::
          {:ok, Node.t(), Subgraph.t()} | {:error, atom(), String.t()}
  def add_gateway(server \\ __MODULE__, subgraph_id, attrs),
    do: GenServer.call(server, {:add_gateway, subgraph_id, attrs})

  @doc "List all saved graph files."
  @spec list_graphs(server()) :: list(map())
  def list_graphs(server \\ __MODULE__),
    do: GenServer.call(server, :list_graphs)

  @doc "Load a graph from a file in the graphs directory."
  @spec load_graph(server(), String.t()) :: {:ok, Graph.t()} | {:error, atom()}
  def load_graph(server \\ __MODULE__, filename),
    do: GenServer.call(server, {:load_graph, filename})

  @doc "Create a new empty graph and save it immediately."
  @spec new_graph(server(), String.t()) :: {:ok, Graph.t(), String.t()}
  def new_graph(server \\ __MODULE__, name),
    do: GenServer.call(server, {:new_graph, name})

  @doc "Save current graph under a new filename."
  @spec save_as(server(), String.t()) :: {:ok, String.t()}
  def save_as(server \\ __MODULE__, name),
    do: GenServer.call(server, {:save_as, name})

  @doc "Delete a graph file."
  @spec delete_graph(server(), String.t()) :: :ok | {:error, atom()}
  def delete_graph(server \\ __MODULE__, filename),
    do: GenServer.call(server, {:delete_graph, filename})

  @doc "Add or update an OODN entry."
  @spec put_oodn(server(), String.t(), any()) :: {:ok, Tomato.OODN.t()}
  def put_oodn(server \\ __MODULE__, key, value),
    do: GenServer.call(server, {:put_oodn, key, value})

  @doc "Remove an OODN entry."
  @spec remove_oodn(server(), String.t()) :: :ok
  def remove_oodn(server \\ __MODULE__, oodn_id),
    do: GenServer.call(server, {:remove_oodn, oodn_id})

  @doc "Update an OODN value by id."
  @spec update_oodn(server(), String.t(), any()) :: :ok | {:error, atom()}
  def update_oodn(server \\ __MODULE__, oodn_id, value),
    do: GenServer.call(server, {:update_oodn, oodn_id, value})

  @doc "Move the OODN node position on canvas."
  @spec move_oodn(server(), map()) :: :ok
  def move_oodn(server \\ __MODULE__, position),
    do: GenServer.call(server, {:move_oodn, position})

  @doc "Add a machine (gateway with machine metadata and child subgraph)."
  @spec add_machine(server(), String.t(), keyword()) ::
          {:ok, Node.t(), Subgraph.t()} | {:error, atom(), String.t()}
  def add_machine(server \\ __MODULE__, subgraph_id, attrs),
    do: GenServer.call(server, {:add_machine, subgraph_id, attrs})

  @doc "Undo the last mutation."
  @spec undo(server()) :: :ok | {:error, :no_history}
  def undo(server \\ __MODULE__), do: GenServer.call(server, :undo)

  @doc "Redo the last undone mutation."
  @spec redo(server()) :: :ok | {:error, :no_redo}
  def redo(server \\ __MODULE__), do: GenServer.call(server, :redo)

  @doc "Returns `{undo_count, redo_count}`."
  @spec history_status(server()) :: {non_neg_integer(), non_neg_integer()}
  def history_status(server \\ __MODULE__),
    do: GenServer.call(server, :history_status)

  @doc "Set the graph backend (`:traditional` or `:flake`)."
  @spec set_backend(server(), Graph.backend()) :: :ok
  def set_backend(server \\ __MODULE__, backend) when backend in [:traditional, :flake],
    do: GenServer.call(server, {:set_backend, backend})

  @doc "Returns the current file name."
  @spec current_file(server()) :: String.t() | nil
  def current_file(server \\ __MODULE__),
    do: GenServer.call(server, :current_file)

  @doc "Slugify a graph name for use as a filename stem."
  defdelegate slugify(name), to: GraphFiles

  # --- Server lifecycle ---

  @impl true
  def init(opts) do
    graphs_dir = opts[:graphs_dir] || "priv/graphs"
    File.mkdir_p!(graphs_dir)

    {graph, file_path} = GraphFiles.load_latest_or_create(graphs_dir)

    state = %State{graph: graph, file_path: file_path, graphs_dir: graphs_dir}
    {:ok, state, {:continue, :maybe_seed}}
  end

  @impl true
  def handle_continue(:maybe_seed, %State{} = state) do
    root = Graph.root_subgraph(state.graph)

    if map_size(root.nodes) <= 2 do
      spawn(fn ->
        Process.sleep(100)
        Tomato.Demo.seed()
        Process.sleep(400)

        multi_path = Path.join(state.graphs_dir, "multi-machine.json")

        unless File.exists?(multi_path) do
          Tomato.Demo.seed_multi()
          Process.sleep(400)
        end

        home_path = Path.join(state.graphs_dir, "home-manager.json")

        unless File.exists?(home_path) do
          Tomato.Demo.seed_home()
          Process.sleep(400)
        end

        # Switch back to default for the active session
        Tomato.Store.load_graph("default.json")
      end)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:flush, state) do
    Persistence.flush_to_disk(state)
    {:noreply, %{state | flush_ref: nil}}
  end

  # --- Query handlers ---

  @impl true
  def handle_call(:get_graph, _from, state), do: {:reply, state.graph, state}

  def handle_call(:current_file, _from, state) do
    filename = state.file_path && Path.basename(state.file_path)
    {:reply, filename, state}
  end

  def handle_call({:get_subgraph, subgraph_id}, _from, state) do
    {:reply, Graph.get_subgraph(state.graph, subgraph_id), state}
  end

  def handle_call(:list_graphs, _from, state) do
    {:reply, GraphFiles.list(state.graphs_dir), state}
  end

  def handle_call(:history_status, _from, state) do
    {:reply, State.history_status(state), state}
  end

  # --- Graph file handlers ---

  def handle_call({:load_graph, filename}, _from, state) do
    case GraphFiles.load(state.graphs_dir, filename) do
      {:ok, graph, path} ->
        new_state = %{state | graph: graph, file_path: path, flush_ref: nil}
        broadcast(graph)
        {:reply, {:ok, graph}, new_state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:new_graph, name}, _from, state) do
    {:ok, graph, path, filename} = GraphFiles.new(state.graphs_dir, name)
    new_state = %{state | graph: graph, file_path: path, flush_ref: nil}
    broadcast(graph)
    {:reply, {:ok, graph, filename}, new_state}
  end

  def handle_call({:save_as, name}, _from, state) do
    {:ok, graph, path, filename} = GraphFiles.save_as(state.graph, state.graphs_dir, name)
    new_state = %{state | graph: graph, file_path: path}
    broadcast(graph)
    {:reply, {:ok, filename}, new_state}
  end

  def handle_call({:delete_graph, filename}, _from, state) do
    {:reply, GraphFiles.delete(state.graphs_dir, filename), state}
  end

  # --- Mutation handlers ---

  def handle_call({:add_node, subgraph_id, attrs}, _from, state) do
    case Mutations.add_node(state.graph, subgraph_id, attrs) do
      {:ok, graph, node} -> {:reply, {:ok, node}, commit(state, graph)}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:remove_node, subgraph_id, node_id}, _from, state) do
    case Mutations.remove_node(state.graph, subgraph_id, node_id) do
      {:ok, graph} -> {:reply, :ok, commit(state, graph)}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:update_node, subgraph_id, node_id, updates}, _from, state) do
    case Mutations.update_node(state.graph, subgraph_id, node_id, updates) do
      {:ok, graph} -> {:reply, :ok, commit(state, graph)}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:add_edge, subgraph_id, from, to}, _from, state) do
    case Mutations.add_edge(state.graph, subgraph_id, from, to) do
      {:ok, graph, edge} -> {:reply, {:ok, edge}, commit(state, graph)}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:remove_edge, subgraph_id, edge_id}, _from, state) do
    case Mutations.remove_edge(state.graph, subgraph_id, edge_id) do
      {:ok, graph} -> {:reply, :ok, commit(state, graph)}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:add_gateway, subgraph_id, attrs}, _from, state) do
    case Mutations.add_gateway(state.graph, subgraph_id, attrs) do
      {:ok, graph, node, child_sg} ->
        {:reply, {:ok, node, child_sg}, commit(state, graph)}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:add_machine, subgraph_id, attrs}, _from, state) do
    case Machine.add(state.graph, subgraph_id, attrs) do
      {:ok, graph, node, child_sg} ->
        {:reply, {:ok, node, child_sg}, commit(state, graph)}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:set_backend, backend}, _from, state) do
    graph = Mutations.set_backend(state.graph, backend)
    {:reply, :ok, commit(state, graph)}
  end

  # --- OODN handlers ---

  def handle_call({:put_oodn, key, value}, _from, state) do
    {graph, oodn} = OODN.put(state.graph, key, value)
    {:reply, {:ok, oodn}, commit(state, graph)}
  end

  def handle_call({:remove_oodn, oodn_id}, _from, state) do
    graph = OODN.remove(state.graph, oodn_id)
    {:reply, :ok, commit(state, graph)}
  end

  def handle_call({:update_oodn, oodn_id, value}, _from, state) do
    case OODN.update(state.graph, oodn_id, value) do
      {:ok, graph} -> {:reply, :ok, commit(state, graph)}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:move_oodn, position}, _from, state) do
    # OODN position drag is purely visual — don't pollute undo history
    graph = OODN.move(state.graph, position)
    new_state = schedule_flush(%{state | graph: graph})
    broadcast(graph)
    {:reply, :ok, new_state}
  end

  # --- History handlers ---

  def handle_call(:undo, _from, state) do
    case State.undo(state) do
      {:ok, new_state} ->
        new_state = schedule_flush(new_state)
        broadcast(new_state.graph)
        {:reply, :ok, new_state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call(:redo, _from, state) do
    case State.redo(state) do
      {:ok, new_state} ->
        new_state = schedule_flush(new_state)
        broadcast(new_state.graph)
        {:reply, :ok, new_state}

      error ->
        {:reply, error, state}
    end
  end

  # --- Private ---

  # Commit a mutated graph: push history, schedule flush, broadcast.
  defp commit(%State{} = state, %Graph{} = graph) do
    new_state =
      state
      |> State.push_history()
      |> State.put_graph(graph)
      |> schedule_flush()

    broadcast(graph)
    new_state
  end

  defp schedule_flush(%State{} = state) do
    if state.flush_ref, do: Process.cancel_timer(state.flush_ref)
    ref = Process.send_after(self(), :flush, @flush_delay)
    %{state | flush_ref: ref}
  end

  defp broadcast(%Graph{} = graph) do
    Phoenix.PubSub.broadcast(Tomato.PubSub, "graph:updates", {:graph_updated, graph})
  end
end
