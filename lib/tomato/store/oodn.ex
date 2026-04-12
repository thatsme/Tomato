defmodule Tomato.Store.OODN do
  @moduledoc """
  Pure OODN (Out-Of-DAG Node) mutations. `put/3`, `remove/2`, `update/3`
  and `move/2` operate on a `%Graph{}` and return the updated graph (or
  `{:ok, graph}` / `{:error, :not_found}` when appropriate).

  `move/2` is special — it's used for visual drag updates and does not
  bump `updated_at` or warrant a history entry.
  """

  alias Tomato.Graph

  @doc """
  Add or replace an OODN entry. Returns the new graph and the freshly
  created `%OODN{}` struct.
  """
  @spec put(Graph.t(), String.t(), any()) :: {Graph.t(), Tomato.OODN.t()}
  def put(%Graph{} = graph, key, value) do
    oodn = Tomato.OODN.new(key, value)

    new_graph = %{
      graph
      | oodn_registry: Map.put(graph.oodn_registry, oodn.id, oodn),
        updated_at: now()
    }

    {new_graph, oodn}
  end

  @doc """
  Remove an OODN entry by id.
  """
  @spec remove(Graph.t(), String.t()) :: Graph.t()
  def remove(%Graph{} = graph, oodn_id) do
    %{
      graph
      | oodn_registry: Map.delete(graph.oodn_registry, oodn_id),
        updated_at: now()
    }
  end

  @doc """
  Update an OODN value by id. Returns `{:error, :not_found}` if the id
  does not exist in the registry.
  """
  @spec update(Graph.t(), String.t(), any()) :: {:ok, Graph.t()} | {:error, :not_found}
  def update(%Graph{} = graph, oodn_id, value) do
    case Map.get(graph.oodn_registry, oodn_id) do
      nil ->
        {:error, :not_found}

      oodn ->
        updated = %{oodn | value: value}

        {:ok,
         %{
           graph
           | oodn_registry: Map.put(graph.oodn_registry, oodn_id, updated),
             updated_at: now()
         }}
    end
  end

  @doc """
  Update the visual OODN node position. Does not touch `updated_at` and
  is excluded from undo history by the caller.
  """
  @spec move(Graph.t(), map()) :: Graph.t()
  def move(%Graph{} = graph, position) do
    %{graph | oodn_position: position}
  end

  defp now, do: DateTime.to_iso8601(DateTime.utc_now())
end
