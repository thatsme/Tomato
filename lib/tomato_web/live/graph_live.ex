defmodule TomatoWeb.GraphLive do
  @moduledoc "Main LiveView for the graph editor."
  use TomatoWeb, :live_view

  import TomatoWeb.GraphLive.CanvasComponents
  import TomatoWeb.GraphLive.ModalComponents
  import TomatoWeb.GraphLive.SidebarComponents

  alias Tomato.{Store, Graph}
  alias TomatoWeb.GraphLive.NodeHandlers

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

  def handle_event("delete_edge", %{"edge-id" => edge_id}, socket) do
    Store.remove_edge(store(socket), socket.assigns.subgraph.id, edge_id)
    {:noreply, socket}
  end

  def handle_event("start_connect", %{"node-id" => node_id}, socket) do
    {:noreply, assign(socket, :connecting_from, node_id)}
  end

  def handle_event("cancel_connect", _params, socket) do
    {:noreply, assign(socket, :connecting_from, nil)}
  end

  def handle_event("enter_gateway", %{"node-id" => node_id}, socket) do
    sg = socket.assigns.subgraph
    node = Map.get(sg.nodes, node_id)

    if node && node.type == :gateway && node.subgraph_id do
      child_sg = Graph.get_subgraph(socket.assigns.graph, node.subgraph_id)

      if child_sg do
        breadcrumb = socket.assigns.breadcrumb ++ [{child_sg.id, child_sg.name}]

        {:noreply,
         socket
         |> assign(:subgraph, child_sg)
         |> assign(:breadcrumb, breadcrumb)
         |> assign(:selected_node_id, nil)
         |> assign(:editing_content_node_id, nil)}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("navigate_breadcrumb", %{"subgraph-id" => sg_id}, socket) do
    subgraph = Graph.get_subgraph(socket.assigns.graph, sg_id)

    if subgraph do
      breadcrumb =
        Enum.take_while(socket.assigns.breadcrumb, fn {id, _} -> id != sg_id end) ++
          [{sg_id, subgraph.name}]

      {:noreply,
       socket
       |> assign(:subgraph, subgraph)
       |> assign(:breadcrumb, breadcrumb)
       |> assign(:selected_node_id, nil)
       |> assign(:editing_content_node_id, nil)}
    else
      {:noreply, socket}
    end
  end

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

  def handle_event("search_nodes", %{"q" => query}, socket) do
    results =
      if String.trim(query) == "" do
        []
      else
        search_graph(socket.assigns.graph, query)
      end

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:search_results, results)}
  end

  def handle_event("goto_search_result", %{"subgraph-id" => sg_id, "node-id" => node_id}, socket) do
    subgraph = Graph.get_subgraph(socket.assigns.graph, sg_id)

    if subgraph do
      breadcrumb = build_breadcrumb_to(socket.assigns.graph, sg_id)

      {:noreply,
       socket
       |> assign(:subgraph, subgraph)
       |> assign(:breadcrumb, breadcrumb)
       |> assign(:selected_node_id, node_id)
       |> assign(:search_query, "")
       |> assign(:search_results, [])}
    else
      {:noreply, socket}
    end
  end

  defp search_graph(graph, query) do
    q = String.downcase(query)

    graph.subgraphs
    |> Enum.flat_map(fn {sg_id, sg} ->
      sg.nodes
      |> Enum.filter(fn {_id, node} -> matches_search?(node, q) end)
      |> Enum.map(fn {_id, node} ->
        %{node: node, subgraph_id: sg_id, subgraph_name: sg.name}
      end)
    end)
    |> Enum.take(50)
  end

  defp matches_search?(node, q) do
    String.contains?(String.downcase(node.name), q) ||
      (is_binary(node.content) && String.contains?(String.downcase(node.content), q))
  end

  defp build_breadcrumb_to(graph, target_sg_id) do
    # Walk from root looking for path to target subgraph
    root_id = graph.root_subgraph_id
    root = graph.subgraphs[root_id]
    initial = [{root_id, root.name}]

    case find_path(graph, root, target_sg_id, initial) do
      nil -> initial
      path -> path
    end
  end

  defp find_path(_graph, sg, target_id, acc) when sg.id == target_id, do: acc

  defp find_path(graph, sg, target_id, acc) do
    sg.nodes
    |> Map.values()
    |> Enum.find_value(fn node ->
      if node.type == :gateway && is_binary(node.subgraph_id) do
        case Graph.get_subgraph(graph, node.subgraph_id) do
          nil ->
            nil

          child_sg ->
            new_acc = acc ++ [{child_sg.id, child_sg.name}]

            cond do
              child_sg.id == target_id -> new_acc
              true -> find_path(graph, child_sg, target_id, new_acc)
            end
        end
      end
    end)
  end

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

  def handle_event("start_connect_to", %{"node-id" => node_id}, socket) do
    {:noreply, assign(socket, :connecting_to, node_id)}
  end

  def handle_event("duplicate_node", params, socket),
    do: NodeHandlers.duplicate(params, socket)

  def handle_event("disconnect_node", %{"node-id" => node_id}, socket) do
    sg = socket.assigns.subgraph

    sg.edges
    |> Enum.filter(fn {_id, edge} -> edge.from == node_id or edge.to == node_id end)
    |> Enum.each(fn {edge_id, _edge} ->
      Store.remove_edge(store(socket), sg.id, edge_id)
    end)

    {:noreply, socket}
  end

  def handle_event("reverse_edge", %{"edge-id" => edge_id}, socket) do
    sg = socket.assigns.subgraph

    case Map.get(sg.edges, edge_id) do
      nil ->
        {:noreply, socket}

      edge ->
        Store.remove_edge(store(socket), sg.id, edge_id)
        Store.add_edge(store(socket), sg.id, edge.to, edge.from)
        {:noreply, socket}
    end
  end

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
