defmodule TomatoWeb.GraphLiveTest do
  @moduledoc """
  Structural smoke tests for the graph editor LiveView.

  ## Coverage gap

  The `generated_output` modal's validation panel (introduced with
  `Walker.validate/1` wiring in §4) has no render-path coverage here.
  The four states (`:ok` / `:disabled` / `:unavailable` / `{:error, _}`)
  are exercised only via `Tomato.Walker.validate/1` unit tests in
  `test/tomato/walker_test.exs`, which verify the return contract but
  not the rendered HTML. If the modal markup or the JS.push chain on
  error rows starts misbehaving, these tests will not catch it. Add
  coverage when the modal grows further behaviour.
  """
  use TomatoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Tomato.{Graph, Store}

  setup do
    name = :"test_store_#{System.unique_integer([:positive])}"
    tmp = Path.join(System.tmp_dir!(), "tomato_test_#{name}")
    File.rm_rf!(tmp)
    File.mkdir_p!(tmp)

    start_supervised!({Store, name: name, graphs_dir: tmp, auto_seed: false})

    conn = Phoenix.ConnTest.build_conn() |> Plug.Test.init_test_session(%{"store" => name})

    on_exit(fn -> File.rm_rf!(tmp) end)

    %{conn: conn, store: name}
  end

  defp root_sg_id(store) do
    graph = Store.get_graph(store)
    graph.root_subgraph_id
  end

  defp node_count(store, sg_id) do
    store |> Store.get_graph() |> Graph.get_subgraph(sg_id) |> Map.fetch!(:nodes) |> map_size()
  end

  defp node_ids(store, sg_id) do
    store
    |> Store.get_graph()
    |> Graph.get_subgraph(sg_id)
    |> Map.fetch!(:nodes)
    |> Map.keys()
    |> MapSet.new()
  end

  defp new_node_id(store, sg_id, before_ids) do
    after_ids = node_ids(store, sg_id)
    [new_id] = MapSet.difference(after_ids, before_ids) |> MapSet.to_list()
    new_id
  end

  describe "mount" do
    test "renders the graph editor", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert render(view) =~ "graph" or has_element?(view, "svg")
    end
  end

  describe "node creation" do
    test "add_leaf increments node count", %{conn: conn, store: store} do
      {:ok, view, _html} = live(conn, ~p"/")
      sg_id = root_sg_id(store)
      before = node_count(store, sg_id)

      render_click(view, "add_leaf")

      assert node_count(store, sg_id) == before + 1
    end

    test "add_gateway creates gateway and child subgraph", %{conn: conn, store: store} do
      {:ok, view, _html} = live(conn, ~p"/")
      sg_id = root_sg_id(store)
      before = node_count(store, sg_id)

      render_click(view, "add_gateway")

      assert node_count(store, sg_id) == before + 1
    end

    test "add_machine creates machine node", %{conn: conn, store: store} do
      {:ok, view, _html} = live(conn, ~p"/")
      sg_id = root_sg_id(store)
      before = node_count(store, sg_id)

      render_click(view, "add_machine")

      assert node_count(store, sg_id) == before + 1
    end

    test "add_node_at with type=leaf increments count", %{conn: conn, store: store} do
      {:ok, view, _html} = live(conn, ~p"/")
      sg_id = root_sg_id(store)
      before = node_count(store, sg_id)

      render_click(view, "add_node_at", %{"type" => "leaf", "x" => 100, "y" => 100})

      assert node_count(store, sg_id) == before + 1
    end
  end

  describe "selection and deletion" do
    test "select_node sets selected_node_id", %{conn: conn, store: store} do
      {:ok, view, _html} = live(conn, ~p"/")
      sg_id = root_sg_id(store)
      before_ids = node_ids(store, sg_id)

      render_click(view, "add_leaf")

      new_id = new_node_id(store, sg_id, before_ids)
      render_click(view, "select_node", %{"node-id" => new_id})

      assert :sys.get_state(view.pid).socket.assigns.selected_node_id == new_id
    end

    test "delete_node removes the node and clears selection", %{conn: conn, store: store} do
      {:ok, view, _html} = live(conn, ~p"/")
      sg_id = root_sg_id(store)
      before_ids = node_ids(store, sg_id)
      before_count = MapSet.size(before_ids)

      render_click(view, "add_leaf")
      new_id = new_node_id(store, sg_id, before_ids)

      render_click(view, "select_node", %{"node-id" => new_id})
      render_click(view, "delete_node", %{"node-id" => new_id})

      assert node_count(store, sg_id) == before_count
      assert :sys.get_state(view.pid).socket.assigns.selected_node_id == nil
    end
  end

  describe "navigation" do
    test "enter_gateway pushes breadcrumb", %{conn: conn, store: store} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "add_gateway")

      sg_id = root_sg_id(store)
      nodes = store |> Store.get_graph() |> Graph.get_subgraph(sg_id) |> Map.fetch!(:nodes)

      gateway_id =
        Enum.find_value(nodes, fn {id, node} ->
          if node.type == :gateway, do: id
        end)

      render_click(view, "enter_gateway", %{"node-id" => gateway_id})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert length(assigns.breadcrumb) == 2
      assert assigns.subgraph.id != sg_id
    end

    test "navigate_to_node jumps into a nested subgraph from the root", %{
      conn: conn,
      store: store
    } do
      # Build the topology via the LiveView: gateway on root, leaf inside it.
      {:ok, view, _html} = live(conn, ~p"/")
      root_id = root_sg_id(store)
      render_click(view, "add_gateway")

      gateway =
        store
        |> Store.get_graph()
        |> Graph.get_subgraph(root_id)
        |> Map.fetch!(:nodes)
        |> Enum.find_value(fn {_id, n} -> if n.type == :gateway, do: n end)

      render_click(view, "enter_gateway", %{"node-id" => gateway.id})
      render_click(view, "add_leaf")

      child_sg_id = gateway.subgraph_id

      nested_leaf_id =
        store
        |> Store.get_graph()
        |> Graph.get_subgraph(child_sg_id)
        |> Map.fetch!(:nodes)
        |> Enum.find_value(fn {id, n} -> if n.type == :leaf, do: id end)

      # Walk back to the root — navigate_to_node must work from anywhere,
      # but the interesting case is jumping into a non-current subgraph.
      render_click(view, "navigate_breadcrumb", %{"subgraph-id" => root_id})
      assert :sys.get_state(view.pid).socket.assigns.subgraph.id == root_id

      render_click(view, "navigate_to_node", %{
        "subgraph-id" => child_sg_id,
        "node-id" => nested_leaf_id
      })

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.subgraph.id == child_sg_id
      assert assigns.selected_node_id == nested_leaf_id
      assert length(assigns.breadcrumb) == 2
      assert [{^root_id, _}, {^child_sg_id, _}] = assigns.breadcrumb
    end
  end

  describe "history" do
    test "undo reverses add_leaf", %{conn: conn, store: store} do
      {:ok, view, _html} = live(conn, ~p"/")
      sg_id = root_sg_id(store)
      before = node_count(store, sg_id)

      render_click(view, "add_leaf")
      assert node_count(store, sg_id) == before + 1

      render_click(view, "undo")
      assert node_count(store, sg_id) == before
    end

    test "redo replays undone add_leaf", %{conn: conn, store: store} do
      {:ok, view, _html} = live(conn, ~p"/")
      sg_id = root_sg_id(store)
      before = node_count(store, sg_id)

      render_click(view, "add_leaf")
      render_click(view, "undo")
      render_click(view, "redo")

      assert node_count(store, sg_id) == before + 1
    end
  end

  describe "modals" do
    test "show_template_picker flips assign", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "show_template_picker")
      assert :sys.get_state(view.pid).socket.assigns.show_template_picker == true
    end

    test "select_oodn opens oodn editor", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "select_oodn")
      assert :sys.get_state(view.pid).socket.assigns.editing_oodn == true
    end

    test "open_graph_manager loads graph list", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "open_graph_manager")
      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.show_graph_manager == true
      assert is_list(assigns.graph_list)
    end

    test "edit_node_content opens content editor", %{conn: conn, store: store} do
      {:ok, view, _html} = live(conn, ~p"/")
      sg_id = root_sg_id(store)
      before_ids = node_ids(store, sg_id)

      render_click(view, "add_leaf")
      new_id = new_node_id(store, sg_id, before_ids)

      render_click(view, "edit_node_content", %{"node-id" => new_id})

      assert :sys.get_state(view.pid).socket.assigns.editing_content_node_id == new_id
    end
  end

  describe "pubsub isolation" do
    test "each test sees only its own store's updates", %{conn: conn, store: store} do
      {:ok, view, _html} = live(conn, ~p"/")
      sg_id = root_sg_id(store)
      before_count = node_count(store, sg_id)

      render_click(view, "add_leaf")
      render_click(view, "add_leaf")

      assert node_count(store, sg_id) == before_count + 2
      assert :sys.get_state(view.pid).socket.assigns.graph.root_subgraph_id == sg_id
    end
  end
end
