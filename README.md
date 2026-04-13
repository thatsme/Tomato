# Tomato

A hierarchical DAG engine for composable NixOS configuration management.

Tomato models system configurations as directed acyclic graphs organized in floors (levels). Each leaf node holds a NixOS configuration fragment. Gateway nodes point to subgraphs on the floor below. Walking the graph top-down in topological order composes a valid `configuration.nix` or `flake.nix` — which can be deployed to a NixOS machine via SSH with a single click.

**OODNs** (Out-Of-DAG Nodes) are global key-value pairs — hostnames, ports, flake inputs — that leaf nodes reference via `${key}` placeholders. The walker interpolates them at generation time, so changing one value updates every node that references it.

![Tomato Graph Editor — multi-machine flake](docs/screenshots/tomato_flake.png)

## Quick Start

```bash
mix setup
mix phx.server
```

Open [localhost:4001](http://localhost:4001). Three demo graphs load automatically — switch between them via the Graph Manager (click the filename in the sidebar).

### Example 1 — `default.json` (simple traditional NixOS)

A single-machine traditional `configuration.nix` example. Good first walkthrough.

- **Root floor**: Networking → System → Services (gateway), with Firewall in parallel
- **Services subgraph**: PostgreSQL + Nginx
- **OODNs**: `hostname`, `timezone`, `locale`, `keymap`, `nginx_port`, `pg_port`
- **Backend**: Traditional (`configuration.nix`)

### Example 2 — `multi-machine.json` (flake with multiple servers)

A flake-based multi-machine setup showing per-machine OODN override and shared config.

- **Root floor**: shared Firewall + 3 machines
- **webserver** (NixOS, x86_64-linux): Nginx
- **dbserver** (NixOS, aarch64-linux): PostgreSQL
- **laptop** (Home Manager, aarch64-darwin): Git + Zsh
- **OODNs**: `input_nixpkgs`, `input_home-manager`, `input_home-manager_follows`
- **Backend**: Flake (`flake.nix` with mixed `nixosConfigurations` + `homeConfigurations`)

### Example 3 — `home-manager.json` (pure Home Manager dotfiles)

A developer dotfiles example — no NixOS server, just user-level configuration.

- **One Home Manager machine**: laptop (aarch64-darwin, user "alex")
- **Inside**: Git, Zsh + Starship, Neovim, Tmux, Alacritty, User Packages
- **OODNs**: `username`, `git_name`, `git_email`, flake inputs
- **Backend**: Flake (`flake.nix` with `homeConfigurations."alex@laptop"`)

## What's New in v0.3

v0.3 is an internal-quality release — refactoring, bug fixes, and small correctness features. **No breaking changes**: every v0.2 graph file loads and renders unchanged, all public APIs are preserved spec-for-spec.

| Change | Description |
|---|---|
| **Deploy split** | `Tomato.Deploy` shrunk from 320 to ~140 lines; logic moved into `Tomato.Deploy.SSH`, `SFTP`, `Rebuild`, `Diff`, `Config`. Public API preserved; `TomatoWeb.GraphLive` needed no changes. |
| **SSH key authentication** | Credentials resolve in order: explicit `:identity_file` → `TOMATO_DEPLOY_IDENTITY_FILE` env var → `~/.ssh/id_ed25519` → `~/.ssh/id_rsa` → password fallback. Key auth uses Erlang `:ssh.connect/3` with `user_dir`. |
| **Store split** | `Tomato.Store` shrunk from 716 to 182 lines — thin GenServer facade over `Store.State`, `Mutations`, `OODN`, `Machine`, `Persistence`, `GraphFiles`. Pure mutation modules are testable without a running GenServer. |
| **Seeder fix** | Demo graphs seed independently. If any of `default.json`, `multi-machine.json`, `home-manager.json` is missing on startup, the seeder creates just that one — previously a populated `default.json` blocked all seeding. |
| **Leaf `target` field** | Each leaf declares `target :: :nixos \| :home_manager \| :all` (default `:nixos`). The walker filters shared root-level fragments by each machine's type, so `networking.firewall.*` is never spliced into a Home Manager module. |
| **Per-machine OODN overlay** | Each machine gateway carries an optional `oodn_overrides` map that shadows the global OODN registry inside that machine's subtree. Two machines can now hold different `nginx_port` values without naming hacks. |
| **Canvas components split** | SVG render components (`graph_node`, `edge_line`, `oodn_node`) and their style helpers moved from `TomatoWeb.GraphLive` into `TomatoWeb.GraphLive.CanvasComponents`. First phase of the LiveView god-module refactor. |
| **Test coverage** | 69 tests → 114 tests (+45) across walker target filtering, mutations, persistence roundtrips, deploy config resolution, and OODN overlay scenarios. |

> ⚠️ **UI gap — `target` and `oodn_overrides` are data-layer only in v0.3.** Both features work end-to-end in the walker, persist to JSON correctly, and have full test coverage, but there's no visual editor yet. New leaves default to `target: :nixos` and new machines default to `oodn_overrides: %{}`, which is correct for every existing graph — but if you need to mark a leaf as `:home_manager` or attach per-machine overrides, you currently have to edit `priv/graphs/*.json` by hand or use `iex -S mix phx.server` (see the [OODN Variables](#oodn-variables) section for an example). **Sidebar editors for both are queued as the next v0.3 PR.**

## What's New in v0.2

| Feature | Description |
|---|---|
| **Flake backend** | Toggle between traditional `configuration.nix` and `flake.nix` output. OODN entries prefixed with `input_` become flake inputs |
| **Multi-machine** | Each machine is a gateway with metadata. Generate one flake with multiple `nixosConfigurations` entries |
| **Home Manager** | Machines can be `:nixos` or `:home_manager`. Generates `homeConfigurations` alongside NixOS configs |
| **Deploy modes** | Switch / Test / Dry Run / Diff / Rollback — all from the UI |
| **Content preview** | Leaf nodes show the first lines of their Nix content directly on the canvas |
| **Node search** | Find nodes by name or content across all subgraphs and floors |
| **Undo / Redo** | 50-snapshot mutation history with sidebar buttons |

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

- **Leaf nodes** hold Nix config fragments (e.g. `services.nginx.enable = true;`). Each leaf declares a `target` field — `:nixos` (default), `:home_manager`, or `:all` — which tells the walker whether to include it when generating each backend-specific machine config
- **Gateway nodes** contain a subgraph on the floor below — composing complex configs from smaller pieces
- **Machine nodes** are gateways with metadata (`hostname`, `system`, `state_version`, `type`, `oodn_overrides`). The walker overlays the machine's hardcoded keys and any user-supplied `oodn_overrides` on top of the global OODN when interpolating that machine's subtree
- **OODN node** (Out-Of-DAG Node) is a canvas singleton holding global key-value pairs (`${hostname}`, `${timezone}`, `input_nixpkgs`, etc.) referenced by leaf nodes via `${key}` placeholders. Per-machine `oodn_overrides` shadow the global OODN for that machine's subtree only
- **Edges** define dependency order — the walker traverses nodes in topological order

### Generate & Deploy

1. **Generate** — walks the graph, interpolates OODN variables, wraps fragments in either a NixOS module skeleton (traditional) or a `flake.nix` skeleton with `nixosConfigurations`/`homeConfigurations` → writes `.nix` file to `priv/generated/`
2. **Deploy modes** — pick from the generated output modal:
   - **Switch** — `nixos-rebuild switch` (apply + boot menu)
   - **Test** — `nixos-rebuild test` (apply without boot menu)
   - **Dry Run** — `nixos-rebuild dry-activate` (show what would change)
   - **Diff** — fetch current remote config and show line-by-line diff
   - **Rollback** — revert to the previous NixOS generation

Real services start, stop, and reconfigure on a real NixOS machine. Change `${nginx_port}` from `80` to `8080` in the OODN node → both the firewall rules and Nginx config update in one rebuild.

> **Note on Nix syntax errors.** The walker treats leaf content as opaque strings — it does not parse Nix. A syntax error in a fragment passes through generation silently and only surfaces at `nixos-rebuild` time on the remote machine, after a full SSH+SFTP roundtrip. Local validation (`nix-instantiate --parse` on each fragment before write) is on the v0.3 list.

### Backend Toggle

Click **Traditional / Flake** in the sidebar header to switch output format:

- **Traditional** generates `configuration.nix` with imports, deployed via `nixos-rebuild switch`
- **Flake** generates `flake.nix` with inputs from `input_*` OODNs, multiple `nixosConfigurations` for multi-machine setups, deployed via `nixos-rebuild switch --flake .#hostname`

Flake inputs and `follows` declarations come from OODNs:

```
input_nixpkgs              = github:nixos/nixpkgs?ref=nixos-unstable
input_home-manager         = github:nix-community/home-manager
input_home-manager_follows = nixpkgs
```

### Multi-Machine

Each machine is a root-level gateway with metadata. The walker generates one `nixosConfigurations` (or `homeConfigurations`) entry per machine, with per-machine `${hostname}`, `${system_arch}`, `${state_version}`, and `${username}` overrides automatically applied during OODN interpolation.

**Shared root-level fragments**: leaf nodes placed at the root (not inside any machine gateway) get included in machines' configs — useful for firewall rules, common packages, or base hardening applied to every server. Each leaf's `target` field controls which machines receive it:

- `target: :nixos` (default) — included in `nixosConfigurations` entries, excluded from `homeConfigurations`
- `target: :home_manager` — included in `homeConfigurations`, excluded from NixOS
- `target: :all` — included in both

So a `networking.firewall.*` leaf ships to the two NixOS servers but not the Home Manager laptop, while a `programs.direnv.enable` leaf would go to the laptop only.

**Per-machine OODN overrides**: each machine gateway can carry an `oodn_overrides` map that shadows the global OODN registry inside that machine's subtree. Two machines with the same service can have different values (e.g. different `nginx_port` per machine) without naming hacks. The global OODN remains the singleton fallback layer for anything the machine doesn't override.

> ⚠️ **v0.3 data-layer only**: the `target` field and `oodn_overrides` map are fully functional in the walker and persisted to JSON, but there is no sidebar editor for either yet. See [OODN Variables](#oodn-variables) below for how to set non-default values via `iex` or direct JSON editing in the current release.

### Template Library

Click **+ Add Node** to pick from predefined templates:

| Category | Templates |
|---|---|
| **Stacks** | Prometheus Stack (5 nodes), Grafana + Prometheus, Web Server Stack |
| **System** | System Base, Networking, Firewall, Admin User, Console |
| **Web** | Nginx, Nginx Reverse Proxy, Caddy |
| **Database** | PostgreSQL, MySQL, Redis |
| **Services** | OpenSSH, Docker, Tailscale, Fail2ban, Cron Jobs |
| **Monitoring** | Prometheus, Grafana |
| **Home Manager** | Git, Zsh, Neovim, Tmux, Starship, Direnv, Alacritty, User Packages |
| **Packages** | Dev Tools |

Stack templates create a **gateway with pre-wired child nodes** — e.g. Prometheus Stack creates Prometheus Base + Node Exporter + Scrape configs + Alert Rules, all connected and ready to deploy.

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
input_nixpkgs              = github:nixos/nixpkgs?ref=nixos-unstable
input_home-manager         = github:nix-community/home-manager
input_home-manager_follows = nixpkgs
```

Leaf nodes reference these with `${key}` syntax. The walker interpolates them at generation time. Change a value once, every referencing node updates. The visible OODN node caps at 6 entries with a `+N more` indicator — double-click to open the full editor.

#### Per-machine OODN overrides (v0.3)

Each machine gateway can carry an `oodn_overrides` map that takes precedence over the global OODN registry when the walker interpolates that machine's subtree. Precedence layering, highest to lowest:

1. `machine.oodn_overrides` — user-supplied, wins over everything
2. Hardcoded machine keys — `hostname`, `system_arch`, `state_version`, `username`
3. Global OODN registry — the canvas singleton, everything else falls through to here

> ⚠️ **The global OODN panel on the canvas remains the only visual editor in v0.3.** Per-machine overrides are fully wired through the walker and persisted to JSON, but there's no sidebar editor for them yet. A scoped OODN panel that appears inside each machine's subgraph is queued as the next v0.3 PR.

Until the UI lands, the two ways to set per-machine overrides are:

**(a) Edit the graph file directly** — open `priv/graphs/<yourgraph>.json`, find the machine gateway node, and add an `oodn_overrides` object to its `machine` map:

```json
{
  "id": "node-abc",
  "type": "gateway",
  "machine": {
    "hostname": "webserver-a",
    "system": "x86_64-linux",
    "state_version": "24.11",
    "type": "nixos",
    "oodn_overrides": {
      "nginx_port": "8080",
      "max_clients": "200"
    }
  }
}
```

Restart the server to reload (or call `Store.load_graph/1` from iex).

**(b) Create the machine from `iex -S mix phx.server`**:

```elixir
graph = Tomato.Store.get_graph()
root = Tomato.Graph.root_subgraph(graph)

Tomato.Store.add_machine(root.id,
  hostname: "webserver-a",
  system: "x86_64-linux",
  state_version: "24.11",
  type: :nixos,
  oodn_overrides: %{"nginx_port" => "8080"}
)
```

Either way, the walker picks them up on the next Generate. Leaves inside the machine that reference `${nginx_port}` resolve against the override; shared root-level leaves still see the global `nginx_port`.

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

The sidebar provides node search, undo/redo, graph manager, backend toggle, generate, and node properties.

## Deploy Configuration

Tomato supports both **SSH public-key authentication** (recommended) and legacy password authentication as a fallback. Credentials are resolved in this order, first match wins:

1. Explicit `:identity_file` key in `config/deploy.secret.exs`
2. `TOMATO_DEPLOY_IDENTITY_FILE` environment variable
3. Auto-discovered `~/.ssh/id_ed25519`
4. Auto-discovered `~/.ssh/id_rsa`
5. Password fallback — `:password` / `TOMATO_DEPLOY_PASSWORD` (logs a warning on every connect)

> **Security notice.** For anything beyond a throw-away lab host, **use SSH key authentication**. The password path logs a Logger warning on every deploy and passes credentials in plaintext to Erlang `:ssh.connect/3`. If you must use password auth, use a dedicated low-privilege deploy user, restrict the target host to your LAN/VPN, and rotate the password on every shared machine.

To deploy generated configs to a NixOS machine, set your target via environment variables or `config/deploy.secret.exs`:

```bash
export TOMATO_DEPLOY_HOST=your-nixos-host
export TOMATO_DEPLOY_PORT=22
export TOMATO_DEPLOY_USER=root
export TOMATO_DEPLOY_IDENTITY_FILE=~/.ssh/id_ed25519   # recommended
# or — legacy password auth:
# export TOMATO_DEPLOY_PASSWORD=your-password
```

Or copy the example file:

```bash
cp config/deploy.secret.exs.example config/deploy.secret.exs
```

See `config/deploy.secret.exs.example` for the format. This file is gitignored.

## Architecture

```
lib/tomato/
  node.ex              # Node struct — :input/:output/:leaf/:gateway + target + machine meta
  edge.ex              # Directed edge between nodes on same floor
  subgraph.ex          # Self-contained DAG on a floor
  graph.ex             # Top-level container with subgraphs, OODN registry, backend
  oodn.ex              # Out-of-DAG key-value pair
  constraint.ex        # DAG validation — cycles, structure, edges
  walker.ex            # Topological traversal + OODN interpolation + per-machine overlay + target filter
  template_library.ex  # Predefined NixOS + Home Manager templates (leaf + gateway stacks)
  demo.ex              # Seeds default, multi-machine, and home-manager demo graphs
  backend/
    flake.ex           # Generates flake.nix with inputs/outputs/nixosConfigurations/homeConfigurations
  store.ex             # GenServer facade — lifecycle + thin handle_call dispatch
  store/
    state.ex           # %State{} struct + history operations (push/undo/redo)
    mutations.ex       # Pure graph mutations (add/remove/update node, edge, gateway, set_backend)
    oodn.ex            # Pure OODN mutations (put/remove/update/move)
    machine.ex         # Pure add/3 for machine gateways (+ oodn_overrides)
    persistence.ex     # JSON encode/decode + flush_to_disk + peek_graph_name
    graph_files.ex     # list / load / new / save_as / delete / load_latest_or_create / slugify
  deploy.ex            # Public deploy API — delegates to the submodules below
  deploy/
    config.ex          # merge_config + credential resolution (identity_file > env > ~/.ssh > password)
    ssh.ex             # connect (key or password auth), disconnect, exec, collect_output
    sftp.ex            # upload, read_file
    rebuild.ex         # rebuild_command, apply_config
    diff.ex            # simple_diff

lib/tomato_web/
  live/
    graph_live.ex              # Main LiveView — mount, render, event routing, modals
    graph_live/
      canvas_components.ex     # SVG function components — graph_node, edge_line, oodn_node
                               #   + style helpers (node_color, node_rect_class, has_content?, ...)

assets/js/
  hooks/graph_canvas.js  # Drag, zoom/pan, long-press context menu, Bezier edges
```

### Persistence

Each graph is a single JSON file in `priv/graphs/`. The Graph Manager (click filename in sidebar) lets you create, load, save-as, and delete graphs. The JSON file is the source of truth — loaded into memory on startup, flushed on every mutation with 200ms debounce.

### Undo / Redo

The Store keeps a bounded history of the last 50 graph snapshots. Every mutation (add/remove/update node, edge, OODN, machine, backend toggle) pushes the prior state. OODN position drag is excluded from history to avoid noise.

### DAG Constraints

Enforced on every mutation: no cycles (Kahn's algorithm), single `:input`/`:output` per subgraph, edges same-floor only, gateway-subgraph integrity.

## Development

```bash
mix deps.get            # install dependencies
mix compile             # compile
mix phx.server          # start dev server at localhost:4001
iex -S mix phx.server   # start with interactive shell
mix test                # run the test suite
mix format              # format code
```

## Requirements

- Elixir 1.15+
- Erlang/OTP 26+
- **Nix 2.18+ with flakes enabled** on any host that will rebuild generated output. Add `experimental-features = nix-command flakes` to `/etc/nix/nix.conf` (or `~/.config/nix/nix.conf`). Tomato's default flake input pins `nixpkgs` to the `nixos-unstable` channel via `input_nixpkgs = github:nixos/nixpkgs?ref=nixos-unstable` — override the OODN if you want a stable channel.

## Roadmap

**v0.3 — paying down technical debt + small correctness fixes.** Landed in the current `v0.3` branch:

- ✅ `Tomato.Deploy` split into `Deploy.SSH` / `SFTP` / `Rebuild` / `Diff` / `Config`
- ✅ SSH public-key authentication (with password fallback)
- ✅ `Tomato.Store` split into `Store.State` / `Mutations` / `OODN` / `Machine` / `Persistence` / `GraphFiles`
- ✅ Seeder fix — demo graphs seed independently of each other
- ✅ Leaf `target` field + walker filter for shared multi-machine fragments
- ✅ Per-machine `oodn_overrides` overlay
- ✅ `TomatoWeb.GraphLive` phase 4a — canvas SVG components extracted to `GraphLive.CanvasComponents`

Still pending for v0.3:

- ⏳ Sidebar editor for leaf `target` field
- ⏳ Scoped OODN panel inside each machine subgraph (visual editor for `oodn_overrides`)
- ⏳ `TomatoWeb.GraphLive` phase 4b — modal components extracted to `GraphLive.ModalComponents`
- ⏳ `TomatoWeb.GraphLive` phase 4c — handle_event dispatch split into per-domain handler modules
- ⏳ Local Nix-fragment validation (`nix-instantiate --parse` on each leaf before write)
- ⏳ Windows dev-server zombie BEAM on restart (install a shutdown signal handler in `Tomato.Application`)

Full plan and scoring in [docs/REFACTOR_v0.3.md](docs/REFACTOR_v0.3.md). The v0.2 plan that shipped the flake backend, multi-machine support, and Home Manager is archived in [docs/ROADMAP_v0.2.md](docs/ROADMAP_v0.2.md).

## License

Apache License 2.0 — Copyright 2026 Alessio Battistutta. See [LICENSE](LICENSE).
