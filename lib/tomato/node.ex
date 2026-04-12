defmodule Tomato.Node do
  @moduledoc """
  The atomic unit of the graph.

  ## `:target`

  Leaf nodes declare which backend their content is compatible with
  via the `:target` field:

    * `:nixos` (default) — NixOS system-level config. Safe for
      `nixosConfigurations` and the traditional `configuration.nix`
      backend. Not included in `homeConfigurations`.
    * `:home_manager` — Home Manager user-level config. Included
      only in Home Manager machines.
    * `:all` — compatible with both. Rare; use when a fragment only
      sets option paths that exist in both schemas.

  The walker filters shared root-level fragments and in-machine
  fragments by this field against the current machine type at
  generation time.
  """

  @type node_type :: :input | :output | :leaf | :gateway
  @type machine_type :: :nixos | :home_manager
  @type target :: :nixos | :home_manager | :all
  @type machine_meta :: %{
          optional(:hostname) => String.t(),
          optional(:system) => String.t(),
          optional(:state_version) => String.t(),
          optional(:type) => machine_type(),
          optional(:username) => String.t(),
          optional(:oodn_overrides) => %{String.t() => String.t()}
        }
  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          type: node_type(),
          target: target(),
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
    position: %{x: 0, y: 0},
    target: :nixos
  ]

  @spec new(keyword()) :: t()
  def new(attrs) do
    %__MODULE__{
      id: attrs[:id] || generate_id(),
      name: attrs[:name] || "Untitled",
      type: attrs[:type] || :leaf,
      target: attrs[:target] || :nixos,
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
