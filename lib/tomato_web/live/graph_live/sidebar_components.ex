defmodule TomatoWeb.GraphLive.SidebarComponents do
  @moduledoc """
  Left-sidebar function components for the Tomato graph editor.

  Public function components:

    * `sidebar_header/1`   — branding, file/backend/generate, undo/redo
    * `breadcrumb/1`       — floor indicator + subgraph path
    * `sidebar_toolbar/1`  — Add Node / Gateway / Machine buttons
    * `search_panel/1`     — search input + results + empty state
    * `node_list/1`        — list of nodes in the current subgraph
    * `properties_panel/1` — selected node details (name, type, machine, actions)

  All components are pure — they read from explicit attrs and emit
  `phx-click` / `phx-submit` events that the LiveView handles.
  """

  use Phoenix.Component

  import TomatoWeb.GraphLive.CanvasComponents, only: [node_color: 1, has_content?: 1]

  # --- Header ---

  attr :current_file, :string, default: nil
  attr :backend, :atom, required: true
  attr :history_status, :any, required: true

  def sidebar_header(assigns) do
    ~H"""
    <div class="p-3 border-b border-base-300">
      <div class="flex items-center gap-2">
        <span class="text-lg font-bold text-primary">Tomato</span>
        <span class="text-xs text-base-content/40">v0.3</span>
      </div>
      <div class="flex items-center gap-1 mt-2">
        <button
          class="btn btn-xs btn-ghost flex-1"
          phx-click="open_graph_manager"
          title="Open / New / Save As"
        >
          {@current_file || "unsaved"}
        </button>
        <button
          class={[
            "btn btn-xs",
            @backend == :flake && "btn-info",
            @backend != :flake && "btn-ghost"
          ]}
          phx-click="toggle_backend"
          title="Switch between Traditional and Flake output"
        >
          {if @backend == :flake, do: "Flake", else: "Traditional"}
        </button>
        <button class="btn btn-xs btn-accent" phx-click="generate">
          Generate
        </button>
      </div>
      <%!-- Undo/Redo --%>
      <div class="flex items-center gap-1 mt-2">
        <button
          class={["btn btn-xs btn-ghost flex-1", elem(@history_status, 0) == 0 && "btn-disabled"]}
          phx-click="undo"
          title="Undo (Cmd+Z)"
          disabled={elem(@history_status, 0) == 0}
        >
          ↶ Undo ({elem(@history_status, 0)})
        </button>
        <button
          class={["btn btn-xs btn-ghost flex-1", elem(@history_status, 1) == 0 && "btn-disabled"]}
          phx-click="redo"
          title="Redo (Cmd+Shift+Z)"
          disabled={elem(@history_status, 1) == 0}
        >
          Redo ({elem(@history_status, 1)}) ↷
        </button>
      </div>
    </div>
    """
  end

  # --- Breadcrumb ---

  attr :breadcrumb, :list, required: true
  attr :floor, :integer, required: true

  def breadcrumb(assigns) do
    ~H"""
    <div class="p-3 border-b border-base-300">
      <div class="text-xs text-base-content/60 mb-1">Floor {@floor}</div>
      <div class="flex flex-wrap gap-1">
        <span
          :for={{sg_id, name} <- @breadcrumb}
          class="text-sm cursor-pointer hover:text-primary"
          phx-click="navigate_breadcrumb"
          phx-value-subgraph-id={sg_id}
        >
          <span class="text-base-content/40">/</span>{name}
        </span>
      </div>
    </div>
    """
  end

  # --- Toolbar ---

  attr :floor, :integer, required: true

  def sidebar_toolbar(assigns) do
    ~H"""
    <div class="p-3 border-b border-base-300 space-y-2">
      <button class="btn btn-sm btn-primary w-full" phx-click="show_template_picker">
        + Add Node
      </button>
      <button class="btn btn-sm btn-secondary w-full" phx-click="add_gateway">
        + Gateway
      </button>
      <button
        :if={@floor == 0}
        class="btn btn-sm btn-warning w-full"
        phx-click="add_machine"
      >
        + Machine
      </button>
    </div>
    """
  end

  # --- Search ---

  attr :query, :string, required: true
  attr :results, :list, required: true

  def search_panel(assigns) do
    ~H"""
    <div class="p-3 border-b border-base-300">
      <form phx-change="search_nodes" phx-submit="search_nodes">
        <input
          type="text"
          name="q"
          value={@query}
          placeholder="Search nodes..."
          class="input input-xs input-bordered w-full"
          phx-debounce="200"
        />
      </form>
    </div>

    <%!-- Search results (when searching) --%>
    <div :if={@query != "" && @results != []} class="flex-1 overflow-y-auto p-3">
      <h3 class="text-xs font-semibold text-base-content/60 mb-2 uppercase">
        Results ({length(@results)})
      </h3>
      <div class="space-y-1">
        <div
          :for={result <- @results}
          class="flex items-center gap-2 px-2 py-1.5 rounded text-sm cursor-pointer hover:bg-base-200"
          phx-click="goto_search_result"
          phx-value-subgraph-id={result.subgraph_id}
          phx-value-node-id={result.node.id}
        >
          <span class={["w-2 h-2 rounded-full shrink-0", node_color(result.node.type)]} />
          <div class="flex-1 min-w-0">
            <div class="truncate">{result.node.name}</div>
            <div class="text-xs text-base-content/40 truncate">in {result.subgraph_name}</div>
          </div>
        </div>
      </div>
    </div>

    <%!-- Empty results --%>
    <div
      :if={@query != "" && @results == []}
      class="flex-1 overflow-y-auto p-3"
    >
      <div class="text-xs text-base-content/40 text-center py-4">
        No nodes match "{@query}"
      </div>
    </div>
    """
  end

  # --- Node List ---

  attr :nodes, :map, required: true
  attr :selected_node_id, :string, default: nil

  def node_list(assigns) do
    ~H"""
    <div class="flex-1 overflow-y-auto p-3">
      <h3 class="text-xs font-semibold text-base-content/60 mb-2 uppercase">Nodes</h3>
      <div class="space-y-1">
        <div
          :for={{_id, node} <- @nodes}
          class={[
            "flex items-center gap-2 px-2 py-1.5 rounded text-sm cursor-pointer",
            node.id == @selected_node_id && "bg-primary/10 text-primary",
            node.id != @selected_node_id && "hover:bg-base-200"
          ]}
          phx-click="select_node"
          phx-value-node-id={node.id}
        >
          <span class={["w-2 h-2 rounded-full shrink-0", node_color(node.type)]} />
          <span class="truncate">{node.name}</span>
          <span
            :if={node.type == :leaf && has_content?(node)}
            class="text-xs text-success ml-auto"
            title="Has content"
          >
            *
          </span>
          <span class="text-xs text-base-content/40 ml-auto">{node.type}</span>
        </div>
      </div>
    </div>
    """
  end

  # --- Properties Panel ---

  attr :node, :map, required: true

  def properties_panel(assigns) do
    ~H"""
    <div class="border-t border-base-300 p-3">
      <h3 class="text-xs font-semibold text-base-content/60 mb-2 uppercase">Properties</h3>
      <div class="space-y-2">
        <div>
          <label class="text-xs text-base-content/60">Name</label>
          <form phx-submit="rename_node" phx-value-node-id={@node.id}>
            <input
              type="text"
              name="name"
              value={@node.name}
              class="input input-sm input-bordered w-full"
            />
          </form>
        </div>
        <div class="text-xs text-base-content/50">
          Type: {@node.type}{if Tomato.Node.machine?(@node), do: " (machine)", else: ""}
        </div>
        <%!-- Machine metadata editor --%>
        <div :if={Tomato.Node.machine?(@node)} class="space-y-1">
          <form phx-submit="update_machine" phx-value-node-id={@node.id}>
            <div class="flex gap-1 items-center">
              <label class="text-xs text-base-content/60 w-16">Type</label>
              <select name="type" class="select select-xs select-bordered flex-1 font-mono">
                <option value="nixos" selected={Map.get(@node.machine, :type, :nixos) == :nixos}>
                  NixOS
                </option>
                <option
                  value="home_manager"
                  selected={Map.get(@node.machine, :type) == :home_manager}
                >
                  Home Manager
                </option>
              </select>
            </div>
            <div class="flex gap-1 items-center mt-1">
              <label class="text-xs text-base-content/60 w-16">Host</label>
              <input
                type="text"
                name="hostname"
                value={@node.machine.hostname}
                class="input input-xs input-bordered flex-1 font-mono"
              />
            </div>
            <div class="flex gap-1 items-center mt-1">
              <label class="text-xs text-base-content/60 w-16">User</label>
              <input
                type="text"
                name="username"
                value={Map.get(@node.machine, :username, "user")}
                class="input input-xs input-bordered flex-1 font-mono"
              />
            </div>
            <div class="flex gap-1 items-center mt-1">
              <label class="text-xs text-base-content/60 w-16">System</label>
              <select name="system" class="select select-xs select-bordered flex-1 font-mono">
                <option value="aarch64-linux" selected={@node.machine.system == "aarch64-linux"}>
                  aarch64-linux
                </option>
                <option value="x86_64-linux" selected={@node.machine.system == "x86_64-linux"}>
                  x86_64-linux
                </option>
                <option value="aarch64-darwin" selected={@node.machine.system == "aarch64-darwin"}>
                  aarch64-darwin
                </option>
              </select>
            </div>
            <div class="flex gap-1 items-center mt-1">
              <label class="text-xs text-base-content/60 w-16">Version</label>
              <input
                type="text"
                name="state_version"
                value={@node.machine.state_version}
                class="input input-xs input-bordered flex-1 font-mono"
              />
            </div>
            <button type="submit" class="btn btn-xs btn-warning mt-1 w-full">Update</button>
          </form>
        </div>
        <div class="flex flex-wrap gap-2">
          <button
            :if={@node.type == :leaf}
            class="btn btn-xs btn-info"
            phx-click="edit_node_content"
            phx-value-node-id={@node.id}
          >
            Edit Content
          </button>
          <button
            :if={@node.type not in [:input, :output]}
            class="btn btn-xs btn-error"
            phx-click="delete_node"
            phx-value-node-id={@node.id}
          >
            Delete
          </button>
          <button
            class="btn btn-xs btn-outline"
            phx-click="start_connect"
            phx-value-node-id={@node.id}
          >
            Connect
          </button>
          <button
            :if={@node.type == :gateway}
            class="btn btn-xs btn-accent"
            phx-click="enter_gateway"
            phx-value-node-id={@node.id}
          >
            Enter
          </button>
        </div>
      </div>
    </div>
    """
  end
end
