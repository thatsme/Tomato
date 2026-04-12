defmodule TomatoWeb.GraphLive do
  @moduledoc "Main LiveView for the graph editor."
  use TomatoWeb, :live_view

  alias Tomato.{Store, Graph}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tomato.PubSub, "graph:updates")
    end

    graph = Store.get_graph()
    root_id = graph.root_subgraph_id
    subgraph = Graph.get_subgraph(graph, root_id)

    {:ok,
     socket
     |> assign(:graph, graph)
     |> assign(:subgraph, subgraph)
     |> assign(:breadcrumb, [{root_id, subgraph.name}])
     |> assign(:selected_node_id, nil)
     |> assign(:connecting_from, nil)
     |> assign(:connecting_to, nil)
     |> assign(:editing_content_node_id, nil)
     |> assign(:editing_oodn, false)
     |> assign(:show_template_picker, false)
     |> assign(:show_generated, false)
     |> assign(:generated_output, "")
     |> assign(:generated_path, nil)
     |> assign(:deploy_status, nil)
     |> assign(:deploy_output, "")
     |> assign(:show_graph_manager, false)
     |> assign(:graph_list, [])
     |> assign(:current_file, Store.current_file())
     |> assign(:page_title, "Graph Editor")}
  end

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

  def handle_info({:graph_updated, graph}, socket) do
    subgraph = Graph.get_subgraph(graph, socket.assigns.subgraph.id)

    {:noreply,
     socket
     |> assign(:graph, graph)
     |> assign(:subgraph, subgraph || socket.assigns.subgraph)}
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
            Store.add_gateway(sg.id,
              name: template.name,
              position: %{x: 300, y: y}
            )

          children = Map.get(template, :children, [])
          child_sg = Store.get_subgraph(child.id)
          child_input = Tomato.Subgraph.input_node(child_sg)
          child_output = Tomato.Subgraph.output_node(child_sg)

          # Create each child leaf and wire input -> leaf -> output
          children
          |> Enum.with_index()
          |> Enum.each(fn {child_tmpl, idx} ->
            {:ok, leaf} =
              Store.add_node(child.id,
                type: :leaf,
                name: child_tmpl.name,
                content: String.trim(child_tmpl.content),
                position: %{x: 150 + idx * 180, y: 200}
              )

            Store.add_edge(child.id, child_input.id, leaf.id)
            Store.add_edge(child.id, leaf.id, child_output.id)
          end)

          {:noreply,
           socket
           |> assign(:show_template_picker, false)
           |> assign(:selected_node_id, gw.id)}

        _ ->
          # Simple leaf node
          {:ok, node} =
            Store.add_node(sg.id,
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

  def handle_event("add_leaf", _params, socket) do
    sg = socket.assigns.subgraph
    node_count = map_size(sg.nodes)
    y = 100 + node_count * 80

    {:ok, _node} =
      Store.add_node(sg.id,
        type: :leaf,
        name: "Node #{node_count - 1}",
        position: %{x: 300, y: y}
      )

    {:noreply, socket}
  end

  def handle_event("add_gateway", _params, socket) do
    sg = socket.assigns.subgraph
    node_count = map_size(sg.nodes)
    y = 100 + node_count * 80

    {:ok, _gateway, _child_sg} =
      Store.add_gateway(sg.id, name: "Gateway #{node_count - 1}", position: %{x: 300, y: y})

    {:noreply, socket}
  end

  def handle_event("add_node_at", %{"type" => type, "x" => x, "y" => y}, socket) do
    sg = socket.assigns.subgraph
    node_count = map_size(sg.nodes)

    case type do
      "leaf" ->
        {:ok, _node} =
          Store.add_node(sg.id,
            type: :leaf,
            name: "Node #{node_count - 1}",
            position: %{x: x, y: y}
          )

        {:noreply, socket}

      "gateway" ->
        {:ok, _gw, _child} =
          Store.add_gateway(sg.id, name: "Gateway #{node_count - 1}", position: %{x: x, y: y})

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("select_node", %{"node-id" => node_id}, socket) do
    cond do
      socket.assigns.connecting_from ->
        from_id = socket.assigns.connecting_from

        if from_id != node_id do
          Store.add_edge(socket.assigns.subgraph.id, from_id, node_id)
        end

        {:noreply, assign(socket, :connecting_from, nil)}

      socket.assigns[:connecting_to] ->
        to_id = socket.assigns.connecting_to

        if to_id != node_id do
          Store.add_edge(socket.assigns.subgraph.id, node_id, to_id)
        end

        {:noreply, assign(socket, :connecting_to, nil)}

      true ->
        {:noreply, assign(socket, :selected_node_id, node_id)}
    end
  end

  def handle_event("deselect", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_node_id, nil)
     |> assign(:connecting_from, nil)
     |> assign(:connecting_to, nil)}
  end

  def handle_event("delete_node", %{"node-id" => node_id}, socket) do
    Store.remove_node(socket.assigns.subgraph.id, node_id)

    {:noreply,
     socket
     |> assign(:selected_node_id, nil)
     |> assign(:editing_content_node_id, nil)}
  end

  def handle_event("delete_edge", %{"edge-id" => edge_id}, socket) do
    Store.remove_edge(socket.assigns.subgraph.id, edge_id)
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

  def handle_event("node_moved", %{"node_id" => node_id, "x" => x, "y" => y}, socket) do
    Store.update_node(socket.assigns.subgraph.id, node_id, position: %{x: x, y: y})
    {:noreply, socket}
  end

  def handle_event("rename_node", %{"node-id" => node_id, "name" => name}, socket) do
    Store.update_node(socket.assigns.subgraph.id, node_id, name: name)
    {:noreply, socket}
  end

  # --- Content editing ---

  def handle_event("edit_node_content", %{"node-id" => node_id}, socket) do
    {:noreply,
     socket
     |> assign(:editing_content_node_id, node_id)
     |> assign(:selected_node_id, node_id)}
  end

  def handle_event("save_content", %{"node-id" => node_id, "content" => content}, socket) do
    Store.update_node(socket.assigns.subgraph.id, node_id, content: content)
    {:noreply, assign(socket, :editing_content_node_id, nil)}
  end

  def handle_event("close_editor", _params, socket) do
    {:noreply, assign(socket, :editing_content_node_id, nil)}
  end

  # --- Backend toggle ---

  def handle_event("toggle_backend", _params, socket) do
    new_backend = if socket.assigns.graph.backend == :flake, do: :traditional, else: :flake
    Store.set_backend(new_backend)
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

  def handle_event("reconfigure", _params, socket) do
    nix_path = socket.assigns.generated_path

    if nix_path && File.exists?(nix_path) do
      # Run deploy asynchronously
      pid = self()

      Task.Supervisor.start_child(Tomato.TaskSupervisor, fn ->
        result = Tomato.Deploy.deploy(nix_path)
        send(pid, {:deploy_result, result})
      end)

      {:noreply,
       socket
       |> assign(:deploy_status, "running")
       |> assign(:deploy_output, "Connecting to NixOS machine...")}
    else
      {:noreply,
       socket
       |> assign(:deploy_status, "error")
       |> assign(:deploy_output, "No .nix file generated yet. Click Generate first.")}
    end
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

  # --- Graph management ---

  def handle_event("open_graph_manager", _params, socket) do
    graph_list = Store.list_graphs()

    {:noreply,
     socket
     |> assign(:show_graph_manager, true)
     |> assign(:graph_list, graph_list)}
  end

  def handle_event("close_graph_manager", _params, socket) do
    {:noreply, assign(socket, :show_graph_manager, false)}
  end

  def handle_event("load_graph_file", %{"filename" => filename}, socket) do
    case Store.load_graph(filename) do
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
    {:ok, graph, filename} = Store.new_graph(name)
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
    {:ok, filename} = Store.save_as(name)

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
    Store.delete_graph(filename)
    graph_list = Store.list_graphs()
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
    Store.put_oodn(key, value)
    {:noreply, socket}
  end

  def handle_event("update_oodn", %{"oodn-id" => oodn_id, "value" => value}, socket) do
    Store.update_oodn(oodn_id, value)
    {:noreply, socket}
  end

  def handle_event("remove_oodn", %{"oodn-id" => oodn_id}, socket) do
    Store.remove_oodn(oodn_id)
    {:noreply, socket}
  end

  def handle_event("oodn_moved", %{"x" => x, "y" => y}, socket) do
    Store.move_oodn(%{x: x, y: y})
    {:noreply, socket}
  end

  # --- Context menu actions ---

  def handle_event("start_connect_to", %{"node-id" => node_id}, socket) do
    {:noreply, assign(socket, :connecting_to, node_id)}
  end

  def handle_event("duplicate_node", %{"node-id" => node_id}, socket) do
    sg = socket.assigns.subgraph
    node = Map.get(sg.nodes, node_id)

    if node do
      {:ok, _new_node} =
        Store.add_node(sg.id,
          type: node.type,
          name: node.name <> " (copy)",
          content: node.content,
          position: %{x: node.position.x + 40, y: node.position.y + 40}
        )
    end

    {:noreply, socket}
  end

  def handle_event("disconnect_node", %{"node-id" => node_id}, socket) do
    sg = socket.assigns.subgraph

    sg.edges
    |> Enum.filter(fn {_id, edge} -> edge.from == node_id or edge.to == node_id end)
    |> Enum.each(fn {edge_id, _edge} ->
      Store.remove_edge(sg.id, edge_id)
    end)

    {:noreply, socket}
  end

  def handle_event("reverse_edge", %{"edge-id" => edge_id}, socket) do
    sg = socket.assigns.subgraph

    case Map.get(sg.edges, edge_id) do
      nil ->
        {:noreply, socket}

      edge ->
        Store.remove_edge(sg.id, edge_id)
        Store.add_edge(sg.id, edge.to, edge.from)
        {:noreply, socket}
    end
  end

  def handle_event("start_rename", %{"node-id" => node_id}, socket) do
    {:noreply, assign(socket, :selected_node_id, node_id)}
  end

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
        <%!-- Header --%>
        <div class="p-3 border-b border-base-300">
          <div class="flex items-center gap-2">
            <span class="text-lg font-bold text-primary">Tomato</span>
            <span class="text-xs text-base-content/40">v0.1</span>
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
                @graph.backend == :flake && "btn-info",
                @graph.backend != :flake && "btn-ghost"
              ]}
              phx-click="toggle_backend"
              title="Switch between Traditional and Flake output"
            >
              {if @graph.backend == :flake, do: "Flake", else: "Traditional"}
            </button>
            <button class="btn btn-xs btn-accent" phx-click="generate">
              Generate
            </button>
          </div>
        </div>

        <%!-- Breadcrumb --%>
        <div class="p-3 border-b border-base-300">
          <div class="text-xs text-base-content/60 mb-1">Floor {@subgraph.floor}</div>
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

        <%!-- Toolbar --%>
        <div class="p-3 border-b border-base-300 space-y-2">
          <button class="btn btn-sm btn-primary w-full" phx-click="show_template_picker">
            + Add Node
          </button>
          <button class="btn btn-sm btn-secondary w-full" phx-click="add_gateway">
            + Gateway
          </button>
        </div>

        <%!-- Node List --%>
        <div class="flex-1 overflow-y-auto p-3">
          <h3 class="text-xs font-semibold text-base-content/60 mb-2 uppercase">Nodes</h3>
          <div class="space-y-1">
            <div
              :for={{_id, node} <- @subgraph.nodes}
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

        <%!-- Selected Node Panel --%>
        <div
          :if={@selected_node_id && Map.get(@subgraph.nodes, @selected_node_id)}
          class="border-t border-base-300 p-3"
        >
          <% node = Map.get(@subgraph.nodes, @selected_node_id) %>
          <h3 class="text-xs font-semibold text-base-content/60 mb-2 uppercase">Properties</h3>
          <div class="space-y-2">
            <div>
              <label class="text-xs text-base-content/60">Name</label>
              <form phx-submit="rename_node" phx-value-node-id={node.id}>
                <input
                  type="text"
                  name="name"
                  value={node.name}
                  class="input input-sm input-bordered w-full"
                />
              </form>
            </div>
            <div class="text-xs text-base-content/50">Type: {node.type}</div>
            <div class="flex flex-wrap gap-2">
              <button
                :if={node.type == :leaf}
                class="btn btn-xs btn-info"
                phx-click="edit_node_content"
                phx-value-node-id={node.id}
              >
                Edit Content
              </button>
              <button
                :if={node.type not in [:input, :output]}
                class="btn btn-xs btn-error"
                phx-click="delete_node"
                phx-value-node-id={node.id}
              >
                Delete
              </button>
              <button
                class="btn btn-xs btn-outline"
                phx-click="start_connect"
                phx-value-node-id={node.id}
              >
                Connect
              </button>
              <button
                :if={node.type == :gateway}
                class="btn btn-xs btn-accent"
                phx-click="enter_gateway"
                phx-value-node-id={node.id}
              >
                Enter
              </button>
            </div>
          </div>
        </div>
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
        <div class="absolute bottom-4 right-4 z-10 text-xs text-base-content/30 space-y-0.5 text-right">
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

  # --- SVG Components ---

  attr :node, :map, required: true
  attr :selected, :boolean, default: false
  attr :connecting, :boolean, default: false

  defp graph_node(assigns) do
    ~H"""
    <g
      class="graph-node cursor-grab active:cursor-grabbing"
      data-node-id={@node.id}
      data-node-type={@node.type}
      data-node-name={@node.name}
      transform={"translate(#{@node.position.x}, #{@node.position.y})"}
      phx-click="select_node"
      phx-value-node-id={@node.id}
    >
      <rect
        x="-60"
        y="-20"
        width="120"
        height="40"
        rx="6"
        class={[
          "stroke-2 transition-colors",
          node_rect_class(@node.type, @selected)
        ]}
      />
      <%!-- Gateway indicator --%>
      <circle
        :if={@node.type == :gateway}
        cx="-42"
        cy="0"
        r="6"
        class="fill-secondary/30 stroke-secondary"
        stroke-width="1.5"
      />
      <%!-- Content indicator for leaf nodes --%>
      <circle
        :if={@node.type == :leaf && has_content?(@node)}
        cx="42"
        cy="-10"
        r="4"
        class="fill-success stroke-success/50"
        stroke-width="1"
      />
      <text
        text-anchor="middle"
        dominant-baseline="central"
        class={["text-xs select-none pointer-events-none", node_text_class(@selected)]}
      >
        {@node.name}
      </text>
    </g>
    """
  end

  attr :edge, :map, required: true
  attr :nodes, :map, required: true

  defp edge_line(assigns) do
    from_node = Map.get(assigns.nodes, assigns.edge.from)
    to_node = Map.get(assigns.nodes, assigns.edge.to)

    path_d =
      if from_node && to_node do
        x1 = from_node.position.x + 60
        y1 = from_node.position.y
        x2 = to_node.position.x - 60
        y2 = to_node.position.y
        dx = abs(x2 - x1)
        offset = max(dx * 0.5, 80)
        "M #{x1} #{y1} C #{x1 + offset} #{y1}, #{x2 - offset} #{y2}, #{x2} #{y2}"
      end

    assigns =
      assigns
      |> assign(:from_node, from_node)
      |> assign(:to_node, to_node)
      |> assign(:path_d, path_d)

    ~H"""
    <path
      :if={@from_node && @to_node}
      d={@path_d}
      data-edge-id={@edge.id}
      data-from={@edge.from}
      data-to={@edge.to}
      fill="none"
      class="stroke-base-content/30 stroke-2 hover:stroke-primary cursor-pointer"
      marker-end="url(#arrowhead)"
      phx-click="delete_edge"
      phx-value-edge-id={@edge.id}
    />
    """
  end

  # --- Template Picker ---

  defp template_picker(assigns) do
    categories = Tomato.TemplateLibrary.by_category()
    assigns = assign(assigns, :categories, categories)

    ~H"""
    <div class="fixed inset-0 z-40 overflow-y-auto">
      <div class="fixed inset-0 bg-black/50" phx-click="close_template_picker" />
      <div class="flex min-h-full items-center justify-center p-4">
        <div class="relative bg-base-100 rounded-lg shadow-2xl w-[600px] max-h-[80vh] flex flex-col">
          <div class="flex items-center justify-between p-4 border-b border-base-300 shrink-0">
            <div>
              <h2 class="font-semibold">Add Node from Template</h2>
              <p class="text-xs text-base-content/50">Pick a predefined NixOS configuration</p>
            </div>
            <button class="btn btn-sm btn-ghost" phx-click="close_template_picker">X</button>
          </div>

          <div class="flex-1 min-h-0 overflow-y-auto p-4 space-y-4">
            <div :for={{category, templates} <- @categories}>
              <h3 class="text-xs font-semibold text-base-content/50 uppercase mb-2">{category}</h3>
              <div class="grid grid-cols-2 gap-2">
                <button
                  :for={t <- templates}
                  class={[
                    "flex flex-col items-start p-3 rounded-lg border transition-colors cursor-pointer text-left",
                    Map.get(t, :type) == :gateway &&
                      "border-secondary/40 hover:border-secondary hover:bg-secondary/5",
                    Map.get(t, :type) != :gateway &&
                      "border-base-300 hover:border-primary hover:bg-primary/5"
                  ]}
                  phx-click="add_from_template"
                  phx-value-template-id={t.id}
                >
                  <div class="flex items-center gap-2">
                    <span :if={Map.get(t, :type) == :gateway} class="badge badge-xs badge-secondary">
                      stack
                    </span>
                    <span class="font-medium text-sm">{t.name}</span>
                  </div>
                  <span class="text-xs text-base-content/50 mt-0.5">{t.description}</span>
                  <div :if={Map.get(t, :children)} class="text-xs text-base-content/40 mt-1">
                    {length(Map.get(t, :children, []))} nodes inside
                  </div>
                  <div :if={t.oodn_keys != []} class="flex gap-1 mt-1.5 flex-wrap">
                    <span
                      :for={key <- t.oodn_keys}
                      class="badge badge-xs badge-warning font-mono"
                    >
                      {"${" <> key <> "}"}
                    </span>
                  </div>
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- OODN Node ---

  attr :oodn_registry, :map, required: true
  attr :position, :map, required: true

  defp oodn_node(assigns) do
    entries = assigns.oodn_registry |> Map.values() |> Enum.sort_by(& &1.key)
    row_height = 20
    header_height = 32
    padding = 10
    width = 220
    height = header_height + padding + max(length(entries), 1) * row_height + padding

    assigns =
      assign(assigns,
        entries: entries,
        width: width,
        height: height,
        row_height: row_height,
        header_height: header_height,
        padding: padding
      )

    ~H"""
    <g
      class="oodn-node cursor-grab active:cursor-grabbing"
      data-node-id="oodn"
      data-node-type="oodn"
      data-node-name="Config"
      transform={"translate(#{@position.x}, #{@position.y})"}
      phx-click="select_oodn"
    >
      <%!-- Shadow --%>
      <rect x="2" y="2" width={@width} height={@height} rx="6" fill="black" opacity="0.08" />

      <%!-- Body --%>
      <rect
        x="0"
        y="0"
        width={@width}
        height={@height}
        rx="6"
        fill="#fef9c3"
        stroke="#eab308"
        stroke-width="2"
      />

      <%!-- Header --%>
      <rect x="0" y="0" width={@width} height={@header_height} rx="6" fill="#eab308" opacity="0.25" />
      <rect x="0" y={@header_height - 4} width={@width} height="4" fill="#eab308" opacity="0.25" />

      <%!-- Header icon --%>
      <text
        x="10"
        y={@header_height / 2 + 1}
        dominant-baseline="central"
        font-size="14"
        class="select-none pointer-events-none"
      >
        &#9881;
      </text>
      <text
        x="28"
        y={@header_height / 2}
        dominant-baseline="central"
        font-size="12"
        font-weight="bold"
        fill="#92400e"
        class="select-none pointer-events-none"
      >
        OODN Config
      </text>
      <text
        x={@width - 10}
        y={@header_height / 2}
        dominant-baseline="central"
        text-anchor="end"
        font-size="10"
        fill="#92400e"
        opacity="0.5"
        class="select-none pointer-events-none"
      >
        {length(@entries)}
      </text>

      <%!-- Separator line --%>
      <line
        x1="8"
        y1={@header_height + 2}
        x2={@width - 8}
        y2={@header_height + 2}
        stroke="#eab308"
        opacity="0.3"
      />

      <%!-- Key-value rows --%>
      <g :for={{entry, idx} <- Enum.with_index(@entries)}>
        <%!-- Row background on hover --%>
        <rect
          x="4"
          y={@header_height + @padding + idx * @row_height - 2}
          width={@width - 8}
          height={@row_height - 2}
          rx="3"
          fill="#eab308"
          opacity="0.05"
        />
        <text
          x="10"
          y={@header_height + @padding + idx * @row_height + 12}
          font-size="11"
          font-family="monospace"
          fill="#78350f"
          class="select-none pointer-events-none"
        >
          {entry.key}
        </text>
        <text
          x={@width - 10}
          y={@header_height + @padding + idx * @row_height + 12}
          text-anchor="end"
          font-size="11"
          font-family="monospace"
          fill="#a16207"
          class="select-none pointer-events-none"
        >
          {truncate_value(entry.value, 14)}
        </text>
      </g>

      <%!-- Empty state --%>
      <text
        :if={@entries == []}
        x={@width / 2}
        y={@header_height + @padding + 12}
        text-anchor="middle"
        font-size="11"
        fill="#a16207"
        opacity="0.4"
        class="select-none pointer-events-none"
      >
        Double-click to add variables
      </text>
    </g>
    """
  end

  defp truncate_value(v, max) when byte_size(v) > max, do: String.slice(v, 0, max) <> ".."
  defp truncate_value(v, _max), do: v

  # --- OODN Editor ---

  attr :oodn_registry, :map, required: true

  defp oodn_editor(assigns) do
    entries = assigns.oodn_registry |> Map.values() |> Enum.sort_by(& &1.key)
    assigns = assign(assigns, :entries, entries)

    ~H"""
    <div class="fixed inset-0 z-40 overflow-y-auto">
      <div class="fixed inset-0 bg-black/50" phx-click="close_oodn_editor" />
      <div class="flex min-h-full items-center justify-center p-4">
        <div class="relative bg-base-100 rounded-lg shadow-2xl w-[500px] max-h-[80vh] flex flex-col">
          <div class="flex items-center justify-between p-4 border-b border-base-300">
            <div>
              <h2 class="font-semibold">OODN Config</h2>
              <p class="text-xs text-base-content/50">
                Global variables — use ${"{key}"} in leaf nodes
              </p>
            </div>
            <button class="btn btn-sm btn-ghost" phx-click="close_oodn_editor">X</button>
          </div>

          <div class="flex-1 overflow-y-auto p-4 space-y-2">
            <div
              :for={entry <- @entries}
              class="flex items-center gap-2"
            >
              <span class="font-mono text-sm font-semibold w-32 shrink-0 truncate" title={entry.key}>
                {entry.key}
              </span>
              <form phx-submit="update_oodn" phx-value-oodn-id={entry.id} class="flex-1 flex gap-1">
                <input
                  type="text"
                  name="value"
                  value={entry.value}
                  class="input input-sm input-bordered flex-1 font-mono"
                />
                <button type="submit" class="btn btn-sm btn-ghost">Save</button>
              </form>
              <button
                class="btn btn-sm btn-ghost text-error"
                phx-click="remove_oodn"
                phx-value-oodn-id={entry.id}
              >
                x
              </button>
            </div>
          </div>

          <div class="p-4 border-t border-base-300">
            <form phx-submit="add_oodn" class="flex gap-2">
              <input
                type="text"
                name="key"
                placeholder="key"
                class="input input-sm input-bordered w-32 font-mono"
                required
              />
              <input
                type="text"
                name="value"
                placeholder="value"
                class="input input-sm input-bordered flex-1 font-mono"
                required
              />
              <button type="submit" class="btn btn-sm btn-warning">Add</button>
            </form>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Content Editor ---

  attr :node, :map, required: true

  defp content_editor(assigns) do
    ~H"""
    <div class="fixed inset-0 z-40 overflow-y-auto">
      <div class="fixed inset-0 bg-black/50" phx-click="close_editor" />
      <div class="flex min-h-full items-center justify-center p-4">
        <div class="relative bg-base-100 rounded-lg shadow-2xl w-[700px] max-h-[80vh] flex flex-col">
          <div class="flex items-center justify-between p-4 border-b border-base-300">
            <div>
              <h2 class="font-semibold">{@node.name}</h2>
              <p class="text-xs text-base-content/50">Nix configuration fragment</p>
            </div>
            <button class="btn btn-sm btn-ghost" phx-click="close_editor">X</button>
          </div>
          <form
            phx-submit="save_content"
            phx-value-node-id={@node.id}
            class="flex flex-col flex-1 min-h-0"
          >
            <div class="flex-1 p-4 min-h-0">
              <textarea
                name="content"
                class="textarea textarea-bordered w-full h-full min-h-[300px] font-mono text-sm"
                placeholder={"# Nix config for #{@node.name}\n# e.g.:\n# services.openssh.enable = true;\n# services.openssh.settings.PermitRootLogin = \"no\";"}
                phx-debounce="500"
              >{@node.content || ""}</textarea>
            </div>
            <div class="flex justify-end gap-2 p-4 border-t border-base-300">
              <button type="button" class="btn btn-sm btn-ghost" phx-click="close_editor">
                Cancel
              </button>
              <button type="submit" class="btn btn-sm btn-primary">Save</button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  # --- Generated Output ---

  attr :output, :string, required: true
  attr :path, :string, default: nil
  attr :deploy_status, :string, default: nil
  attr :deploy_output, :string, default: nil

  defp generated_output(assigns) do
    ~H"""
    <div class="fixed inset-0 z-40 overflow-y-auto">
      <div class="fixed inset-0 bg-black/50" phx-click="close_generated" />
      <div class="flex min-h-full items-center justify-center p-4">
        <div class="relative bg-base-100 rounded-lg shadow-2xl w-[800px] max-h-[85vh] flex flex-col">
          <div class="flex items-center justify-between p-4 border-b border-base-300 shrink-0">
            <div>
              <h2 class="font-semibold">Generated Output</h2>
              <p :if={@path} class="text-xs text-success">Saved to: {@path}</p>
            </div>
            <button class="btn btn-sm btn-ghost" phx-click="close_generated">X</button>
          </div>

          <%!-- Scrollable content area --%>
          <div class="flex-1 min-h-0 overflow-y-auto p-4 space-y-4">
            <pre class="bg-base-200 rounded-lg p-4 text-sm font-mono whitespace-pre overflow-x-auto"><code>{@output}</code></pre>

            <%!-- Deploy status inside scroll area --%>
            <div
              :if={@deploy_status}
              class={[
                "rounded-lg p-3 text-sm font-mono whitespace-pre-wrap",
                @deploy_status == "running" && "bg-info/10 text-info",
                @deploy_status == "success" && "bg-success/10 text-success",
                @deploy_status == "error" && "bg-error/10 text-error"
              ]}
            >
              <div class="font-semibold mb-1">
                <span :if={@deploy_status == "running"}>Deploying...</span>
                <span :if={@deploy_status == "success"}>Deploy successful</span>
                <span :if={@deploy_status == "error"}>Deploy failed</span>
              </div>
              <div :if={@deploy_output != ""}>{@deploy_output}</div>
            </div>
          </div>

          <%!-- Fixed footer --%>
          <div class="flex justify-end gap-2 p-4 border-t border-base-300 shrink-0">
            <button type="button" class="btn btn-sm btn-ghost" phx-click="close_generated">
              Close
            </button>
            <button
              type="button"
              class={["btn btn-sm btn-warning", @deploy_status == "running" && "btn-disabled loading"]}
              phx-click="reconfigure"
              disabled={@deploy_status == "running"}
            >
              Reconfigure NixOS
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Graph Manager ---

  attr :graph_list, :list, required: true
  attr :current_file, :string, default: nil

  defp graph_manager(assigns) do
    ~H"""
    <div class="fixed inset-0 z-40 overflow-y-auto">
      <div class="fixed inset-0 bg-black/50" phx-click="close_graph_manager" />
      <div class="flex min-h-full items-center justify-center p-4">
        <div class="relative bg-base-100 rounded-lg shadow-2xl w-[500px] max-h-[80vh] flex flex-col">
          <div class="flex items-center justify-between p-4 border-b border-base-300">
            <h2 class="font-semibold">Graph Manager</h2>
            <button class="btn btn-sm btn-ghost" phx-click="close_graph_manager">X</button>
          </div>

          <%!-- New graph --%>
          <div class="p-4 border-b border-base-300">
            <form phx-submit="new_graph_submit" class="flex gap-2">
              <input
                type="text"
                name="name"
                placeholder="New graph name..."
                class="input input-sm input-bordered flex-1"
                required
              />
              <button type="submit" class="btn btn-sm btn-primary">New</button>
            </form>
          </div>

          <%!-- Save As --%>
          <div class="px-4 py-3 border-b border-base-300">
            <form phx-submit="save_as_submit" class="flex gap-2">
              <input
                type="text"
                name="name"
                placeholder="Save current graph as..."
                class="input input-sm input-bordered flex-1"
                required
              />
              <button type="submit" class="btn btn-sm btn-secondary">Save As</button>
            </form>
          </div>

          <%!-- File list --%>
          <div class="flex-1 overflow-y-auto p-4">
            <h3 class="text-xs font-semibold text-base-content/60 mb-3 uppercase">Saved Graphs</h3>
            <div :if={@graph_list == []} class="text-sm text-base-content/40 text-center py-4">
              No saved graphs yet
            </div>
            <div class="space-y-1">
              <div
                :for={item <- @graph_list}
                class={[
                  "flex items-center gap-3 px-3 py-2 rounded",
                  item.filename == @current_file && "bg-primary/10 border border-primary/20",
                  item.filename != @current_file && "hover:bg-base-200"
                ]}
              >
                <div class="flex-1 min-w-0">
                  <div class="text-sm font-medium truncate">{item.name}</div>
                  <div class="text-xs text-base-content/40">{item.filename}</div>
                </div>
                <div class="flex gap-1 shrink-0">
                  <button
                    :if={item.filename != @current_file}
                    class="btn btn-xs btn-ghost"
                    phx-click="load_graph_file"
                    phx-value-filename={item.filename}
                  >
                    Load
                  </button>
                  <span :if={item.filename == @current_file} class="badge badge-xs badge-primary">
                    active
                  </span>
                  <button
                    :if={item.filename != @current_file}
                    class="btn btn-xs btn-ghost text-error"
                    phx-click="delete_graph_file"
                    phx-value-filename={item.filename}
                    data-confirm="Delete this graph?"
                  >
                    Del
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Helpers ---

  defp has_content?(%{content: c}) when is_binary(c) and c != "", do: true
  defp has_content?(_), do: false

  defp node_color(:input), do: "bg-success"
  defp node_color(:output), do: "bg-error"
  defp node_color(:leaf), do: "bg-info"
  defp node_color(:gateway), do: "bg-secondary"
  defp node_color(_), do: "bg-base-content/30"

  defp node_rect_class(:input, true), do: "fill-success/20 stroke-success"
  defp node_rect_class(:input, false), do: "fill-success/10 stroke-success/50"
  defp node_rect_class(:output, true), do: "fill-error/20 stroke-error"
  defp node_rect_class(:output, false), do: "fill-error/10 stroke-error/50"
  defp node_rect_class(:leaf, true), do: "fill-info/20 stroke-info"
  defp node_rect_class(:leaf, false), do: "fill-info/10 stroke-info/50"
  defp node_rect_class(:gateway, true), do: "fill-secondary/20 stroke-secondary"
  defp node_rect_class(:gateway, false), do: "fill-secondary/10 stroke-secondary/50"

  defp node_rect_class(_, selected),
    do:
      if(selected,
        do: "fill-base-300 stroke-base-content",
        else: "fill-base-200 stroke-base-content/30"
      )

  defp node_text_class(true), do: "fill-base-content font-semibold"
  defp node_text_class(false), do: "fill-base-content/70"
end
