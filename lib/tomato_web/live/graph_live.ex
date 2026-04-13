defmodule TomatoWeb.GraphLive do
  @moduledoc "Main LiveView for the graph editor."
  use TomatoWeb, :live_view

  import TomatoWeb.GraphLive.CanvasComponents
  import TomatoWeb.GraphLive.ModalComponents
  import TomatoWeb.GraphLive.SidebarComponents

  alias Tomato.{Store, Graph}

  alias TomatoWeb.GraphLive.{
    DeployHandlers,
    EdgeHandlers,
    GraphStateHandlers,
    MachineHandlers,
    NavigationHandlers,
    NodeHandlers,
    OodnHandlers,
    TemplateHandlers
  }

  @impl true
  def mount(_params, session, socket) do
    store = Map.get(session, "store", Tomato.Store)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tomato.PubSub, Store.topic(store))
    end

    graph = Store.get_graph(store)
    root_id = graph.root_subgraph_id
    subgraph = Graph.get_subgraph(graph, root_id)

    {:ok,
     socket
     |> assign(:store, store)
     |> assign(:graph, graph)
     |> assign(:subgraph, subgraph)
     |> assign(:breadcrumb, [{root_id, subgraph.name}])
     |> assign(:selected_node_id, nil)
     |> assign(:connecting_from, nil)
     |> assign(:connecting_to, nil)
     |> assign(:editing_content_node_id, nil)
     |> assign(:editing_oodn, false)
     |> assign(:show_template_picker, false)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:history_status, Store.history_status(store))
     |> assign(:show_generated, false)
     |> assign(:generated_output, "")
     |> assign(:generated_path, nil)
     |> assign(:validation_result, :disabled)
     |> assign(:deploy_status, nil)
     |> assign(:deploy_output, "")
     |> assign(:show_graph_manager, false)
     |> assign(:graph_list, [])
     |> assign(:current_file, Store.current_file(store))
     |> assign(:page_title, "Graph Editor")}
  end

  @impl true
  # Deploy/diff result dispatch — body lives in DeployHandlers, the tuple
  # envelope is unwrapped here and the bare-socket return is re-wrapped.
  def handle_info({:deploy_result, result}, socket),
    do: {:noreply, DeployHandlers.handle_deploy_result(result, socket)}

  def handle_info({:diff_result, result}, socket),
    do: {:noreply, DeployHandlers.handle_diff_result(result, socket)}

  def handle_info({:graph_updated, graph}, socket) do
    subgraph = Graph.get_subgraph(graph, socket.assigns.subgraph.id)

    {:noreply,
     socket
     |> assign(:graph, graph)
     |> assign(:subgraph, subgraph || socket.assigns.subgraph)
     |> assign(:history_status, Store.history_status(socket.assigns.store))}
  end

  # --- Events ---

  @impl true
  def handle_event("show_template_picker", params, socket),
    do: TemplateHandlers.open(params, socket)

  def handle_event("close_template_picker", params, socket),
    do: TemplateHandlers.close(params, socket)

  def handle_event("add_from_template", params, socket),
    do: TemplateHandlers.add(params, socket)

  def handle_event("add_leaf", params, socket),
    do: NodeHandlers.add_leaf(params, socket)

  def handle_event("add_machine", params, socket),
    do: NodeHandlers.add_machine(params, socket)

  def handle_event("add_gateway", params, socket),
    do: NodeHandlers.add_gateway(params, socket)

  def handle_event("add_node_at", params, socket),
    do: NodeHandlers.add_node_at(params, socket)

  def handle_event("select_node", params, socket),
    do: NodeHandlers.select(params, socket)

  def handle_event("deselect", params, socket),
    do: NodeHandlers.deselect(params, socket)

  def handle_event("delete_node", params, socket),
    do: NodeHandlers.delete(params, socket)

  def handle_event("delete_edge", params, socket),
    do: EdgeHandlers.delete(params, socket)

  def handle_event("start_connect", params, socket),
    do: EdgeHandlers.start_connect(params, socket)

  def handle_event("cancel_connect", params, socket),
    do: EdgeHandlers.cancel_connect(params, socket)

  def handle_event("enter_gateway", params, socket),
    do: NavigationHandlers.enter_gateway(params, socket)

  def handle_event("navigate_breadcrumb", params, socket),
    do: NavigationHandlers.navigate_breadcrumb(params, socket)

  def handle_event("node_moved", params, socket),
    do: NodeHandlers.moved(params, socket)

  def handle_event("rename_node", params, socket),
    do: NodeHandlers.rename(params, socket)

  # --- Content editing ---

  def handle_event("edit_node_content", params, socket),
    do: NodeHandlers.edit_content(params, socket)

  def handle_event("save_content", params, socket),
    do: NodeHandlers.save_content(params, socket)

  def handle_event("close_editor", params, socket),
    do: NodeHandlers.close_editor(params, socket)

  # --- Machine ---

  def handle_event("update_machine", params, socket),
    do: MachineHandlers.update(params, socket)

  # --- Undo / Redo ---

  def handle_event("undo", params, socket),
    do: GraphStateHandlers.undo(params, socket)

  def handle_event("redo", params, socket),
    do: GraphStateHandlers.redo(params, socket)

  # --- Search ---

  def handle_event("search_nodes", params, socket),
    do: NavigationHandlers.search(params, socket)

  def handle_event("goto_search_result", params, socket),
    do: NavigationHandlers.goto_search_result(params, socket)

  # --- Backend toggle ---

  def handle_event("toggle_backend", params, socket),
    do: GraphStateHandlers.toggle_backend(params, socket)

  # --- Deploy pipeline ---

  def handle_event("generate", params, socket),
    do: DeployHandlers.generate(params, socket)

  def handle_event("close_generated", params, socket),
    do: DeployHandlers.close_generated(params, socket)

  def handle_event("reconfigure", params, socket),
    do: DeployHandlers.reconfigure(params, socket)

  def handle_event("show_diff", params, socket),
    do: DeployHandlers.show_diff(params, socket)

  def handle_event("rollback", params, socket),
    do: DeployHandlers.rollback(params, socket)

  def handle_event("test_connection", params, socket),
    do: DeployHandlers.test_connection(params, socket)

  # --- Graph management ---

  def handle_event("open_graph_manager", params, socket),
    do: GraphStateHandlers.open_manager(params, socket)

  def handle_event("close_graph_manager", params, socket),
    do: GraphStateHandlers.close_manager(params, socket)

  def handle_event("load_graph_file", params, socket),
    do: GraphStateHandlers.load(params, socket)

  def handle_event("new_graph_submit", params, socket),
    do: GraphStateHandlers.new(params, socket)

  def handle_event("save_as_submit", params, socket),
    do: GraphStateHandlers.save_as(params, socket)

  def handle_event("delete_graph_file", params, socket),
    do: GraphStateHandlers.delete(params, socket)

  # --- OODN ---

  def handle_event("select_oodn", params, socket),
    do: OodnHandlers.select(params, socket)

  def handle_event("close_oodn_editor", params, socket),
    do: OodnHandlers.close_editor(params, socket)

  def handle_event("add_oodn", params, socket),
    do: OodnHandlers.add(params, socket)

  def handle_event("update_oodn", params, socket),
    do: OodnHandlers.update(params, socket)

  def handle_event("remove_oodn", params, socket),
    do: OodnHandlers.remove(params, socket)

  def handle_event("oodn_moved", params, socket),
    do: OodnHandlers.move(params, socket)

  # --- Context menu actions ---

  def handle_event("start_connect_to", params, socket),
    do: EdgeHandlers.start_connect_to(params, socket)

  def handle_event("duplicate_node", params, socket),
    do: NodeHandlers.duplicate(params, socket)

  def handle_event("disconnect_node", params, socket),
    do: EdgeHandlers.disconnect(params, socket)

  def handle_event("reverse_edge", params, socket),
    do: EdgeHandlers.reverse(params, socket)

  def handle_event("start_rename", params, socket),
    do: NodeHandlers.start_rename(params, socket)

  # Canvas event plumbing — phx-click="stop_propagation" on the sidebar wrapper
  # prevents clicks inside the sidebar from bubbling to the outer `deselect`
  # handler. Not a domain handler, stays inline.
  def handle_event("stop_propagation", _params, socket) do
    {:noreply, socket}
  end

  # --- Rendering ---

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen bg-base-200" phx-click="deselect">
      <%!-- Sidebar --%>
      <div
        class="w-72 bg-base-100 border-r border-base-300 flex flex-col"
        phx-click="stop_propagation"
      >
        <.sidebar_header
          current_file={@current_file}
          backend={@graph.backend}
          history_status={@history_status}
        />

        <.breadcrumb breadcrumb={@breadcrumb} floor={@subgraph.floor} />

        <.sidebar_toolbar floor={@subgraph.floor} />

        <.search_panel query={@search_query} results={@search_results} />

        <.node_list
          :if={@search_query == ""}
          nodes={@subgraph.nodes}
          selected_node_id={@selected_node_id}
        />

        <.properties_panel
          :if={@selected_node_id && Map.get(@subgraph.nodes, @selected_node_id)}
          node={Map.get(@subgraph.nodes, @selected_node_id)}
        />
      </div>

      <%!-- Canvas --%>
      <div class="flex-1 relative overflow-hidden">
        <%!-- Connection mode indicator --%>
        <div
          :if={@connecting_from || @connecting_to}
          class="absolute top-4 left-1/2 -translate-x-1/2 z-10"
        >
          <div class="alert alert-info py-2 px-4 text-sm shadow-lg">
            <span :if={@connecting_from}>Click a target node to connect to</span>
            <span :if={@connecting_to}>Click a source node to connect from</span>
            <button class="btn btn-xs btn-ghost" phx-click="deselect">Cancel</button>
          </div>
        </div>

        <%!-- Canvas hints --%>
        <div class="absolute top-4 right-4 z-10 text-xs text-base-content/30 space-y-0.5 text-right pointer-events-none">
          <div>Scroll: pan | Pinch/Ctrl+scroll: zoom</div>
          <div>Double-click: enter gateway | Cmd+click: edit leaf content</div>
          <div>Long-press / right-click: context menu</div>
        </div>

        <svg
          id="graph-canvas"
          class="w-full h-full"
          phx-hook="GraphCanvas"
          data-subgraph-id={@subgraph.id}
        >
          <defs>
            <marker id="arrowhead" markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto">
              <polygon points="0 0, 8 3, 0 6" class="fill-base-content/40" />
            </marker>
          </defs>

          <%!-- Edges --%>
          <g id="edges">
            <.edge_line
              :for={{_id, edge} <- @subgraph.edges}
              edge={edge}
              nodes={@subgraph.nodes}
            />
          </g>

          <%!-- Nodes --%>
          <g id="nodes">
            <.graph_node
              :for={{_id, node} <- @subgraph.nodes}
              node={node}
              selected={node.id == @selected_node_id}
              connecting={@connecting_from != nil}
            />
          </g>

          <%!-- OODN node — only on root floor --%>
          <.oodn_node
            :if={@subgraph.floor == 0}
            oodn_registry={@graph.oodn_registry}
            position={@graph.oodn_position || %{x: 600, y: 80}}
          />
        </svg>

        <%!-- Minimap --%>
        <.minimap subgraph={@subgraph} />
      </div>

      <%!-- Content Editor Modal --%>
      <.content_editor
        :if={@editing_content_node_id}
        node={Map.get(@subgraph.nodes, @editing_content_node_id)}
      />

      <%!-- Template Picker Modal --%>
      <.template_picker :if={@show_template_picker} />

      <%!-- OODN Editor Modal --%>
      <.oodn_editor
        :if={@editing_oodn}
        oodn_registry={@graph.oodn_registry}
      />

      <%!-- Generated Output Modal --%>
      <.generated_output
        :if={@show_generated}
        output={@generated_output}
        path={@generated_path}
        validation={@validation_result}
        deploy_status={@deploy_status}
        deploy_output={@deploy_output}
      />

      <%!-- Graph Manager Modal --%>
      <.graph_manager
        :if={@show_graph_manager}
        graph_list={@graph_list}
        current_file={@current_file}
      />
    </div>
    """
  end

end
