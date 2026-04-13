defmodule Tomato.Store.State do
  @moduledoc """
  State struct for the `Tomato.Store` GenServer and pure history
  operations (push/undo/redo).
  """

  alias Tomato.Graph

  @history_limit 50

  @type t :: %__MODULE__{
          graph: Graph.t() | nil,
          file_path: String.t() | nil,
          graphs_dir: String.t() | nil,
          flush_ref: reference() | nil,
          undo_stack: [Graph.t()],
          redo_stack: [Graph.t()],
          name: atom() | nil
        }

  defstruct graph: nil,
            file_path: nil,
            graphs_dir: nil,
            flush_ref: nil,
            undo_stack: [],
            redo_stack: [],
            name: nil

  @doc """
  Replace the graph held in state without touching history.
  """
  @spec put_graph(t(), Graph.t()) :: t()
  def put_graph(%__MODULE__{} = state, %Graph{} = graph),
    do: %{state | graph: graph}

  @doc """
  Push the current graph onto the undo stack (bounded to #{@history_limit}
  entries) and clear the redo stack.
  """
  @spec push_history(t()) :: t()
  def push_history(%__MODULE__{} = state) do
    %{
      state
      | undo_stack: Enum.take([state.graph | state.undo_stack], @history_limit),
        redo_stack: []
    }
  end

  @doc """
  Restore the previous graph from the undo stack, moving the current one
  onto the redo stack.
  """
  @spec undo(t()) :: {:ok, t()} | {:error, :no_history}
  def undo(%__MODULE__{undo_stack: []}), do: {:error, :no_history}

  def undo(%__MODULE__{undo_stack: [prev | rest]} = state) do
    {:ok,
     %{
       state
       | graph: prev,
         undo_stack: rest,
         redo_stack: [state.graph | state.redo_stack]
     }}
  end

  @doc """
  Re-apply the most recently undone graph, moving the current one back
  onto the undo stack.
  """
  @spec redo(t()) :: {:ok, t()} | {:error, :no_redo}
  def redo(%__MODULE__{redo_stack: []}), do: {:error, :no_redo}

  def redo(%__MODULE__{redo_stack: [next | rest]} = state) do
    {:ok,
     %{
       state
       | graph: next,
         redo_stack: rest,
         undo_stack: [state.graph | state.undo_stack]
     }}
  end

  @doc """
  Return `{undo_count, redo_count}`.
  """
  @spec history_status(t()) :: {non_neg_integer(), non_neg_integer()}
  def history_status(%__MODULE__{undo_stack: u, redo_stack: r}),
    do: {length(u), length(r)}
end
