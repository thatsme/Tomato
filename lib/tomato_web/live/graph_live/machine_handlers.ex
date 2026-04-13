defmodule TomatoWeb.GraphLive.MachineHandlers do
  @moduledoc """
  Handler functions for machine-node metadata edits in `TomatoWeb.GraphLive`.
  Machine nodes carry hostname, system, state_version, type (nixos vs
  home_manager) and username — all edited via the properties panel when
  a machine node is selected.

  Each public function takes `(params, socket)` and returns
  `{:noreply, socket}`, so the main LiveView can delegate directly:

      def handle_event("update_machine", params, socket),
        do: MachineHandlers.update/2

  Currently small (one clause) but separate from `OodnHandlers` because
  machine metadata lives on a specific node while OODN is a graph-level
  registry — different domains that happen to share the same "metadata
  editor" UI pattern.
  """

  alias Tomato.Store

  @type socket :: Phoenix.LiveView.Socket.t()
  @type result :: {:noreply, socket()}

  @spec update(map(), socket()) :: result()
  def update(params, socket) do
    store = socket.assigns.store
    node_id = params["node-id"]

    machine_type = if params["type"] == "home_manager", do: :home_manager, else: :nixos

    machine = %{
      hostname: params["hostname"],
      system: params["system"],
      state_version: params["state_version"],
      type: machine_type,
      username: params["username"] || "user"
    }

    Store.update_node(store, socket.assigns.subgraph.id, node_id,
      machine: machine,
      name: params["hostname"]
    )

    {:noreply, socket}
  end
end
