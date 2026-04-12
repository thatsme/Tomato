defmodule Tomato.Node do
  @moduledoc """
  The atomic unit of the graph.
  """

  @type node_type :: :input | :output | :leaf | :gateway
  @type machine_meta :: %{
          optional(:hostname) => String.t(),
          optional(:system) => String.t(),
          optional(:state_version) => String.t()
        }
  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          type: node_type(),
          template_fn: {module(), atom(), list()} | nil,
          subgraph_id: String.t() | nil,
          inputs: list(String.t()),
          outputs: list(String.t()),
          position: %{x: number(), y: number()},
          content: String.t() | nil,
          machine: machine_meta() | nil
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
    :machine,
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
      machine: attrs[:machine],
      inputs: attrs[:inputs] || [],
      outputs: attrs[:outputs] || [],
      position: attrs[:position] || %{x: 0, y: 0}
    }
  end

  @spec machine?(t()) :: boolean()
  def machine?(%__MODULE__{type: :gateway, machine: m}) when is_map(m), do: true
  def machine?(_), do: false

  defp generate_id, do: UUID.uuid4()
end
