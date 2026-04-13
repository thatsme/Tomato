defmodule TomatoWeb.GraphLive.OodnHandlers do
  @moduledoc """
  Handler functions for the OODN registry in `TomatoWeb.GraphLive`.
  OODN (Object-Oriented Design Notation) is a graph-level key/value
  registry — `${key}` placeholders in leaf content are substituted from
  this registry at generation time.

  Each public function takes `(params, socket)` and returns
  `{:noreply, socket}`, so the main LiveView can delegate directly:

      def handle_event("add_oodn", params, socket),
        do: OodnHandlers.add(params, socket)

  The `select/2` and `close_editor/2` handlers manage the `:editing_oodn`
  assign that gates the OODN editor modal; the mutation handlers (`add`,
  `update`, `remove`, `move`) call the store and leave the modal state
  alone.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Tomato.Store

  @type socket :: Phoenix.LiveView.Socket.t()
  @type result :: {:noreply, socket()}

  # --- Editor modal lifecycle ---

  @spec select(map(), socket()) :: result()
  def select(_params, socket) do
    {:noreply, assign(socket, :editing_oodn, true)}
  end

  @spec close_editor(map(), socket()) :: result()
  def close_editor(_params, socket) do
    {:noreply, assign(socket, :editing_oodn, false)}
  end

  # --- Mutation ---

  @spec add(map(), socket()) :: result()
  def add(%{"key" => key, "value" => value}, socket) do
    Store.put_oodn(socket.assigns.store, key, value)
    {:noreply, socket}
  end

  @spec update(map(), socket()) :: result()
  def update(%{"oodn-id" => oodn_id, "value" => value}, socket) do
    Store.update_oodn(socket.assigns.store, oodn_id, value)
    {:noreply, socket}
  end

  @spec remove(map(), socket()) :: result()
  def remove(%{"oodn-id" => oodn_id}, socket) do
    Store.remove_oodn(socket.assigns.store, oodn_id)
    {:noreply, socket}
  end

  @spec move(map(), socket()) :: result()
  def move(%{"x" => x, "y" => y}, socket) do
    Store.move_oodn(socket.assigns.store, %{x: x, y: y})
    {:noreply, socket}
  end
end
