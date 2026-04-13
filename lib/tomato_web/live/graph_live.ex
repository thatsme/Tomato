defmodule TomatoWeb.GraphLive do
  @moduledoc "Main LiveView for the graph editor."
  use TomatoWeb, :live_view

  import TomatoWeb.GraphLive.CanvasComponents
  import TomatoWeb.GraphLive.ModalComponents
  import TomatoWeb.GraphLive.SidebarComponents

  alias Tomato.{Store, Graph}
  alias TomatoWeb.GraphLive.{EdgeHandlers, NavigationHandlers, NodeHandlers}

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
     |> assign(:deploy_status, nil)
     |> assign(:deploy_output, "")
     |> assign(:show_graph_manager, false)
     |> assign(:graph_list, [])
     |> assign(:current_file, Store.current_file(store))
     |> assign(:page_title, "Graph Editor")}
  end

  defp store(socket), do: socket.assigns.store

  @impl true
  def handle_info({:deploy_result, {:ok, output}}, socket) do
    {:noreply,
     socket
     |> assign(:deploy_status, "success")
     |> assign(:deploy_output, output)}
  end

  def handle_info({:deploy_result, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:deploy_status, "error")
     |> assign(:deploy_output, reason)}
  end

  def handle_info({:diff_result, {:ok, ""}}, socket) do
    {:noreply,
     socket
     |> assign(:deploy_status, "success")
     |> assign(:deploy_output, "No changes — local config matches the machine.")}
  end

  def handle_info({:diff_result, {:ok, diff}}, socket) do
    {:noreply,
     socket
     |> assign(:deploy_status, "success")
     |> assign(:deploy_output, "=== Diff (current vs new) ===\n\n" <> diff)}
  end

  def handle_info({:diff_result, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:deploy_status, "error")
     |> assign(:deploy_output, "Diff failed: " <> reason)}
  end

  def handle_info({:graph_updated, graph}, socket) do
    subgraph = Graph.get_subgraph(graph, socket.assigns.subgraph.id)

    {:noreply,
     socket
     |> assign(:graph, graph)
     |> assign(:subgraph, subgraph || socket.assigns.subgraph)
     |> assign(:history_status, Store.history_status(store(socket)))}
  end

  # --- Events ---

  @impl true
  def handle_event("show_template_picker", _params, socket) do
    {:noreply, assign(socket, :show_template_picker, true)}
  end

  def handle_event("close_template_picker", _params, socket) do
    {:noreply, assign(socket, :show_template_picker, false)}
  end

  def handle_event("add_from_template", %{"template-id" => template_id}, socket) do
    sg = socket.assigns.subgraph
    node_count = map_size(sg.nodes)
    y = 100 + node_count * 80

    template = Tomato.TemplateLibrary.get(template_id)

    if template do
      case Map.get(template, :type, :leaf) do
        :gateway ->
          # Create gateway with pre-populated child nodes
          {:ok, gw, child} =
            Store.add_gateway(store(socket), sg.id,
              name: template.name,
              position: %{x: 300, y: y}
            )

          children = Map.get(template, :children, [])
          child_sg = Store.get_subgraph(store(socket), child.id)
          child_input = Tomato.Subgraph.input_node(child_sg)
          child_output = Tomato.Subgraph.output_node(child_sg)

          # Create each child leaf and wire input -> leaf -> output
          children
          |> Enum.with_index()
          |> Enum.each(fn {child_tmpl, idx} ->
            {:ok, leaf} =
              Store.add_node(store(socket), child.id,
                type: :leaf,
                name: child_tmpl.name,
                content: String.trim(child_tmpl.content),
                position: %{x: 150 + idx * 180, y: 200}
              )

            Store.add_edge(store(socket), child.id, child_input.id, leaf.id)
            Store.add_edge(store(socket), child.id, leaf.id, child_output.id)
          end)

          {:noreply,
           socket
           |> assign(:show_template_picker, false)
           |> assign(:selected_node_id, gw.id)}

        _ ->
          # Simple leaf node
          {:ok, node} =
            Store.add_node(store(socket), sg.id,
              type: :leaf,
              name: template.name,
              content: String.trim(template.content),
              position: %{x: 300, y: y}
            )

          {:noreply,
           socket
           |> assign(:show_template_picker, false)
           |> assign(:selected_node_id, node.id)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_leaf", params, socket),
    do: NodeHandlers.add_leaf(params, socket)

  def handle_event("add_machine", _params, socket) do
    sg = socket.assigns.subgraph
    node_count = map_size(sg.nodes)
    y = 100 + node_count * 80

    {:ok, _machine, _child} =
      Store.add_machine(store(socket), sg.id,
        hostname: "machine-#{node_count}",
        system: "aarch64-linux",
        state_version: "24.11",
        position: %{x: 300, y: y}
      )

    {:noreply, socket}
  end

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

  def handle_event("update_machine", params, socket) do
    node_id = params["node-id"]

    machine_type = if params["type"] == "home_manager", do: :home_manager, else: :nixos

    machine = %{
      hostname: params["hostname"],
      system: params["system"],
      state_version: params["state_version"],
      type: machine_type,
      username: params["username"] || "user"
    }

    Store.update_node(store(socket), socket.assigns.subgraph.id, node_id,
      machine: machine,
      name: params["hostname"]
    )

    {:noreply, socket}
  end

  # --- Undo / Redo ---

  def handle_event("undo", _params, socket) do
    Store.undo(store(socket))
    {:noreply, socket}
  end

  def handle_event("redo", _params, socket) do
    Store.redo(store(socket))
    {:noreply, socket}
  end

  # --- Search ---

  def handle_event("search_nodes", params, socket),
    do: NavigationHandlers.search(params, socket)

  def handle_event("goto_search_result", params, socket),
    do: NavigationHandlers.goto_search_result(params, socket)

  # --- Backend toggle ---

  def handle_event("toggle_backend", _params, socket) do
    new_backend = if socket.assigns.graph.backend == :flake, do: :traditional, else: :flake
    Store.set_backend(store(socket), new_backend)
    {:noreply, socket}
  end

  # --- Generate ---

  def handle_event("generate", _params, socket) do
    graph = socket.assigns.graph
    output = Tomato.Walker.walk(graph)

    # Write .nix file to disk
    generated_dir = Path.expand("priv/generated", File.cwd!())
    File.mkdir_p!(generated_dir)

    filename =
      case graph.backend do
        :flake -> "flake.nix"
        _ -> Tomato.Store.slugify(graph.name) <> ".nix"
      end

    nix_path = Path.join(generated_dir, filename)
    File.write!(nix_path, output)

    {:noreply,
     socket
     |> assign(:generated_output, output)
     |> assign(:generated_path, nix_path)
     |> assign(:show_generated, true)}
  end

  def handle_event("close_generated", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_generated, false)
     |> assign(:deploy_status, nil)
     |> assign(:deploy_output, "")}
  end

  def handle_event("reconfigure", params, socket) do
    nix_path = socket.assigns.generated_path
    mode = parse_deploy_mode(params["mode"])

    if nix_path && File.exists?(nix_path) do
      pid = self()

      Task.Supervisor.start_child(Tomato.TaskSupervisor, fn ->
        result = Tomato.Deploy.deploy(nix_path, %{mode: mode})
        send(pid, {:deploy_result, result})
      end)

      {:noreply,
       socket
       |> assign(:deploy_status, "running")
       |> assign(:deploy_output, "Running nixos-rebuild #{mode}...")}
    else
      {:noreply,
       socket
       |> assign(:deploy_status, "error")
       |> assign(:deploy_output, "No .nix file generated yet. Click Generate first.")}
    end
  end

  def handle_event("show_diff", _params, socket) do
    nix_path = socket.assigns.generated_path

    if nix_path && File.exists?(nix_path) do
      pid = self()

      Task.Supervisor.start_child(Tomato.TaskSupervisor, fn ->
        result = Tomato.Deploy.diff(nix_path)
        send(pid, {:diff_result, result})
      end)

      {:noreply,
       socket
       |> assign(:deploy_status, "running")
       |> assign(:deploy_output, "Fetching current config from machine...")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("rollback", _params, socket) do
    pid = self()

    Task.Supervisor.start_child(Tomato.TaskSupervisor, fn ->
      result = Tomato.Deploy.rollback()
      send(pid, {:deploy_result, result})
    end)

    {:noreply,
     socket
     |> assign(:deploy_status, "running")
     |> assign(:deploy_output, "Rolling back to previous generation...")}
  end

  def handle_event("test_connection", _params, socket) do
    pid = self()

    Task.Supervisor.start_child(Tomato.TaskSupervisor, fn ->
      result = Tomato.Deploy.test_connection()
      send(pid, {:deploy_result, result})
    end)

    {:noreply,
     socket
     |> assign(:deploy_status, "running")
     |> assign(:deploy_output, "Testing SSH connection...")}
  end

  defp parse_deploy_mode("test"), do: :test
  defp parse_deploy_mode("dry_activate"), do: :dry_activate
  defp parse_deploy_mode("build"), do: :build
  defp parse_deploy_mode(_), do: :switch

  # --- Graph management ---

  def handle_event("open_graph_manager", _params, socket) do
    graph_list = Store.list_graphs(store(socket))

    {:noreply,
     socket
     |> assign(:show_graph_manager, true)
     |> assign(:graph_list, graph_list)}
  end

  def handle_event("close_graph_manager", _params, socket) do
    {:noreply, assign(socket, :show_graph_manager, false)}
  end

  def handle_event("load_graph_file", %{"filename" => filename}, socket) do
    case Store.load_graph(store(socket), filename) do
      {:ok, graph} ->
        root = Graph.root_subgraph(graph)

        {:noreply,
         socket
         |> assign(:graph, graph)
         |> assign(:subgraph, root)
         |> assign(:breadcrumb, [{root.id, root.name}])
         |> assign(:selected_node_id, nil)
         |> assign(:show_graph_manager, false)
         |> assign(:current_file, filename)}

      _ ->
        {:noreply, put_flash(socket, :error, "Failed to load graph")}
    end
  end

  def handle_event("new_graph_submit", %{"name" => name}, socket) when name != "" do
    {:ok, graph, filename} = Store.new_graph(store(socket), name)
    root = Graph.root_subgraph(graph)

    {:noreply,
     socket
     |> assign(:graph, graph)
     |> assign(:subgraph, root)
     |> assign(:breadcrumb, [{root.id, root.name}])
     |> assign(:selected_node_id, nil)
     |> assign(:show_graph_manager, false)
     |> assign(:current_file, filename)}
  end

  def handle_event("new_graph_submit", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("save_as_submit", %{"name" => name}, socket) when name != "" do
    {:ok, filename} = Store.save_as(store(socket), name)

    {:noreply,
     socket
     |> assign(:current_file, filename)
     |> assign(:show_graph_manager, false)
     |> put_flash(:info, "Saved as #{filename}")}
  end

  def handle_event("save_as_submit", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("delete_graph_file", %{"filename" => filename}, socket) do
    Store.delete_graph(store(socket), filename)
    graph_list = Store.list_graphs(store(socket))
    {:noreply, assign(socket, :graph_list, graph_list)}
  end

  # --- OODN ---

  def handle_event("select_oodn", _params, socket) do
    {:noreply, assign(socket, :editing_oodn, true)}
  end

  def handle_event("close_oodn_editor", _params, socket) do
    {:noreply, assign(socket, :editing_oodn, false)}
  end

  def handle_event("add_oodn", %{"key" => key, "value" => value}, socket) do
    Store.put_oodn(store(socket), key, value)
    {:noreply, socket}
  end

  def handle_event("update_oodn", %{"oodn-id" => oodn_id, "value" => value}, socket) do
    Store.update_oodn(store(socket), oodn_id, value)
    {:noreply, socket}
  end

  def handle_event("remove_oodn", %{"oodn-id" => oodn_id}, socket) do
    Store.remove_oodn(store(socket), oodn_id)
    {:noreply, socket}
  end

  def handle_event("oodn_moved", %{"x" => x, "y" => y}, socket) do
    Store.move_oodn(store(socket), %{x: x, y: y})
    {:noreply, socket}
  end

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
