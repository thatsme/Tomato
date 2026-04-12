defmodule Tomato.Graph do
  @moduledoc """
  Top-level graph container. Holds all subgraphs, OODN registry,
  and metadata for a single Tomato project.
  """

  alias Tomato.{Subgraph, OODN}

  @type backend :: :traditional | :flake
  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          version: String.t(),
          created_at: String.t(),
          updated_at: String.t(),
          oodn_registry: %{String.t() => OODN.t()},
          subgraphs: %{String.t() => Subgraph.t()},
          root_subgraph_id: String.t(),
          backend: backend()
        }

  @derive Jason.Encoder
  @enforce_keys [:id, :name]
  defstruct [
    :id,
    :name,
    :version,
    :created_at,
    :updated_at,
    :root_subgraph_id,
    oodn_registry: %{},
    oodn_position: %{x: 600, y: 80},
    subgraphs: %{},
    backend: :traditional
  ]

  @spec new(String.t()) :: t()
  def new(name \\ "untitled") do
    now = DateTime.to_iso8601(DateTime.utc_now())
    root = Subgraph.new(name: "root", floor: 0)

    %__MODULE__{
      id: UUID.uuid4(),
      name: name,
      version: "0.2.0",
      created_at: now,
      updated_at: now,
      root_subgraph_id: root.id,
      subgraphs: %{root.id => root},
      oodn_registry: %{}
    }
  end

  @spec root_subgraph(t()) :: Subgraph.t() | nil
  def root_subgraph(%__MODULE__{subgraphs: subgraphs, root_subgraph_id: id}) do
    Map.get(subgraphs, id)
  end

  @spec get_subgraph(t(), String.t()) :: Subgraph.t() | nil
  def get_subgraph(%__MODULE__{subgraphs: subgraphs}, id) do
    Map.get(subgraphs, id)
  end

  @spec put_subgraph(t(), Subgraph.t()) :: t()
  def put_subgraph(%__MODULE__{} = graph, %Subgraph{} = sg) do
    now = DateTime.to_iso8601(DateTime.utc_now())

    %{graph | subgraphs: Map.put(graph.subgraphs, sg.id, sg), updated_at: now}
  end
end
