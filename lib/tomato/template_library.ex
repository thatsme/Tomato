defmodule Tomato.TemplateLibrary do
  @moduledoc """
  Predefined Nix configuration templates for leaf nodes.
  Each template uses ${oodn_key} placeholders for OODN integration.
  """

  @enforce_keys [:id, :name, :category]
  defstruct [:id, :name, :category, :description, :content, :oodn_keys]

  @templates [
    # --- System ---
    %{
      id: "system-base",
      name: "System Base",
      category: "System",
      description: "Hostname, timezone, locale",
      oodn_keys: ["hostname", "timezone", "locale"],
      content: ~S"""
      networking.hostName = "${hostname}";
      time.timeZone = "${timezone}";
      i18n.defaultLocale = "${locale}";
      """
    },
    %{
      id: "networking",
      name: "Networking",
      category: "System",
      description: "NetworkManager with DHCP",
      oodn_keys: ["hostname"],
      content: ~S"""
      networking.hostName = "${hostname}";
      networking.networkmanager.enable = true;
      """
    },
    %{
      id: "firewall",
      name: "Firewall",
      category: "System",
      description: "Basic firewall with configurable ports",
      oodn_keys: [],
      content: """
      networking.firewall.enable = true;
      networking.firewall.allowedTCPPorts = [ 22 80 443 ];
      """
    },
    %{
      id: "users-admin",
      name: "Admin User",
      category: "System",
      description: "Admin user with wheel and networkmanager groups",
      oodn_keys: [],
      content: """
      users.users.admin = {
        isNormalUser = true;
        extraGroups = [ "wheel" "networkmanager" ];
        openssh.authorizedKeys.keys = [];
      };
      """
    },
    %{
      id: "console",
      name: "Console",
      category: "System",
      description: "Console keymap and font",
      oodn_keys: ["keymap"],
      content: ~S"""
      console.keyMap = "${keymap}";
      """
    },

    # --- Web ---
    %{
      id: "nginx",
      name: "Nginx",
      category: "Web",
      description: "Nginx web server with virtual host",
      oodn_keys: ["nginx_port"],
      content: ~S"""
      services.nginx.enable = true;
      services.nginx.defaultHTTPListenPort = ${nginx_port};
      services.nginx.virtualHosts."localhost" = {
        root = "/var/www";
      };
      """
    },
    %{
      id: "nginx-reverse-proxy",
      name: "Nginx Reverse Proxy",
      category: "Web",
      description: "Nginx as reverse proxy to a backend",
      oodn_keys: [],
      content: """
      services.nginx = {
        enable = true;
        virtualHosts."localhost" = {
          locations."/" = {
            proxyPass = "http://127.0.0.1:4000";
            proxyWebsockets = true;
          };
        };
      };
      """
    },
    %{
      id: "caddy",
      name: "Caddy",
      category: "Web",
      description: "Caddy web server with automatic HTTPS",
      oodn_keys: [],
      content: """
      services.caddy = {
        enable = true;
        virtualHosts."localhost".extraConfig = ''
          root * /var/www
          file_server
        '';
      };
      """
    },

    # --- Database ---
    %{
      id: "postgresql",
      name: "PostgreSQL",
      category: "Database",
      description: "PostgreSQL database server",
      oodn_keys: ["pg_port"],
      content: ~S"""
      services.postgresql = {
        enable = true;
        package = pkgs.postgresql_17;
        settings.port = ${pg_port};
      };
      """
    },
    %{
      id: "mysql",
      name: "MySQL",
      category: "Database",
      description: "MySQL/MariaDB database server",
      oodn_keys: [],
      content: """
      services.mysql = {
        enable = true;
        package = pkgs.mariadb;
      };
      """
    },
    %{
      id: "redis",
      name: "Redis",
      category: "Database",
      description: "Redis in-memory data store",
      oodn_keys: [],
      content: """
      services.redis.servers."default" = {
        enable = true;
        port = 6379;
      };
      """
    },

    # --- Services ---
    %{
      id: "openssh",
      name: "OpenSSH",
      category: "Services",
      description: "SSH server with key-based auth",
      oodn_keys: [],
      content: """
      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin = "prohibit-password";
          PasswordAuthentication = false;
        };
      };
      """
    },
    %{
      id: "docker",
      name: "Docker",
      category: "Services",
      description: "Docker container runtime",
      oodn_keys: [],
      content: """
      virtualisation.docker.enable = true;
      users.users.admin.extraGroups = [ "docker" ];
      """
    },
    %{
      id: "tailscale",
      name: "Tailscale",
      category: "Services",
      description: "Tailscale VPN mesh network",
      oodn_keys: [],
      content: """
      services.tailscale.enable = true;
      networking.firewall.allowedUDPPorts = [ 41641 ];
      """
    },
    %{
      id: "fail2ban",
      name: "Fail2ban",
      category: "Services",
      description: "Intrusion prevention - ban IPs after failed logins",
      oodn_keys: [],
      content: """
      services.fail2ban = {
        enable = true;
        maxretry = 5;
        bantime = "1h";
      };
      """
    },
    %{
      id: "cron",
      name: "Cron Jobs",
      category: "Services",
      description: "Scheduled tasks",
      oodn_keys: [],
      content: """
      services.cron = {
        enable = true;
        systemCronJobs = [
          "0 2 * * * root /run/current-system/sw/bin/nix-collect-garbage -d"
        ];
      };
      """
    },

    # --- Monitoring ---
    %{
      id: "prometheus",
      name: "Prometheus",
      category: "Monitoring",
      description: "Prometheus metrics collection",
      oodn_keys: [],
      content: """
      services.prometheus = {
        enable = true;
        port = 9090;
        exporters.node = {
          enable = true;
          port = 9100;
        };
      };
      """
    },
    %{
      id: "grafana",
      name: "Grafana",
      category: "Monitoring",
      description: "Grafana dashboards",
      oodn_keys: [],
      content: """
      services.grafana = {
        enable = true;
        settings.server.http_port = 3000;
        settings.server.http_addr = "0.0.0.0";
      };
      """
    },

    # --- Packages ---
    %{
      id: "dev-tools",
      name: "Dev Tools",
      category: "Packages",
      description: "Common development tools",
      oodn_keys: [],
      content: """
      environment.systemPackages = with pkgs; [
        vim
        git
        curl
        wget
        htop
        tmux
        jq
        ripgrep
      ];
      """
    },
    %{
      id: "custom",
      name: "Empty (Custom)",
      category: "Custom",
      description: "Blank template — write your own Nix config",
      oodn_keys: [],
      content: ""
    },

    # --- Stacks (Gateway templates with child nodes) ---
    %{
      id: "stack-prometheus",
      name: "Prometheus Stack",
      category: "Stacks",
      description: "Full monitoring: Prometheus + Node Exporter + scrape configs + alert rules",
      type: :gateway,
      oodn_keys: [],
      children: [
        %{
          name: "Prometheus Base",
          content: """
          services.prometheus = {
            enable = true;
            port = 9090;
            globalConfig = {
              scrape_interval = "15s";
              evaluation_interval = "15s";
            };
          };
          """
        },
        %{
          name: "Node Exporter",
          content: """
          services.prometheus.exporters.node = {
            enable = true;
            port = 9100;
            enabledCollectors = [ "cpu" "diskstats" "filesystem" "loadavg" "meminfo" "netdev" "stat" "time" ];
          };
          """
        },
        %{
          name: "Scrape: Node",
          content: """
          services.prometheus.scrapeConfigs = [
            {
              job_name = "node";
              static_configs = [{
                targets = [ "localhost:9100" ];
                labels = { instance = "localhost"; };
              }];
            }
          ];
          """
        },
        %{
          name: "Scrape: Nginx",
          content: """
          services.prometheus.scrapeConfigs = [
            {
              job_name = "nginx";
              static_configs = [{
                targets = [ "localhost:9113" ];
              }];
            }
          ];

          services.prometheus.exporters.nginx = {
            enable = true;
            port = 9113;
          };
          """
        },
        %{
          name: "Alert Rules",
          content: ~S"""
          services.prometheus.rules = [
            ''
              groups:
                - name: system
                  rules:
                    - alert: InstanceDown
                      expr: up == 0
                      for: 5m
                      labels:
                        severity: critical
                      annotations:
                        summary: "Instance {{ $labels.instance }} down"
                    - alert: HighCPU
                      expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
                      for: 10m
                      labels:
                        severity: warning
                    - alert: DiskSpaceLow
                      expr: node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} < 0.1
                      for: 5m
                      labels:
                        severity: warning
            ''
          ];
          """
        }
      ]
    },
    %{
      id: "stack-grafana",
      name: "Grafana + Prometheus",
      category: "Stacks",
      description: "Grafana with Prometheus datasource pre-configured",
      type: :gateway,
      oodn_keys: [],
      children: [
        %{
          name: "Grafana Server",
          content: """
          services.grafana = {
            enable = true;
            settings = {
              server = {
                http_port = 3000;
                http_addr = "0.0.0.0";
              };
              security = {
                admin_user = "admin";
                admin_password = "admin";
              };
            };
          };
          """
        },
        %{
          name: "Prometheus Datasource",
          content: """
          services.grafana.provision.datasources.settings.datasources = [
            {
              name = "Prometheus";
              type = "prometheus";
              url = "http://localhost:9090";
              isDefault = true;
            }
          ];
          """
        }
      ]
    },
    %{
      id: "stack-webserver",
      name: "Web Server Stack",
      category: "Stacks",
      description: "Nginx + PostgreSQL + firewall rules for a typical web app",
      type: :gateway,
      oodn_keys: ["nginx_port", "pg_port"],
      children: [
        %{
          name: "Nginx",
          content: ~S"""
          services.nginx = {
            enable = true;
            recommendedProxySettings = true;
            recommendedTlsSettings = true;
            virtualHosts."localhost" = {
              listen = [{ port = ${nginx_port}; addr = "0.0.0.0"; }];
              locations."/" = {
                root = "/var/www";
              };
            };
          };
          """
        },
        %{
          name: "PostgreSQL",
          content: ~S"""
          services.postgresql = {
            enable = true;
            package = pkgs.postgresql_17;
            settings.port = ${pg_port};
            ensureDatabases = [ "app" ];
            ensureUsers = [
              { name = "app"; ensureDBOwnership = true; }
            ];
          };
          """
        },
        %{
          name: "Firewall Ports",
          content: ~S"""
          networking.firewall.allowedTCPPorts = [ ${nginx_port} 443 ];
          """
        }
      ]
    }
  ]

  @doc "Returns all templates."
  @spec all() :: list(map())
  def all, do: @templates

  @doc "Returns templates grouped by category."
  @spec by_category() :: list({String.t(), list(map())})
  def by_category do
    @templates
    |> Enum.group_by(& &1.category)
    |> Enum.sort_by(fn {cat, _} ->
      case cat do
        "Stacks" -> 0
        "System" -> 1
        "Web" -> 2
        "Database" -> 3
        "Services" -> 4
        "Monitoring" -> 5
        "Packages" -> 6
        _ -> 99
      end
    end)
  end

  @doc "Find a template by id."
  @spec get(String.t()) :: map() | nil
  def get(id) do
    Enum.find(@templates, fn t -> t.id == id end)
  end
end
