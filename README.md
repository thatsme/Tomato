# Tomato

A hierarchical DAG engine for composable NixOS configuration management.

Tomato models system configurations as directed acyclic graphs organized in floors (levels). Each leaf node holds a NixOS configuration fragment. Gateway nodes point to subgraphs on the floor below. Walking the graph top-down in topological order composes a valid `configuration.nix` — which can be deployed to a NixOS machine via SSH with a single click.

## Quick Start

```bash
mix setup
mix phx.server
```

Open [localhost:4000](http://localhost:4000). A demo graph loads automatically with Networking, Firewall, System, and a Services gateway containing PostgreSQL and Nginx.

## How It Works

### The Graph

```
Floor 0 (root)
  Input → Networking → System → Services (gateway) → Output
          Firewall  ↗

Floor 1 (inside Services)
  Input → PostgreSQL → Output
          Nginx      ↗
```

- **Leaf nodes** hold Nix config fragments (e.g. `services.nginx.enable = true;`)
- **Gateway nodes** contain a subgraph on the floor below — composing complex configs from smaller pieces
- **OODN node** (Out-Of-DAG Node) holds global variables (`${hostname}`, `${timezone}`, etc.) referenced by any leaf on any floor via `${key}` placeholders
- **Edges** define dependency order — the walker traverses nodes in topological order

### Generate & Deploy

1. **Generate** — walks the graph, interpolates OODN variables, wraps fragments in a NixOS module skeleton → writes `.nix` file to `priv/generated/`
2. **Reconfigure** — uploads `configuration.nix` to the target NixOS machine via SSH/SFTP, runs `nixos-rebuild switch`

Real services start, stop, and reconfigure on a real NixOS machine. Change `${nginx_port}` from `80` to `8080` in the OODN node → both the firewall rules and Nginx config update in one rebuild.

### Template Library

Click **+ Add Node** to pick from predefined NixOS templates:

| Category | Templates |
|---|---|
| **Stacks** | Prometheus Stack (5 nodes), Grafana + Prometheus, Web Server Stack |
| **System** | System Base, Networking, Firewall, Admin User, Console |
| **Web** | Nginx, Nginx Reverse Proxy, Caddy |
| **Database** | PostgreSQL, MySQL, Redis |
| **Services** | OpenSSH, Docker, Tailscale, Fail2ban, Cron Jobs |
| **Monitoring** | Prometheus, Grafana |
| **Packages** | Dev Tools |

Stack templates create a **gateway node with pre-wired child nodes** — e.g. Prometheus Stack creates Prometheus Base + Node Exporter + Scrape configs + Alert Rules, all connected and ready to deploy.

NixOS merges list and attribute set options automatically — `scrapeConfigs` from multiple nodes get concatenated into one `prometheus.yml`.

### OODN Variables

The OODN node is a singleton on the canvas holding global key-value pairs:

```
hostname    = tomato-node
timezone    = Europe/Rome
locale      = it_IT.UTF-8
keymap      = it
nginx_port  = 80
pg_port     = 5432
```

Leaf nodes reference these with `${key}` syntax. The walker interpolates them at generation time. Change a value once, every referencing node updates.

## Canvas Interactions

| Action | Effect |
|---|---|
| **Click** | Select node |
| **Drag** | Move node |
| **Double-click gateway** | Enter subgraph |
| **Double-click leaf** | Edit content |
| **Cmd+click leaf** | Edit content |
| **Long-press / right-click** | Context menu |
| **Scroll / two-finger** | Pan canvas |
| **Pinch / Ctrl+scroll** | Zoom |

Context menu actions: Connect from/to, Duplicate, Rename, Disconnect all, Delete, Reverse edge, Fit to view, Reset zoom.

## NixOS Deploy Target

### UTM VM (recommended for Apple Silicon)

NixOS ARM64 VM running natively in UTM. Full `nixos-rebuild switch` with real service activation.

Configure in `config/config.exs`:

```elixir
config :tomato, Tomato.Deploy,
  host: "192.168.64.3",
  port: 22,
  user: "root",
  password: "tomato"
```

### OrbStack (syntax validation)

Ubuntu VM with Nix installed. Validates config syntax with `nix-instantiate --parse`. No full rebuild.

## Architecture

```
lib/tomato/
  node.ex              # Node struct — :input, :output, :leaf, :gateway
  edge.ex              # Directed edge between nodes on same floor
  subgraph.ex          # Self-contained DAG on a floor
  graph.ex             # Top-level container with subgraphs + OODN registry
  oodn.ex              # Out-of-DAG key-value pair
  store.ex             # GenServer — in-memory state, JSON persistence, PubSub
  constraint.ex        # DAG validation — cycles, structure, edges
  walker.ex            # Topological traversal + OODN interpolation → .nix output
  deploy.ex            # SSH/SFTP upload + nixos-rebuild switch
  template_library.ex  # Predefined NixOS config templates (leaf + gateway stacks)
  demo.ex              # Seeds demo graph on first run

lib/tomato_web/
  live/graph_live.ex   # Main LiveView — SVG canvas, sidebar, modals
  
assets/js/
  hooks/graph_canvas.js  # Drag-and-drop, zoom/pan, long-press context menu, Bezier edges
```

### Persistence

Each graph is a single JSON file in `priv/graphs/`. The Graph Manager (click filename in sidebar) lets you create, load, save-as, and delete graphs. The JSON file is the source of truth — loaded into memory on startup, flushed on every mutation with 200ms debounce.

### DAG Constraints

Enforced on every mutation: no cycles (Kahn's algorithm), single `:input`/`:output` per subgraph, edges same-floor only, gateway-subgraph integrity.

## Development

```bash
mix deps.get            # install dependencies
mix compile             # compile
mix phx.server          # start dev server at localhost:4000
iex -S mix phx.server   # start with interactive shell
mix test                # run tests
mix format              # format code
```

## Requirements

- Elixir 1.15+
- Erlang/OTP 26+
- NixOS target machine for deploy (UTM VM or remote server)

## License

Private — designed over aperitivo, April 2026.
