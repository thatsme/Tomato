defmodule Tomato.Node do
  @moduledoc """
  The atomic unit of the graph.
  """

  @type node_type :: :input | :output | :leaf | :gateway
  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          type: node_type(),
          template_fn: {module(), atom(), list()} | nil,
          subgraph_id: String.t() | nil,
          inputs: list(String.t()),
          outputs: list(String.t()),
          position: %{x: number(), y: number()},
          content: String.t() | nil
        }

  @derive Jason.Encoder
  @enforce_keys [:id, :name, :type]
  defstruct [
    :id,
    :name,
    :type,
    :template_fn,
    :subgraph_id,
    :content,
    inputs: [],
    outputs: [],
    position: %{x: 0, y: 0}
  ]

  @spec new(keyword()) :: t()
  def new(attrs) do
    %__MODULE__{
      id: attrs[:id] || generate_id(),
      name: attrs[:name] || "Untitled",
      type: attrs[:type] || :leaf,
      template_fn: attrs[:template_fn],
      subgraph_id: attrs[:subgraph_id],
      content: attrs[:content],
      inputs: attrs[:inputs] || [],
      outputs: attrs[:outputs] || [],
      position: attrs[:position] || %{x: 0, y: 0}
    }
  end

  defp generate_id, do: UUID.uuid4()
end
