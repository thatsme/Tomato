defmodule Tomato.Demo do
  @moduledoc """
  Seeds a demo graph for development/mockup purposes.
  Leaf nodes use ${oodn_key} placeholders for values that come from the OODN registry.
  """

  alias Tomato.Store

  @spec seed() :: :ok
  def seed do
    graph = Store.get_graph()
    root_sg = Tomato.Graph.root_subgraph(graph)

    # --- OODN config entries (global variables) ---
    Store.put_oodn("hostname", "tomato-node")
    Store.put_oodn("timezone", "Europe/Rome")
    Store.put_oodn("locale", "it_IT.UTF-8")
    Store.put_oodn("keymap", "it")
    Store.put_oodn("state_version", "24.11")
    Store.put_oodn("system_arch", "aarch64-linux")
    Store.put_oodn("nginx_port", "80")
    Store.put_oodn("pg_port", "5432")

    # --- Leaf nodes using ${oodn_key} references ---
    {:ok, n1} =
      Store.add_node(root_sg.id,
        type: :leaf,
        name: "Networking",
        position: %{x: 200, y: 180},
        content: ~S"""
        networking.hostName = "${hostname}";
        networking.networkmanager.enable = true;
        """
      )

    {:ok, n2} =
      Store.add_node(root_sg.id,
        type: :leaf,
        name: "Firewall",
        position: %{x: 400, y: 180},
        content: ~S"""
        networking.firewall.enable = true;
        networking.firewall.allowedTCPPorts = [ 22 ${nginx_port} 443 ];
        """
      )

    {:ok, n3} =
      Store.add_node(root_sg.id,
        type: :leaf,
        name: "System",
        position: %{x: 300, y: 300},
        content: ~S"""
        time.timeZone = "${timezone}";
        i18n.defaultLocale = "${locale}";
        """
      )

    # Gateway with child subgraph for services
    {:ok, gw, child} =
      Store.add_gateway(root_sg.id,
        name: "Services",
        position: %{x: 300, y: 420}
      )

    # Child subgraph: PostgreSQL + Nginx
    {:ok, svc_pg} =
      Store.add_node(child.id,
        type: :leaf,
        name: "PostgreSQL",
        position: %{x: 200, y: 180},
        content: ~S"""
        services.postgresql = {
          enable = true;
          package = pkgs.postgresql_17;
          settings.port = ${pg_port};
        };
        """
      )

    {:ok, svc_nginx} =
      Store.add_node(child.id,
        type: :leaf,
        name: "Nginx",
        position: %{x: 400, y: 180},
        content: ~S"""
        services.nginx.enable = true;
        services.nginx.defaultHTTPListenPort = ${nginx_port};
        services.nginx.virtualHosts."localhost" = {
          root = "/var/www";
        };
        """
      )

    # Wire child subgraph
    child_sg = Store.get_subgraph(child.id)
    child_input = Tomato.Subgraph.input_node(child_sg)
    child_output = Tomato.Subgraph.output_node(child_sg)

    Store.add_edge(child.id, child_input.id, svc_pg.id)
    Store.add_edge(child.id, child_input.id, svc_nginx.id)
    Store.add_edge(child.id, svc_pg.id, child_output.id)
    Store.add_edge(child.id, svc_nginx.id, child_output.id)

    # Wire root subgraph
    updated_sg = Store.get_subgraph(root_sg.id)
    input = Tomato.Subgraph.input_node(updated_sg)
    output = Tomato.Subgraph.output_node(updated_sg)

    Store.add_edge(root_sg.id, input.id, n1.id)
    Store.add_edge(root_sg.id, input.id, n2.id)
    Store.add_edge(root_sg.id, n1.id, n3.id)
    Store.add_edge(root_sg.id, n2.id, n3.id)
    Store.add_edge(root_sg.id, n3.id, gw.id)
    Store.add_edge(root_sg.id, gw.id, output.id)

    :ok
  end
end
