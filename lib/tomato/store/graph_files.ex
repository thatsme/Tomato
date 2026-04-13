defmodule Tomato.Store.GraphFiles do
  @moduledoc """
  Filesystem operations for graph JSON files. Pure I/O — the functions
  here do not manipulate Store GenServer state directly; they return
  results that the caller merges back into its own `%State{}`.
  """

  alias Tomato.Graph
  alias Tomato.Store.Persistence

  @doc """
  List all saved graphs in `graphs_dir` with their filename + display
  name.
  """
  @spec list(String.t()) :: [%{filename: String.t(), name: String.t()}]
  def list(graphs_dir) do
    graphs_dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.sort()
    |> Enum.map(fn filename ->
      path = Path.join(graphs_dir, filename)
      %{filename: filename, name: Persistence.peek_graph_name(path)}
    end)
  end

  @doc """
  Load a graph from a file under `graphs_dir`.
  """
  @spec load(String.t(), String.t()) ::
          {:ok, Graph.t(), String.t()} | {:error, :not_found}
  def load(graphs_dir, filename) do
    path = Path.join(graphs_dir, filename)

    if File.exists?(path) do
      graph = path |> File.read!() |> Jason.decode!() |> Persistence.decode_graph()
      {:ok, graph, path}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Create a new empty graph named `name` and persist it to disk.
  """
  @spec new(String.t(), String.t()) ::
          {:ok, Graph.t(), String.t(), String.t()}
  def new(graphs_dir, name) do
    graph = Graph.new(name)
    filename = slugify(name) <> ".json"
    path = Path.join(graphs_dir, filename)
    File.write!(path, Persistence.encode(graph))
    {:ok, graph, path, filename}
  end

  @doc """
  Save an existing graph under a new name. Updates the graph's `:name`
  and `:updated_at` before writing.
  """
  @spec save_as(Graph.t(), String.t(), String.t()) ::
          {:ok, Graph.t(), String.t(), String.t()}
  def save_as(%Graph{} = graph, graphs_dir, name) do
    graph = %{graph | name: name, updated_at: DateTime.to_iso8601(DateTime.utc_now())}
    filename = slugify(name) <> ".json"
    path = Path.join(graphs_dir, filename)
    File.write!(path, Persistence.encode(graph))
    {:ok, graph, path, filename}
  end

  @doc """
  Delete a graph file. Returns `{:error, :not_found}` if it was missing.
  """
  @spec delete(String.t(), String.t()) :: :ok | {:error, :not_found}
  def delete(graphs_dir, filename) do
    path = Path.join(graphs_dir, filename)

    if File.exists?(path) do
      File.rm!(path)
      :ok
    else
      {:error, :not_found}
    end
  end

  @doc """
  Load the lexicographically first saved graph in `graphs_dir`, or
  create a default one if the directory has no .json files.
  """
  @spec load_latest_or_create(String.t()) :: {Graph.t(), String.t()}
  def load_latest_or_create(graphs_dir) do
    case graphs_dir |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".json")) |> Enum.sort() do
      [] ->
        graph = Graph.new("default")
        path = Path.join(graphs_dir, "default.json")
        File.write!(path, Persistence.encode(graph))
        {graph, path}

      [first | _] ->
        path = Path.join(graphs_dir, first)
        graph = path |> File.read!() |> Jason.decode!() |> Persistence.decode_graph()
        {graph, path}
    end
  end

  @doc """
  Slugify a graph name for use as a filename stem. Lowercased, with
  runs of non-alphanumerics collapsed to single `-` and trimmed.
  """
  @spec slugify(String.t()) :: String.t()
  def slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
