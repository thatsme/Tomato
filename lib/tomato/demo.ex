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

    # --- Flake inputs (used when backend is :flake) ---
    Store.put_oodn("input_nixpkgs", "github:nixos/nixpkgs?ref=nixos-unstable")
    Store.put_oodn("input_home-manager", "github:nix-community/home-manager")
    Store.put_oodn("input_home-manager_follows", "nixpkgs")

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

  @doc """
  Seed a multi-machine demo graph showing 2 NixOS servers + 1 Home Manager config.
  Creates a new graph file 'multi-machine.json'.
  """
  @spec seed_multi() :: :ok
  def seed_multi do
    {:ok, _graph, _filename} = Store.new_graph("multi-machine")
    Store.set_backend(:flake)

    # --- Global OODNs ---
    Store.put_oodn("timezone", "Europe/Rome")
    Store.put_oodn("locale", "it_IT.UTF-8")
    Store.put_oodn("keymap", "it")
    Store.put_oodn("state_version", "24.11")

    # --- Flake inputs ---
    Store.put_oodn("input_nixpkgs", "github:nixos/nixpkgs?ref=nixos-unstable")
    Store.put_oodn("input_home-manager", "github:nix-community/home-manager")
    Store.put_oodn("input_home-manager_follows", "nixpkgs")

    graph = Store.get_graph()
    root_sg = Tomato.Graph.root_subgraph(graph)

    # --- Shared firewall (applies to all machines) ---
    {:ok, shared_fw} =
      Store.add_node(root_sg.id,
        type: :leaf,
        name: "Firewall",
        position: %{x: 200, y: 180},
        content: """
        networking.firewall.enable = true;
        networking.firewall.allowedTCPPorts = [ 22 80 443 ];
        """
      )

    # --- Machine 1: webserver (NixOS) ---
    {:ok, m1, m1_sg} =
      Store.add_machine(root_sg.id,
        hostname: "webserver",
        system: "x86_64-linux",
        state_version: "24.11",
        type: :nixos,
        position: %{x: 200, y: 320}
      )

    {:ok, nginx_node} =
      Store.add_node(m1_sg.id,
        type: :leaf,
        name: "Nginx",
        position: %{x: 200, y: 200},
        content: """
        services.nginx = {
          enable = true;
          virtualHosts."default" = { root = "/var/www"; };
        };
        """
      )

    m1_sg_full = Store.get_subgraph(m1_sg.id)
    m1_in = Tomato.Subgraph.input_node(m1_sg_full)
    m1_out = Tomato.Subgraph.output_node(m1_sg_full)
    Store.add_edge(m1_sg.id, m1_in.id, nginx_node.id)
    Store.add_edge(m1_sg.id, nginx_node.id, m1_out.id)

    # --- Machine 2: dbserver (NixOS) ---
    {:ok, m2, m2_sg} =
      Store.add_machine(root_sg.id,
        hostname: "dbserver",
        system: "aarch64-linux",
        state_version: "24.11",
        type: :nixos,
        position: %{x: 400, y: 320}
      )

    {:ok, pg_node} =
      Store.add_node(m2_sg.id,
        type: :leaf,
        name: "PostgreSQL",
        position: %{x: 200, y: 200},
        content: """
        services.postgresql = {
          enable = true;
          package = pkgs.postgresql_17;
          ensureDatabases = [ "app" ];
        };
        """
      )

    m2_sg_full = Store.get_subgraph(m2_sg.id)
    m2_in = Tomato.Subgraph.input_node(m2_sg_full)
    m2_out = Tomato.Subgraph.output_node(m2_sg_full)
    Store.add_edge(m2_sg.id, m2_in.id, pg_node.id)
    Store.add_edge(m2_sg.id, pg_node.id, m2_out.id)

    # --- Machine 3: laptop (Home Manager) ---
    {:ok, m3, m3_sg} =
      Store.add_machine(root_sg.id,
        hostname: "laptop",
        system: "aarch64-darwin",
        state_version: "24.11",
        type: :home_manager,
        username: "alex",
        position: %{x: 600, y: 320}
      )

    {:ok, git_node} =
      Store.add_node(m3_sg.id,
        type: :leaf,
        name: "Git",
        position: %{x: 200, y: 180},
        content: ~S"""
        programs.git = {
          enable = true;
          userName = "${username}";
          userEmail = "${username}@localhost";
        };
        """
      )

    {:ok, zsh_node} =
      Store.add_node(m3_sg.id,
        type: :leaf,
        name: "Zsh",
        position: %{x: 400, y: 180},
        content: """
        programs.zsh = {
          enable = true;
          enableCompletion = true;
          oh-my-zsh.enable = true;
        };
        """
      )

    m3_sg_full = Store.get_subgraph(m3_sg.id)
    m3_in = Tomato.Subgraph.input_node(m3_sg_full)
    m3_out = Tomato.Subgraph.output_node(m3_sg_full)
    Store.add_edge(m3_sg.id, m3_in.id, git_node.id)
    Store.add_edge(m3_sg.id, m3_in.id, zsh_node.id)
    Store.add_edge(m3_sg.id, git_node.id, m3_out.id)
    Store.add_edge(m3_sg.id, zsh_node.id, m3_out.id)

    # --- Wire root: input -> firewall -> all machines -> output ---
    updated_root = Store.get_subgraph(root_sg.id)
    input = Tomato.Subgraph.input_node(updated_root)
    output = Tomato.Subgraph.output_node(updated_root)

    Store.add_edge(root_sg.id, input.id, shared_fw.id)
    Store.add_edge(root_sg.id, shared_fw.id, m1.id)
    Store.add_edge(root_sg.id, shared_fw.id, m2.id)
    Store.add_edge(root_sg.id, shared_fw.id, m3.id)
    Store.add_edge(root_sg.id, m1.id, output.id)
    Store.add_edge(root_sg.id, m2.id, output.id)
    Store.add_edge(root_sg.id, m3.id, output.id)

    :ok
  end

  @doc """
  Seed a pure Home Manager demo graph — developer dotfiles via flake.
  Creates a new graph file 'home-manager.json' with Git, Zsh, Neovim, Tmux,
  Alacritty and user packages.
  """
  @spec seed_home() :: :ok
  def seed_home do
    {:ok, _graph, _filename} = Store.new_graph("home-manager")
    Store.set_backend(:flake)

    # --- Global OODNs ---
    Store.put_oodn("username", "alex")
    Store.put_oodn("git_name", "Alex Doe")
    Store.put_oodn("git_email", "alex@example.com")
    Store.put_oodn("state_version", "24.11")

    # --- Flake inputs ---
    Store.put_oodn("input_nixpkgs", "github:nixos/nixpkgs?ref=nixos-unstable")
    Store.put_oodn("input_home-manager", "github:nix-community/home-manager")
    Store.put_oodn("input_home-manager_follows", "nixpkgs")

    graph = Store.get_graph()
    root_sg = Tomato.Graph.root_subgraph(graph)

    # --- Single Home Manager machine: laptop ---
    {:ok, machine, m_sg} =
      Store.add_machine(root_sg.id,
        hostname: "laptop",
        system: "aarch64-darwin",
        state_version: "24.11",
        type: :home_manager,
        username: "alex",
        position: %{x: 300, y: 250}
      )

    # --- User config nodes ---
    {:ok, git_node} =
      Store.add_node(m_sg.id,
        type: :leaf,
        name: "Git",
        position: %{x: 150, y: 180},
        content: ~S"""
        programs.git = {
          enable = true;
          userName = "${git_name}";
          userEmail = "${git_email}";
          extraConfig = {
            init.defaultBranch = "main";
            pull.rebase = true;
          };
        };
        """
      )

    {:ok, zsh_node} =
      Store.add_node(m_sg.id,
        type: :leaf,
        name: "Zsh + Starship",
        position: %{x: 350, y: 180},
        content: """
        programs.zsh = {
          enable = true;
          enableCompletion = true;
          autosuggestion.enable = true;
          syntaxHighlighting.enable = true;
          oh-my-zsh = {
            enable = true;
            plugins = [ "git" "docker" "z" ];
            theme = "robbyrussell";
          };
        };

        programs.starship = {
          enable = true;
          enableZshIntegration = true;
        };
        """
      )

    {:ok, nvim_node} =
      Store.add_node(m_sg.id,
        type: :leaf,
        name: "Neovim",
        position: %{x: 550, y: 180},
        content: """
        programs.neovim = {
          enable = true;
          defaultEditor = true;
          viAlias = true;
          vimAlias = true;
        };
        """
      )

    {:ok, tmux_node} =
      Store.add_node(m_sg.id,
        type: :leaf,
        name: "Tmux",
        position: %{x: 150, y: 320},
        content: """
        programs.tmux = {
          enable = true;
          clock24 = true;
          terminal = "screen-256color";
          keyMode = "vi";
          shortcut = "a";
        };
        """
      )

    {:ok, alacritty_node} =
      Store.add_node(m_sg.id,
        type: :leaf,
        name: "Alacritty",
        position: %{x: 350, y: 320},
        content: """
        programs.alacritty = {
          enable = true;
          settings = {
            font.size = 14;
            window.opacity = 0.95;
            window.padding = { x = 10; y = 10; };
          };
        };
        """
      )

    {:ok, pkgs_node} =
      Store.add_node(m_sg.id,
        type: :leaf,
        name: "User Packages",
        position: %{x: 550, y: 320},
        content: """
        home.packages = with pkgs; [
          ripgrep
          fd
          jq
          htop
          bat
          eza
          fzf
          direnv
          gh
        ];
        """
      )

    # Wire all leaves: input -> each leaf -> output
    m_sg_full = Store.get_subgraph(m_sg.id)
    m_in = Tomato.Subgraph.input_node(m_sg_full)
    m_out = Tomato.Subgraph.output_node(m_sg_full)

    for leaf <- [git_node, zsh_node, nvim_node, tmux_node, alacritty_node, pkgs_node] do
      Store.add_edge(m_sg.id, m_in.id, leaf.id)
      Store.add_edge(m_sg.id, leaf.id, m_out.id)
    end

    # Wire root: input -> machine -> output
    updated_root = Store.get_subgraph(root_sg.id)
    input = Tomato.Subgraph.input_node(updated_root)
    output = Tomato.Subgraph.output_node(updated_root)
    Store.add_edge(root_sg.id, input.id, machine.id)
    Store.add_edge(root_sg.id, machine.id, output.id)

    :ok
  end
end
